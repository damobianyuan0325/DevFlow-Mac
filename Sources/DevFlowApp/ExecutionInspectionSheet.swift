import SwiftUI
import DevFlowCore

/// Freeze the selected plan at click time; a background refresh cannot change this report's scope.
struct ExecutionInspectionRequest: Identifiable {
    let id = UUID()
    let plan: SupervisionPlan
    let root: String
    let records: [ActivityRecord]
    let executionID: String
}

struct ExecutionInspectionSheet: View {
    let request: ExecutionInspectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var result: ExecutionAssessment?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("单独核验执行").font(.title2.bold())
            Text(request.executionID).font(.body.monospaced()).textSelection(.enabled)
            Text("按打开时的计划 \(request.plan.version) 与本次读取到的来源核验。结果不代表最新执行、需求验收或问题已关闭；重新打开可再次检查。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let result {
                        Text(result.state.title).font(.headline)
                        ForEach(Array(result.reasons.enumerated()), id: \.offset) { _, reason in
                            Text(reason).textSelection(.enabled)
                        }
                    } else if let failure { Text(failure).foregroundStyle(.orange).textSelection(.enabled) }
                    else { ProgressView("正在读取该执行的证据…") }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 620, height: 420)
        .buttonStyle(HandButtonStyle(base: DefaultButtonStyle()))
        .task {
            let captured = request
            let checked = await Task.detached(priority: .userInitiated) {
                Result { try SupervisionEvaluator.inspectExecution(plan: captured.plan, root: captured.root, records: captured.records, executionID: captured.executionID) }
            }.value
            guard !Task.isCancelled else { return }
            switch checked {
            case .success(let execution): result = execution
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}
