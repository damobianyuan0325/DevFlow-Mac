import Foundation

public enum ExecutionPresentationTone: Equatable {
    case neutral, verified, caution, failure
}

/// Presentation only. Never changes the recorded outcome, assessment state or acceptance gate.
public struct ExecutionPresentation: Equatable {
    public let title: String
    public let recordedResult: String
    public let exitStatus: String
    public let explanation: String?
    public let tone: ExecutionPresentationTone

    public init(execution: VerificationExecution, state: SupervisionState?) {
        recordedResult = "记录结果：" + execution.result.title
        exitStatus = execution.exitCode.map { "命令退出码：\($0)" + ($0 == 0 ? "" : "（非零）") } ?? "命令退出码：未知"
        let hasFailedCount = (execution.counts?.failed ?? 0) > 0
        let hasFailureRecord = execution.result == .failed || hasFailedCount
        let nonzeroExit = execution.exitCode.map { $0 != 0 } ?? false

        if state == .failed && hasFailureRecord {
            title = execution.result == .failed ? "核验未通过 · 有失败记录" : "核验未通过 · 有失败计数"
            tone = .failure
        } else if state == .failed && nonzeroExit {
            title = "核验未通过 · 非零退出"
            tone = .caution
        } else {
            title = state?.title ?? "尚未核查"
            tone = state == .satisfied ? .verified : (state == nil ? .neutral : .caution)
        }
        if nonzeroExit && !hasFailureRecord {
            if execution.result == .passed {
                explanation = "通过声明与非零退出码冲突，本次不能计为有效通过；需核对命令约定与原始日志，不能直接推断产品运行失败。"
            } else {
                explanation = "记录结果仍为“\(execution.result.title)”。非零退出使本次核验不能通过；仅凭退出码不能判定产品运行失败，需核对命令约定与原始日志。"
            }
        } else if hasFailureRecord {
            explanation = "导入记录声明失败或包含失败计数；失败范围和原因须结合原始日志核对，不代表整个产品都不可用。"
        } else { explanation = nil }
    }
}

public extension VerificationResult {
    var title: String {
        switch self {
        case .passed: return "通过"
        case .failed: return "失败"
        case .unknown: return "未知"
        case .notRun: return "未运行"
        case .blocked: return "受阻"
        }
    }
}
