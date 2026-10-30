import Foundation
import DevFlowCore

final class SupervisionTests: CheckCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("devflow-supervision-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    @discardableResult private func file(_ path: String, _ text: String) throws -> String {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data(text.utf8); try bytes.write(to: url); return ProjectImporter.digest(bytes)
    }
    private func plan() throws -> SupervisionPlan {
        let source = try file("Sources/Feature.swift", "func feature() -> Bool { true }\n")
        let log = try file("evidence/check.log", "1 case: PASS; failed=0; skipped=0\n")
        var result = SupervisionPlan(title: "真实链路", version: "0.2.0", originalRequest: "我希望看清研发是否有证据", requirements: [
            SupervisionRequirement(id: "R1", title: "展示真实状态", originalText: "看清研发是否有证据", details: "拆解为一个组件可验收标准")
        ], criteria: [
            AcceptanceCriterion(id: "A1", requirementID: "R1", title: "状态由证据支持", expected: "有效证据链满足标准", requiredLevel: .unit, sourcePaths: ["Sources/Feature.swift"])
        ], tasks: [DevelopmentTask(id: "U1", title: "实现证据核验", criterionIDs: ["A1"], status: .completed)], testCases: [
            SupervisionTestCase(id: "T1", title: "有效链路", criterionIDs: ["A1"], taskIDs: ["U1"], input: "真实源码与日志", expected: "标准满足", level: .unit)
        ], executions: [
            VerificationExecution(id: "E1", testCaseID: "T1", occurredAt: "2026-10-30T03:00:00Z", command: "swift run DevFlowChecks", environment: "macOS local fixture", result: .passed, level: .unit,
                                  counts: ExecutionCounts(total: 1, passed: 1, failed: 0, skipped: 0), sourceFiles: [SourceFileIdentity(path: "Sources/Feature.swift", sha256: source)], log: SourceReference(path: "evidence/check.log", digest: log))
        ])
        result.executions[0].contractDigest = try SupervisionEvaluator.contractDigest(plan: result, testCaseID: "T1")
        return result
    }
    private func assess(_ plan: SupervisionPlan, records: [ActivityRecord] = []) -> SupervisionAssessment {
        SupervisionEvaluator.evaluate(plan: plan, root: root.path, records: records)
    }
    func testCompleteEvidenceChainIsSatisfied() throws {
        var input = try plan()
        let artifact = try file("dist/DevFlow.zip", "fixture artifact")
        input.artifacts = [DeliveryArtifact(id: "D1", title: "本地包", path: "dist/DevFlow.zip", sha256: artifact, executionIDs: ["E1"])]
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(SupervisionPlan.self, from: encoded)
        try decoded.validate()
        let result = assess(decoded)
        checkEqual(decoded, input)
        checkEqual(result.requirements.first?.state, .satisfied)
        checkEqual(result.criteria.first?.state, .satisfied)
        checkEqual(result.executions.first?.isValidPass, true)
        checkEqual(result.artifacts.first?.state, .satisfied)
        checkTrue(result.validationErrors.isEmpty)
        checkFalse(result.briefing.isEmpty)
        checkEqual(try String(contentsOf: root.appendingPathComponent("evidence/check.log"), encoding: .utf8), "1 case: PASS; failed=0; skipped=0\n")
        var appended = input; appended.tasks[0].status = .inProgress; appended.requirements[0].recordIDs = ["new-action"]
        var extra = input.executions[0]; extra.id = "E2"; extra.result = .unknown; appended.executions.append(extra)
        checkEqual(try SupervisionEvaluator.contractDigest(plan: appended, testCaseID: "T1"), input.executions[0].contractDigest, "追加执行和动作、改变任务状态不能使验收合同自我失效")
    }
    func testLowerLayerCannotSatisfyNativeCriterion() throws {
        var input = try plan(); input.criteria[0].requiredLevel = .native
        input.executions[0].contractDigest = try SupervisionEvaluator.contractDigest(plan: input, testCaseID: "T1") // The native criterion existed before this lower-layer execution.
        let result = assess(input)
        checkEqual(result.criteria.first?.state, .partial)
        checkFalse(result.requirements.first?.state == .satisfied)
        checkTrue(result.criteria.first?.reasons.joined().contains("原生") == true)
    }
    func testChangedSourceMakesOldPassStale() throws {
        let input = try plan(); try file("Sources/Feature.swift", "func feature() -> Bool { false }\n")
        let result = assess(input)
        checkEqual(result.executions.first?.state, .stale)
        checkEqual(result.criteria.first?.state, .stale)
        checkEqual(result.requirements.first?.state, .stale)
        checkFalse(result.executions.first?.isValidPass == true)
        var changedExpectation = try plan(); changedExpectation.criteria[0].expected = "增加原生窗口要求"
        checkEqual(assess(changedExpectation).criteria.first?.state, .stale, "同 ID 预期改变后旧通过不能沿用")
    }
    func testMissingOrChangedLogDoesNotPass() throws {
        let input = try plan()
        try FileManager.default.removeItem(at: root.appendingPathComponent("evidence/check.log"))
        checkEqual(assess(input).criteria.first?.state, .unverified)
        try file("evidence/check.log", "different log\n")
        checkFalse(assess(input).executions.first?.isValidPass == true)
        checkTrue(assess(input).executions.first?.reasons.joined().contains("日志") == true)
        var missingHash = input; missingHash.executions[0].log?.digest = nil
        checkEqual(assess(missingHash).criteria.first?.state, .unverified)
    }
    func testLatestFailureWinsAndHistoryRemains() throws {
        var input = try plan(); var later = input.executions[0]
        later.id = "E2"; later.occurredAt = "2026-10-30T03:10:00Z"; later.result = .failed
        later.counts = ExecutionCounts(total: 1, passed: 0, failed: 1, skipped: 0)
        later.log = SourceReference(path: "evidence/fail.log", digest: try file("evidence/fail.log", "1 FAIL\n"))
        input.executions = [later, input.executions[0]] // Array order must not impersonate execution time.
        let snapshot = input
        let result = assess(input)
        checkEqual(result.criteria.first?.state, .failed)
        checkEqual(result.requirements.first?.state, .failed)
        checkEqual(result.executions.count, 2)
        checkEqual(input, snapshot)
        checkTrue(result.criteria.first?.evidenceIDs.contains("E2") == true)
        input.executions[0].occurredAt = nil
        checkFalse(assess(input).criteria.first?.state == .satisfied, "没有真实时间也不能回退旧成功")
    }
    func testDeclaredClosureRequiresFixAndValidRetest() throws {
        var input = try plan()
        input.issues = [SupervisionIssue(id: "B1", title: "遗漏边界", criterionIDs: ["A1"], testCaseIDs: ["T1"], declaredClosed: true, rootCause: "错误分支", missedCheckCause: "缺少反例", fixRecordIDs: ["fix1"], verificationExecutionIDs: ["E1"])]
        checkFalse(assess(input).issues.first?.state == .closed)
        let fix = ActivityRecord(id: "fix1", kind: .development, title: "修复分支", summary: "修改已记录", occurredAt: "2026-10-30T02:59:00Z", origin: .execution, source: SourceReference(path: "Sources/Feature.swift"), action: ActionContext(kind: .fileChange))
        checkEqual(assess(input, records: [fix]).issues.first?.state, .closed)
        var failedFix = fix; failedFix.status = .failed
        checkFalse(assess(input, records: [failedFix]).issues.first?.state == .closed, "失败的修复动作不能充当完成修复")
        var tooLate = fix; tooLate.occurredAt = "2026-10-30T03:01:00Z"
        checkFalse(assess(input, records: [tooLate]).issues.first?.state == .closed, "修复之前的通过不是复验")
        var simultaneous = fix; simultaneous.occurredAt = input.executions[0].occurredAt
        checkFalse(assess(input, records: [simultaneous]).issues.first?.state == .closed, "同一时间不能证明复验晚于修复")
        var failure = input.executions[0]; failure.id = "E2"; failure.result = .failed; failure.occurredAt = "2026-10-30T03:02:00Z"
        input.executions.append(failure)
        checkFalse(assess(input, records: [fix]).issues.first?.state == .closed, "指定旧复验不能遮住新失败")
    }
    func testInvalidGraphAndDuplicateIDsRejected() throws {
        var input = try plan(); input.criteria[0].requirementID = "missing"
        checkThrows(try input.validate())
        checkFalse(assess(input).validationErrors.isEmpty)
        input = try plan(); input.testCases[0].id = "R1"
        checkThrows(try input.validate(), "所有类型的ID全局唯一")
        input = try plan(); input.issues = [SupervisionIssue(id: "B1", title: "不存在的复验", criterionIDs: ["A1"], verificationExecutionIDs: ["missing"])]
        checkThrows(try input.validate())
        input = try plan(); input.testCases[0].taskIDs = ["missing"]
        checkThrows(try input.validate())
    }
    func testUnsafeAndSymlinkPathsRejected() throws {
        for path in ["../outside.log", "/etc/passwd", "evidence/../../outside.log", ".env", "nested/.aws/credentials", "secrets.json", "C:\\secret.txt"] {
            var input = try plan(); input.executions[0].log?.path = path
            checkThrows(try input.validate(), path)
        }
        var input = try plan()
        let link = root.appendingPathComponent("evidence/link.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("evidence/check.log"))
        input.executions[0].log?.path = "evidence/link.log"
        checkFalse(assess(input).executions.first?.isValidPass == true)
        checkTrue(assess(input).executions.first?.reasons.joined().contains("符号链接") == true)
        input = try plan(); input.executions[0].log?.path = "evidence"
        checkFalse(assess(input).executions.first?.isValidPass == true, "目录不能冒充日志")
        input = try plan()
        let large = Data(repeating: 65, count: 4 * 1_024 * 1_024 + 1)
        try large.write(to: root.appendingPathComponent("evidence/large.log"))
        input.executions[0].log = SourceReference(path: "evidence/large.log", digest: ProjectImporter.digest(large))
        checkFalse(assess(input).executions.first?.isValidPass == true)
        checkTrue(assess(input).executions.first?.reasons.joined().contains("4 MiB") == true)
    }
    func testUnknownCountsAreNotZero() throws {
        var input = try plan(); input.executions[0].counts = ExecutionCounts(total: 1, passed: 1)
        checkEqual(assess(input).criteria.first?.state, .unverified)
        input.executions[0].counts = nil
        checkFalse(assess(input).executions.first?.isValidPass == true)
        input.executions[0].counts = ExecutionCounts(total: 0, passed: 0, failed: 0, skipped: 0)
        checkFalse(assess(input).executions.first?.isValidPass == true)
        input.executions[0].counts = ExecutionCounts(total: 2, passed: 1, failed: 0, skipped: 1)
        checkFalse(assess(input).executions.first?.isValidPass == true)
        input.executions[0].counts = ExecutionCounts(total: 1, passed: 1, failed: 0, skipped: 0); input.executions[0].result = .unknown
        checkEqual(assess(input).criteria.first?.state, .unverified)
        input = try plan(); input.executions[0].exitCode = 7
        checkEqual(assess(input).criteria.first?.state, .failed, "非零退出码不能被passed声明盖住")
        input = try plan(); input.executions[0].counts?.failed = -1
        checkThrows(try input.validate())
        input = try plan(); input.executions[0].contractDigest = nil
        checkEqual(assess(input).criteria.first?.state, .unverified, "缺失验收合同绑定不能推断仍适用")
    }
    func testMissingRecordsAndBlockedTasksRemainVisible() throws {
        var input = try plan(); input.executions[0].recordIDs = ["unconnected-action"]
        let missing = assess(input)
        checkFalse(missing.executions.first?.isValidPass == true)
        checkTrue(missing.interventions.contains { $0.reason.contains("未接入") })
        input = try plan(); input.tasks[0].status = .blocked
        checkEqual(assess(input).criteria.first?.state, .blocked)
        input.tasks[0].status = .completed; input.executions = []
        checkEqual(assess(input).criteria.first?.state, .unverified, "完成声明不能代替检查执行")
    }
}
