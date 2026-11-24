import Testing
@testable import QualityRatchet

private func bar(_ id: String, _ direction: Direction = .atMost, limit: Double,
                 pass: QualityPass = .performanceBudget) throws -> QualityBar {
    try QualityBar(id: id, name: id, unit: "u", direction: direction, limit: limit, owner: "Owner", pass: pass)
}

private let evidenceForAll: [QualityPass: String] = Dictionary(
    uniqueKeysWithValues: QualityPass.allCases.map { ($0, "evidence") })

@Suite("QualityBar")
struct QualityBarTests {
    @Test func atMostIncludesTheLimit() throws {
        let b = try bar("m", limit: 250)
        #expect(b.isMet(by: 250))
        #expect(b.isMet(by: 249.9))
        #expect(!b.isMet(by: 250.01))
    }

    @Test func atLeastIncludesTheLimit() throws {
        let b = try bar("c", .atLeast, limit: 90)
        #expect(b.isMet(by: 90))
        #expect(!b.isMet(by: 89.99))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteValuesNeverMeetABar(value: Double) throws {
        #expect(!(try bar("m", limit: 250)).isMet(by: value))
        #expect(!(try bar("c", .atLeast, limit: 0)).isMet(by: value))
    }

    @Test func rejectsEmptyOwnerAndNonFiniteLimit() {
        #expect(throws: QualityRatchetError.emptyField("owner")) {
            try QualityBar(id: "m", name: "m", unit: "MB", direction: .atMost, limit: 1, owner: "  ", pass: .staffReview)
        }
        #expect(throws: QualityRatchetError.nonFiniteLimit(barID: "m")) {
            try QualityBar(id: "m", name: "m", unit: "MB", direction: .atMost, limit: .nan, owner: "o", pass: .staffReview)
        }
    }

    @Test func numberTextDropsFloatingPointNoise() {
        #expect(NumberText.format(190 * 1.1) == "209")
        #expect(NumberText.format(-0.001) == "0")
        #expect(NumberText.format(0.25) == "0.25")
    }

    @Test func summaryFormatsWholeAndFractionalLimits() throws {
        #expect(try bar("m", limit: 250).summary == "m ≤ 250 u")
        let percent = try QualityBar(id: "p", name: "Covered", unit: "%", direction: .atLeast, limit: 90,
                                     owner: "o", pass: .failureModes)
        #expect(percent.summary == "Covered ≥ 90%")
        #expect(try bar("m", .atLeast, limit: 209.5).summary == "m ≥ 209.5 u")
    }
}

@Suite("QualityBudget.evaluate")
struct EvaluateTests {
    @Test func rejectsEmptyAndDuplicateBudgets() throws {
        #expect(throws: QualityRatchetError.noBars) { try QualityBudget(bars: [], requiredPasses: []) }
        let m = try bar("m", limit: 1)
        #expect(throws: QualityRatchetError.duplicateBarID("m")) { try QualityBudget(bars: [m, m], requiredPasses: []) }
    }

