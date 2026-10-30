import Foundation
import DevFlowCore

final class WorkspaceTests: CheckCase {
    func record(_ status: RecordStatus = .passed, summary: String = "first") -> ActivityRecord { ActivityRecord(id: "T1", kind: .test, title: "检查", summary: summary, status: status, source: SourceReference(path: "report.md")) }
    func testWorkspaceRoundTripIncludesFeedback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WorkspaceStorage(url: folder.appendingPathComponent("workspace.json"))
        var action = record(); action.id = "A1"; action.action = ActionContext(kind: .toolCall, callID: "call-1")
        var state = WorkspaceState(); let project = Project(name: "test", importPath: "test", sourceRoot: folder.path, records: [record(), action])
        state.projects = [project]; state.drafts = [FeedbackDraft(projectID: project.id, recordID: "T1", text: "需要补验")]
        try store.save(state)
        let reloaded = try store.load(); checkEqual(reloaded.projects, state.projects); checkEqual(reloaded.drafts, state.drafts)
    }
    func testCorruptWorkspaceIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("workspace.json"); let bytes = Data("broken original".utf8); try bytes.write(to: url)
        let store = WorkspaceStorage(url: url)
        checkThrows(try store.load()); checkThrows(try store.save(WorkspaceState())); checkEqual(try Data(contentsOf: url), bytes)
    }
    func testNewFailurePreservesOldSuccessWithoutReplacingIt() {
        let merged = ProjectHistory.merging(old: [record()], new: [record(.failed, summary: "actual assertion failed")])
        checkEqual(merged.first?.status, .failed); checkEqual(merged.count, 2); checkEqual(merged.last?.status, .passed)
        checkNotEqual(merged.first?.id, merged.last?.id); checkFalse(merged.last!.limitations.isEmpty)
        let again = ProjectHistory.merging(old: merged, new: [record(.failed, summary: "actual assertion failed")]); checkEqual(again.count, 2)
    }
    func testDisappearedFailureRemainsVisible() {
        let merged = ProjectHistory.merging(old: [record(.failed)], new: [])
        checkEqual(merged.first?.status, .failed); checkEqual(merged.count, 1); checkFalse(merged[0].limitations.isEmpty)
    }
    func testFeedbackDoesNotClaimSentOrFixed() {
        let project = Project(name: "Example", importPath: "", sourceRoot: "", records: [])
        let text = FeedbackComposer.compose(record: record(.open), project: project)
        checkTrue(text.contains("尚未关闭")); checkTrue(text.contains("report.md")); checkFalse(text.contains("已发送")); checkFalse(text.contains("已解决"))
    }
    func testFeedbackIncludesLimitsAndRelatedEvidence() {
        var issue = record(.open)
        issue.source.excerpt = "原始复现：缺少当前风险字段"
        issue.limitations = ["只验证隔离组件，真实业务路径未验"]
        issue.relatedIDs = ["T2", "missing"]
        var check = record(.passed); check.id = "T2"; check.title = "隔离组件检查"; check.version = "a1"
        check.source = SourceReference(path: "docs/check.md", line: 8)
        var returned = record(); returned.id = "T3"; returned.title = "返回依据"; returned.relatedIDs = [issue.id]
        let project = Project(name: "Example", importPath: "", sourceRoot: "", records: [issue, check, returned])
        let text = FeedbackComposer.compose(record: issue, project: project)
        checkTrue(text.contains("原始复现：缺少当前风险字段"))
        checkTrue(text.contains("真实业务路径未验"))
        checkTrue(text.contains("T2") && text.contains("a1") && text.contains("docs/check.md:8"))
        checkTrue(text.contains("missing") && text.contains("未导入"))
        checkTrue(text.contains("T3") && text.contains("返回依据"))
        checkFalse(text.contains("已解决"))
    }
    func testEvidenceOnlyCorrectionPreservesPreviousClaim() {
        let old = record()
        var revised = old; revised.origin = .retrospective; revised.source.excerpt = "纠正原摘录"; revised.limitations = ["只检查隔离组件"]
        let merged = ProjectHistory.merging(old: [old], new: [revised])
        checkEqual(merged.count, 2); checkEqual(merged.first?.origin, .retrospective); checkEqual(merged.last?.origin, .document)
    }
}
