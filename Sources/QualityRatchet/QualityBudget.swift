import Foundation

/// One small, reviewable unit of agent work (a PR-sized checkpoint), with what was measured
/// and the evidence that each quality pass actually ran.
public struct Checkpoint: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Bar id → measured value. These numbers are reported by the team's own tooling;
    /// the gate checks them, it does not produce them.
    public let measurements: [String: Double]
    /// Pass → a link or note showing the pass ran (a PR comment, a test run, an audit report).
    public let evidence: [QualityPass: String]

    public init(id: String, title: String, measurements: [String: Double], evidence: [QualityPass: String]) {
        self.id = id
        self.title = title
        self.measurements = measurements
        self.evidence = evidence
    }
}

/// Why a checkpoint is held.
public enum Finding: Sendable, Hashable, CustomStringConvertible {
    case missingMeasurement(barID: String)
    case invalidMeasurement(barID: String)
    case overBudget(barID: String, value: Double, limit: Double)
    /// A measurement whose id matches no bar, usually a typo that would otherwise hide a missing number.
    case unknownMeasurement(id: String)
    case missingEvidence(QualityPass)

    public var description: String {
        switch self {
        case .missingMeasurement(let id): "No measurement for \(id)"
        case .invalidMeasurement(let id): "Measurement for \(id) is not a finite number"
        case .overBudget(let id, let value, let limit):
            "\(id): \(NumberText.format(value)) misses the limit of \(NumberText.format(limit))"
        case .unknownMeasurement(let id): "Measurement \(id) matches no bar in the budget"
        case .missingEvidence(let pass): "No evidence that the \(pass.title.lowercased()) ran"
        }
    }
}

public enum Verdict: Sendable, Hashable {
    case ship
    case hold([Finding])

    public var isShippable: Bool { self == .ship }
    public var findings: [Finding] {
        if case .hold(let findings) = self { return findings }
        return []
    }
}

/// A limit the ratchet tightened.
public struct RatchetChange: Sendable, Hashable {
    public let barID: String
    public let oldLimit: Double
    public let newLimit: Double
}

/// The quality budget: the bars a team commits to, who owns each one, and which passes must
/// leave evidence before a checkpoint ships.
public struct QualityBudget: Sendable, Hashable {
    public let bars: [QualityBar]
    public let requiredPasses: Set<QualityPass>

    public init(bars: [QualityBar], requiredPasses: Set<QualityPass>) throws {
        guard !bars.isEmpty else { throw QualityRatchetError.noBars }
        var seen = Set<String>()
        for bar in bars {
            guard seen.insert(bar.id).inserted else { throw QualityRatchetError.duplicateBarID(bar.id) }
        }
        self.bars = bars
        self.requiredPasses = requiredPasses
    }

    public func bar(_ id: String) -> QualityBar? { bars.first { $0.id == id } }

    /// Holds the checkpoint unless every bar has a finite measurement inside its limit,
    /// no measurement is unaccounted for, and every required pass left non-empty evidence.
    /// Findings come out in a stable order: bars in budget order, then unknown ids sorted,
    /// then passes in declaration order.
    public func evaluate(_ checkpoint: Checkpoint) -> Verdict {
        var findings: [Finding] = []
        for bar in bars {
            guard let value = checkpoint.measurements[bar.id] else {
                findings.append(.missingMeasurement(barID: bar.id))
                continue
            }
            guard value.isFinite else {
                findings.append(.invalidMeasurement(barID: bar.id))
                continue
            }
            if !bar.isMet(by: value) {
                findings.append(.overBudget(barID: bar.id, value: value, limit: bar.limit))
            }
        }
        let known = Set(bars.map(\.id))
        for id in checkpoint.measurements.keys.sorted() where !known.contains(id) {
            findings.append(.unknownMeasurement(id: id))
        }
        for pass in QualityPass.allCases where requiredPasses.contains(pass) {
            let note = checkpoint.evidence[pass]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if note.isEmpty { findings.append(.missingEvidence(pass)) }
        }
        return findings.isEmpty ? .ship : .hold(findings)
    }

    /// Tightens each bar toward what a shipped checkpoint actually achieved, plus `headroom`
    /// (0.1 = 10% slack for noise). A limit only ever moves in the stricter direction, so a
    /// gain that has shipped cannot quietly leak back in a later checkpoint.
    ///
    /// Throws if the checkpoint does not ship against this budget: numbers from a held
    /// checkpoint never move a bar.
    public func ratcheted(by checkpoint: Checkpoint, headroom: Double) throws -> (budget: QualityBudget, changes: [RatchetChange]) {
        guard headroom.isFinite, (0...1).contains(headroom) else {
            throw QualityRatchetError.headroomOutOfRange(headroom)
        }
        guard evaluate(checkpoint).isShippable else {
            throw QualityRatchetError.cannotRatchetFromHeldCheckpoint(checkpointID: checkpoint.id)
        }
        var changes: [RatchetChange] = []
        let newBars = bars.map { bar -> QualityBar in
            // evaluate() returned .ship, so every bar has a finite measurement.
            guard let value = checkpoint.measurements[bar.id] else { return bar }
            let slack = abs(value) * headroom
            let tightened: Double
            switch bar.direction {
            case .atMost: tightened = min(bar.limit, value + slack)
            case .atLeast: tightened = max(bar.limit, value - slack)
            }
            guard tightened != bar.limit else { return bar }
            changes.append(RatchetChange(barID: bar.id, oldLimit: bar.limit, newLimit: tightened))
            return bar.with(limit: tightened)
        }
        // Same ids as self, so this cannot fail; `try` keeps validation in one place.
        return (try QualityBudget(bars: newBars, requiredPasses: requiredPasses), changes)
    }
}
