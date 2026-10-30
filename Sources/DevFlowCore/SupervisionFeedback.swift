import Foundation

public enum SupervisionFeedback {
    public static func compose(targetID: String, plan: SupervisionPlan, assessment: SupervisionAssessment?, records: [ActivityRecord]) -> String {
        var title = targetID
        var context: [String] = []
        var refs: [String] = []
        if let value = plan.requirements.first(where: { $0.id == targetID }) {
            title = value.title; context = ["原话：\(value.originalText)", "拆解：\(value.details)", "范围：\(value.scope.joined(separator: "；"))", "假设：\(value.assumptions.joined(separator: "；"))"]; refs = value.recordIDs
        } else if let value = plan.criteria.first(where: { $0.id == targetID }) {
            title = value.title; context = ["需求：\(value.requirementID)", "验收预期：\(value.expected)", "要求层级：\(value.requiredLevel.title)"]
        } else if let value = plan.tasks.first(where: { $0.id == targetID }) {
            title = value.title; context = ["验收：\(value.criterionIDs.joined(separator: ", "))", "记录的任务状态：\(value.status.rawValue)"]; refs = value.recordIDs
        } else if let value = plan.testCases.first(where: { $0.id == targetID }) {
            title = value.title; context = ["测试输入：\(value.input)", "预期：\(value.expected)", "验证层级：\(value.level.title)", "关联验收：\(value.criterionIDs.joined(separator: ", "))"]
        } else if let value = plan.executions.first(where: { $0.id == targetID }) {
            title = "执行 \(value.id)"; context = ["用例：\(value.testCaseID)", "命令：\(value.command)", "环境：\(value.environment)", "时间：\(value.occurredAt ?? "未记录")", "原记录结果：\(value.result.rawValue)", "日志：\(value.log?.path ?? "缺失")"]; refs = value.recordIDs
        } else if let value = plan.issues.first(where: { $0.id == targetID }) {
            title = value.title; context = ["根因：\(value.rootCause ?? "尚未记录")", "之前漏检原因：\(value.missedCheckCause ?? "尚未记录")", "复验：\(value.verificationExecutionIDs.joined(separator: ", "))", "声明已关闭：\(value.declaredClosed ? "是，仍需核查证据" : "否")"]; refs = value.fixRecordIDs
        } else if let value = plan.artifacts.first(where: { $0.id == targetID }) {
            title = value.title; context = ["产物：\(value.path)", "SHA-256：\(value.sha256 ?? "未记录")", "关联执行：\(value.executionIDs.joined(separator: ", "))"]; refs = value.recordIDs
        }
        let findings = (assessment?.requirements ?? []) + (assessment?.criteria ?? []) + (assessment?.artifacts ?? [])
        if let value = findings.first(where: { $0.id == targetID }) { context += ["当前核对：\(value.state.title)"] + value.reasons + ["依据执行：\(value.evidenceIDs.joined(separator: ", "))"] }
        if let value = assessment?.executions.first(where: { $0.id == targetID }) { context += ["当前核对：\(value.state.title)"] + value.reasons }
        if let value = assessment?.issues.first(where: { $0.id == targetID }) { context += ["复验关闭核对：\(value.state.rawValue)"] + value.reasons }
        let sources = refs.prefix(10).map { id -> String in
            guard let row = records.first(where: { $0.id == id }) else { return "- \(id)：关联记录尚未接入" }
            return "- \(id)：\(row.title)；\(row.source.path)\(row.source.line.map { ":\($0)" } ?? "")（\(row.origin.title)）"
        }
        return "项目：\(plan.title)\n监督对象：\(targetID) · \(title)\n计划版本：\(plan.version)\n\n当前依据与范围：\n\(context.joined(separator: "\n"))\n\n可回查记录：\n\(sources.isEmpty ? "尚无直接原始记录；请补充，不推断已经执行。" : sources.joined(separator: "\n"))\n\n希望智能体处理：\n请核对上述差异及其对当前需求的影响，说明实际修改和对应验证，保留原失败与未验证范围。\n\n我的具体要求：\n\n此文本由我手动带回开发聊天；保存或复制不表示送达、执行或问题已解决。\n"
    }
}
