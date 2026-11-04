import SwiftUI
import DevFlowCore

/// Shared by execution cards and the isolated inspection sheet.
struct ExecutionStatusSummary: View {
    let execution: VerificationExecution
    let state: SupervisionState?

    var body: some View {
        let display = ExecutionPresentation(execution: execution, state: state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SmallBadge(text: display.title, color: color(display.tone))
                SmallBadge(text: display.recordedResult, color: .secondary)
                SmallBadge(text: display.exitStatus, color: .secondary)
            }
            if let explanation = display.explanation {
                Text(explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func color(_ tone: ExecutionPresentationTone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .verified: return DevFlowStyle.accent
        case .caution: return .orange
        case .failure: return .red
        }
    }
}
