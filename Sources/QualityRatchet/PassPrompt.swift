import Foundation

/// Renders the instructions for one quality pass from the same budget the gate enforces,
/// so the bars an agent is asked to check are exactly the bars CI holds a checkpoint on.
public enum PassPrompt {
    public static func render(_ pass: QualityPass, checkpoint title: String, budget: QualityBudget) -> String {
        let bars = budget.bars.filter { $0.pass == pass }
        var lines = ["Quality pass: \(pass.title)", "Checkpoint: \(title)", ""]
        lines.append(contentsOf: task(for: pass))
        if !bars.isEmpty {
            lines.append("")
            lines.append("Bars for this pass (report the measured value for each, in its unit):")
            for bar in bars {
                lines.append("- \(bar.id): \(bar.summary). Owner: \(bar.owner).")
            }
        }
        lines.append("")
        lines.append(contentsOf: [
            "Rules:",
            "- Do not edit code during this pass. Report findings only.",
            "- Only report a number you measured, with the command or tool that produced it.",
            "- If you could not measure something, write \"not measured\". Never estimate.",
            "- If you find nothing, say so. Do not invent issues to fill the list.",
        ])
        return lines.joined(separator: "\n")
    }

    static func task(for pass: QualityPass) -> [String] {
        switch pass {
        case .failureModes:
            [
                "List how this change can fail for a real user: offline, slow network, empty data,",
                "very large data, permission denied, app backgrounded mid-request, low memory,",
                "and the largest Dynamic Type size. For each, name the test that covers it or write \"no test\".",
            ]
        case .performanceBudget:
            [
                "Measure this change against the performance bars below on the agreed device and build.",
                "Compare each number with the bar and say which ones miss.",
            ]
        case .accessibility:
            [
                "Audit this change with VoiceOver and the Accessibility Inspector: labels, traits, focus order,",
                "Dynamic Type, contrast, and hit targets smaller than 44 by 44 points. Count every failure.",
            ]
        case .staffReview:
            [
                "Review this diff as a staff iOS engineer would before a human reviewer sees it.",
                "List what that reviewer would reject: the file and line, the rule it breaks,",
                "and the smallest fix.",
            ]
        }
    }
}
