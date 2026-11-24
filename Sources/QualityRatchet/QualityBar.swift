import Foundation

/// Which side of the limit a measurement has to land on.
public enum Direction: String, Sendable, Hashable, CaseIterable {
    /// The value must be less than or equal to the limit (memory, launch time, audit failures).
    case atMost
    /// The value must be greater than or equal to the limit (coverage of failure modes).
    case atLeast

    var symbol: String { self == .atMost ? "≤" : "≥" }
}

/// A quality pass a person or an agent runs on a checkpoint before it can ship.
public enum QualityPass: String, Sendable, Hashable, CaseIterable {
    case failureModes
    case performanceBudget
    case accessibility
    case staffReview

    public var title: String {
        switch self {
        case .failureModes: "Failure-mode enumeration"
        case .performanceBudget: "Performance budget"
        case .accessibility: "Accessibility"
        case .staffReview: "Staff-reviewer pass"
        }
    }
}

public enum QualityRatchetError: Error, Equatable, Sendable {
    case emptyField(String)
    case nonFiniteLimit(barID: String)
    case duplicateBarID(String)
    case noBars
    case headroomOutOfRange(Double)
    case cannotRatchetFromHeldCheckpoint(checkpointID: String)
}

/// One measurable quality bar with a named owner.
///
/// A bar is the unit of the quality budget: if nobody owns it and nothing measures it,
/// it is a wish, not a budget line.
public struct QualityBar: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let unit: String
    public let direction: Direction
    public let limit: Double
    public let owner: String
    /// The quality pass whose prompt lists this bar.
    public let pass: QualityPass

    public init(
        id: String,
        name: String,
        unit: String,
        direction: Direction,
        limit: Double,
        owner: String,
        pass: QualityPass
    ) throws {
        for (field, value) in [("id", id), ("name", name), ("unit", unit), ("owner", owner)]
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw QualityRatchetError.emptyField(field)
        }
        guard limit.isFinite else { throw QualityRatchetError.nonFiniteLimit(barID: id) }
        self.id = id
        self.name = name
        self.unit = unit
        self.direction = direction
        self.limit = limit
        self.owner = owner
        self.pass = pass
    }

    /// True when `value` lands on the allowed side of the limit. Non-finite values never meet a bar.
    public func isMet(by value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch direction {
        case .atMost: return value <= limit
        case .atLeast: return value >= limit
        }
    }

    /// A copy of this bar with a different limit. Internal: only the ratchet moves limits.
    func with(limit newLimit: Double) -> QualityBar {
        // Safe: every stored field was already validated, and the ratchet only produces finite limits.
        QualityBar(validatedID: id, name: name, unit: unit, direction: direction,
                   limit: newLimit, owner: owner, pass: pass)
    }

    private init(validatedID id: String, name: String, unit: String, direction: Direction,
                 limit: Double, owner: String, pass: QualityPass) {
        self.id = id
        self.name = name
        self.unit = unit
        self.direction = direction
        self.limit = limit
        self.owner = owner
        self.pass = pass
    }

    /// "Peak memory (P50) ≤ 250 MB".
    public var summary: String { "\(name) \(direction.symbol) \(NumberText.format(limit)) \(unit)" }
}

enum NumberText {
    /// Up to two decimals, with trailing zeros dropped: 250 → "250", 209.00000000000003 → "209", 209.5 → "209.5".
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return String(value) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}
