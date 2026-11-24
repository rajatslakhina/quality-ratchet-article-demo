import SwiftUI
import QualityRatchet

@main
struct QualityRatchetDemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Launch argument used by Scripts/simulator-screenshots.sh:
///   -tab gate|ratchet|prompt    which tab to open
struct RootView: View {
    @State private var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "gate"

    var body: some View {
        switch DemoModel.load() {
        case .success(let model):
            TabView(selection: $tab) {
                NavigationStack { GateView(model: model) }
                    .tabItem { Label("Gate", systemImage: "checkmark.shield") }
                    .tag("gate")
                NavigationStack { RatchetView(model: model) }
                    .tabItem { Label("Ratchet", systemImage: "arrow.down.right.circle") }
                    .tag("ratchet")
                NavigationStack { PromptView(model: model) }
                    .tabItem { Label("Prompt", systemImage: "text.bubble") }
                    .tag("prompt")
            }
        case .failure(let error):
            Text("Could not build the sample budget: \(String(describing: error))").padding()
        }
    }
}

struct DemoModel {
    let budget: QualityBudget
    let ratcheted: QualityBudget
    let changes: [RatchetChange]

    static func load() -> Result<DemoModel, Error> {
        Result {
            let budget = try Samples.budget()
            let (ratcheted, changes) = try budget.ratcheted(by: Samples.ordersList, headroom: Samples.headroom)
            return DemoModel(budget: budget, ratcheted: ratcheted, changes: changes)
        }
    }
}

struct GateView: View {
    let model: DemoModel

    var body: some View {
        List {
            Section("Budget") {
                ForEach(model.budget.bars) { bar in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bar.summary).font(.subheadline.weight(.semibold))
                        Text("\(bar.owner) · \(bar.pass.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Checkpoints") {
                ForEach(Samples.checkpoints) { checkpoint in
                    VerdictRow(title: checkpoint.title, verdict: model.budget.evaluate(checkpoint))
                }
            }
        }
        .navigationTitle("Quality gate")
    }
}

struct VerdictRow: View {
    let title: String
    let verdict: Verdict

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(verdict.isShippable ? "SHIP" : "HOLD")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(verdict.isShippable ? Color.green.opacity(0.2) : Color.red.opacity(0.2), in: Capsule())
                    .foregroundStyle(verdict.isShippable ? Color.green : Color.red)
            }
            ForEach(verdict.findings, id: \.self) { finding in
                Text("• \(finding.description)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RatchetView: View {
    let model: DemoModel

    var body: some View {
        List {
            Section("After “\(Samples.ordersList.title)” shipped (\(Int((Samples.headroom * 100).rounded()))% headroom)") {
                ForEach(model.changes, id: \.barID) { change in
                    let name = model.budget.bar(change.barID)?.name ?? change.barID
                    let unit = model.budget.bar(change.barID)?.unit ?? ""
                    HStack {
                        Text(name)
                        Spacer()
                        Text("\(format(change.oldLimit)) → \(format(change.newLimit))\(unit == "%" ? "%" : " " + unit)")
                            .monospacedDigit().foregroundStyle(.blue)
                    }
                }
                Text("Bars it didn't beat by more than the headroom stay where they were.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Next change: “\(Samples.ordersListFollowUp.title)”, \(followUpMemory)") {
                VerdictRow(title: "Against the original budget", verdict: model.budget.evaluate(Samples.ordersListFollowUp))
                VerdictRow(title: "Against the ratcheted budget", verdict: model.ratcheted.evaluate(Samples.ordersListFollowUp))
            }
        }
        .navigationTitle("Ratchet")
    }

    private var followUpMemory: String {
        Samples.ordersListFollowUp.measurements["peak-memory"].map { "\(format($0)) MB" } ?? "memory not measured"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct PromptView: View {
    let model: DemoModel

    var body: some View {
        ScrollView {
            Text(PassPrompt.render(.performanceBudget, checkpoint: Samples.ordersListFollowUp.title, budget: model.ratcheted))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Pass prompt")
    }
}