    @Test func sampleVerdicts() throws {
        let budget = try Samples.budget()
        #expect(budget.evaluate(Samples.ordersList) == .ship)
        #expect(budget.evaluate(Samples.orderDetail) == .hold([.overBudget(barID: "peak-memory", value: 310, limit: 250)]))
        #expect(budget.evaluate(Samples.refundFlow) == .hold([
            .missingMeasurement(barID: "a11y-failures"),
            .missingEvidence(.staffReview),
        ]))
        #expect(budget.evaluate(Samples.ordersListFollowUp) == .ship)
    }

    @Test func findingDescriptionIsUsedForInterpolation() {
        let finding = Finding.overBudget(barID: "peak-memory", value: 230, limit: 209.00000000000003)
        #expect("\(finding)" == "peak-memory: 230 misses the limit of 209")
    }

    @Test func whitespaceEvidenceCountsAsMissing() throws {
        let budget = try QualityBudget(bars: [bar("m", limit: 10)], requiredPasses: [.staffReview])
        let c = Checkpoint(id: "c", title: "c", measurements: ["m": 1], evidence: [.staffReview: " \n "])
        #expect(budget.evaluate(c) == .hold([.missingEvidence(.staffReview)]))
    }

    @Test func onlyRequiredPassesNeedEvidence() throws {
        let budget = try QualityBudget(bars: [bar("m", limit: 10)], requiredPasses: [.performanceBudget])
        let c = Checkpoint(id: "c", title: "c", measurements: ["m": 1], evidence: [.performanceBudget: "trace"])
        #expect(budget.evaluate(c) == .ship)
    }

    @Test func nonFiniteMeasurementIsHeldAsInvalidNotAsOverBudget() throws {
        let budget = try QualityBudget(bars: [bar("m", limit: 10)], requiredPasses: [])
        let c = Checkpoint(id: "c", title: "c", measurements: ["m": .nan], evidence: [:])
        #expect(budget.evaluate(c) == .hold([.invalidMeasurement(barID: "m")]))
    }

    @Test func typoInAMeasurementIdIsReportedNotIgnored() throws {
        let budget = try QualityBudget(bars: [bar("peak-memory", limit: 250)], requiredPasses: [])
        let c = Checkpoint(id: "c", title: "c", measurements: ["peak-memroy": 100], evidence: [:])
        #expect(budget.evaluate(c) == .hold([
            .missingMeasurement(barID: "peak-memory"),
            .unknownMeasurement(id: "peak-memroy"),
        ]))
    }

    @Test func findingsAreInStableOrder() throws {
        let budget = try QualityBudget(
            bars: [bar("b", limit: 1), bar("a", limit: 1)], requiredPasses: Set(QualityPass.allCases))
        let c = Checkpoint(id: "c", title: "c", measurements: ["b": 2, "z": 0, "y": 0], evidence: [:])
        #expect(budget.evaluate(c).findings == [
            .overBudget(barID: "b", value: 2, limit: 1),
            .missingMeasurement(barID: "a"),
            .unknownMeasurement(id: "y"),
            .unknownMeasurement(id: "z"),
            .missingEvidence(.failureModes),
            .missingEvidence(.performanceBudget),
            .missingEvidence(.accessibility),
            .missingEvidence(.staffReview),
        ])
    }
}

@Suite("QualityBudget.ratcheted")
struct RatchetTests {
    @Test func sampleRatchetTightensMemoryAndLaunchOnly() throws {
        let (ratcheted, changes) = try Samples.budget().ratcheted(by: Samples.ordersList, headroom: Samples.headroom)
        #expect(changes.count == 2)
        let memory = try #require(changes.first { $0.barID == "peak-memory" })
        #expect(memory.oldLimit == 250)
        #expect(abs(memory.newLimit - 209) < 1e-9)
        let launch = try #require(changes.first { $0.barID == "cold-launch" })
        #expect(abs(launch.newLimit - 616) < 1e-9)
        #expect(ratcheted.bar("a11y-failures")?.limit == 0)
        #expect(ratcheted.bar("failure-mode-tests")?.limit == 90)
        #expect(ratcheted.requiredPasses == Set(QualityPass.allCases))
    }

