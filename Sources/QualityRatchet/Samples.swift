import Foundation

/// Illustrative sample data for the demo app and tests. The numbers are made up, per screen,
/// for the demo; they are not anyone's production data. The 190 MB only echoes Shopify's
/// app-wide iOS P50 peak-memory figure.
public enum Samples {
    public static func budget() throws -> QualityBudget {
        try QualityBudget(
            bars: [
                QualityBar(id: "peak-memory", name: "Peak memory (P50)", unit: "MB",
                           direction: .atMost, limit: 250, owner: "Performance owner",
                           pass: .performanceBudget),
                QualityBar(id: "cold-launch", name: "Cold launch (P50)", unit: "ms",
                           direction: .atMost, limit: 650, owner: "Performance owner",
                           pass: .performanceBudget),
                QualityBar(id: "a11y-failures", name: "Accessibility audit failures", unit: "issues",
                           direction: .atMost, limit: 0, owner: "Accessibility owner",
                           pass: .accessibility),
                QualityBar(id: "failure-mode-tests", name: "Failure modes with a test", unit: "%",
                           direction: .atLeast, limit: 90, owner: "Pod lead",
                           pass: .failureModes),
            ],
            requiredPasses: Set(QualityPass.allCases)
        )
    }

    static let fullEvidence: [QualityPass: String] = [
        .failureModes: "PR comment: 8 failure modes, 8 tests",
        .performanceBudget: "Instruments trace attached to the PR",
        .accessibility: "Accessibility Inspector audit, 0 issues",
        .staffReview: "Agent review: 2 findings, both fixed",
    ]

    /// Inside every bar, with every pass evidenced: ships, and tightens two bars when ratcheted.
    public static let ordersList = Checkpoint(
        id: "orders-list", title: "Orders list",
        measurements: ["peak-memory": 190, "cold-launch": 560, "a11y-failures": 0, "failure-mode-tests": 100],
        evidence: fullEvidence)

    /// Over the memory bar: held.
    public static let orderDetail = Checkpoint(
        id: "order-detail", title: "Order detail",
        measurements: ["peak-memory": 310, "cold-launch": 600, "a11y-failures": 0, "failure-mode-tests": 92],
        evidence: fullEvidence)

    /// No accessibility number and no staff-review evidence: held for both.
    public static let refundFlow = Checkpoint(
        id: "refund-flow", title: "Refund flow",
        measurements: ["peak-memory": 205, "cold-launch": 610, "failure-mode-tests": 95],
        evidence: fullEvidence.filter { $0.key != .staffReview })

    /// A later change to the orders list. It passes the original 250 MB bar, but not the bar
    /// the ratchet set after `ordersList` shipped at 190 MB.
    public static let ordersListFollowUp = Checkpoint(
        id: "orders-list-filters", title: "Orders list: filters",
        measurements: ["peak-memory": 230, "cold-launch": 590, "a11y-failures": 0, "failure-mode-tests": 95],
        evidence: fullEvidence)

    public static let checkpoints = [ordersList, orderDetail, refundFlow]

    /// The slack the demo ratchet leaves above (or below) a shipped measurement.
    public static let headroom = 0.10
}