    @Test func followUpPassesTheOldBarButNotTheRatchetedOne() throws {
        let original = try Samples.budget()
        let (ratcheted, _) = try original.ratcheted(by: Samples.ordersList, headroom: Samples.headroom)
        #expect(original.evaluate(Samples.ordersListFollowUp) == .ship)
        let verdict = ratcheted.evaluate(Samples.ordersListFollowUp)
        #expect(verdict.findings.count == 1)
        guard case .overBudget(let id, let value, let limit) = try #require(verdict.findings.first) else {
            Issue.record("expected overBudget, got \(verdict)")
            return
        }
        #expect(id == "peak-memory")
        #expect(value == 230)
        #expect(abs(limit - 209) < 1e-9)
    }

    @Test func limitsNeverLoosen() throws {
        let budget = try QualityBudget(
            bars: [bar("m", limit: 100), bar("c", .atLeast, limit: 90)], requiredPasses: [])
        // Both values only just meet their bars, so headroom would move the limits the wrong way.
        let c = Checkpoint(id: "c", title: "c", measurements: ["m": 100, "c": 90], evidence: [:])
        let (ratcheted, changes) = try budget.ratcheted(by: c, headroom: 0.5)
        #expect(changes.isEmpty)
        #expect(ratcheted == budget)
    }

    @Test func atLeastBarTightensUpward() throws {
        let budget = try QualityBudget(bars: [bar("c", .atLeast, limit: 80)], requiredPasses: [])
        let c = Checkpoint(id: "c", title: "c", measurements: ["c": 100], evidence: [:])
        let (ratcheted, changes) = try budget.ratcheted(by: c, headroom: 0.05)
        #expect(changes.count == 1)
        #expect(changes.first?.oldLimit == 80)
        #expect(abs((ratcheted.bar("c")?.limit ?? 0) - 95) < 1e-9)
    }

    @Test func zeroHeadroomLocksTheShippedValue() throws {
        let budget = try QualityBudget(bars: [bar("m", limit: 250)], requiredPasses: [])
        let c = Checkpoint(id: "c", title: "c", measurements: ["m": 190], evidence: [:])
        #expect(try budget.ratcheted(by: c, headroom: 0).budget.bar("m")?.limit == 190)
    }

    @Test func negativeValuesStillGetSlackInTheLooserDirection() throws {
        // e.g. a "change in crash rate" bar where negative is good.
        let budget = try QualityBudget(bars: [bar("d", limit: 0)], requiredPasses: [])
        let c = Checkpoint(id: "c", title: "c", measurements: ["d": -10], evidence: [:])
        let limit = try #require(try budget.ratcheted(by: c, headroom: 0.1).budget.bar("d")?.limit)
        #expect(abs(limit - -9) < 1e-9)
    }

    @Test func heldCheckpointCannotMoveABar() throws {
        #expect(throws: QualityRatchetError.cannotRatchetFromHeldCheckpoint(checkpointID: "order-detail")) {
            try Samples.budget().ratcheted(by: Samples.orderDetail, headroom: 0.1)
        }
        #expect(throws: QualityRatchetError.cannotRatchetFromHeldCheckpoint(checkpointID: "refund-flow")) {
            try Samples.budget().ratcheted(by: Samples.refundFlow, headroom: 0.1)
        }
    }

    @Test(arguments: [-0.01, 1.01, Double.nan, .infinity])
    func headroomOutsideZeroToOneIsRejected(headroom: Double) throws {
        let budget = try Samples.budget()
        do {
            _ = try budget.ratcheted(by: Samples.ordersList, headroom: headroom)
            Issue.record("expected headroomOutOfRange for \(headroom)")
        } catch QualityRatchetError.headroomOutOfRange {
            // expected
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func ratchetingTwiceWithTheSameCheckpointIsStable() throws {
        let (once, _) = try Samples.budget().ratcheted(by: Samples.ordersList, headroom: 0.1)
        let (twice, changes) = try once.ratcheted(by: Samples.ordersList, headroom: 0.1)
        #expect(changes.isEmpty)
        #expect(twice == once)
    }
}

@Suite("PassPrompt")
struct PassPromptTests {
    @Test func performancePromptListsExactlyThePerformanceBars() throws {
        let budget = try Samples.budget()
        let prompt = PassPrompt.render(.performanceBudget, checkpoint: "Order detail", budget: budget)
        #expect(prompt.contains("Checkpoint: Order detail"))
        #expect(prompt.contains("- peak-memory: Peak memory (P50) ≤ 250 MB. Owner: Performance owner."))
        #expect(prompt.contains("- cold-launch: Cold launch (P50) ≤ 650 ms. Owner: Performance owner."))
        #expect(!prompt.contains("a11y-failures"))
        #expect(!prompt.contains("failure-mode-tests"))
        #expect(prompt.contains("Never estimate."))
    }

    @Test func promptFollowsTheRatchetedBudget() throws {
        let (ratcheted, _) = try Samples.budget().ratcheted(by: Samples.ordersList, headroom: 0.1)
        let prompt = PassPrompt.render(.performanceBudget, checkpoint: "Orders list: filters", budget: ratcheted)
        #expect(prompt.contains("Peak memory (P50) ≤ 209 MB"))
        #expect(!prompt.contains("≤ 250 MB"))
    }

    @Test func passWithoutBarsHasNoBarSection() throws {
        let prompt = PassPrompt.render(.staffReview, checkpoint: "Refund flow", budget: try Samples.budget())
        #expect(!prompt.contains("Bars for this pass"))
        #expect(prompt.contains("staff iOS engineer"))
    }

    @Test(arguments: QualityPass.allCases)
    func everyPassForbidsEditsAndEstimates(pass: QualityPass) throws {
        let prompt = PassPrompt.render(pass, checkpoint: "x", budget: try Samples.budget())
        #expect(prompt.hasPrefix("Quality pass: \(pass.title)"))
        #expect(prompt.contains("Do not edit code during this pass."))
        #expect(prompt.contains("Never estimate."))
    }
}
