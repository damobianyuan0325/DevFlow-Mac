import Foundation
import DevFlowCore

final class ProjectSourcesTests: CheckCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func base() throws -> Project {
        let url = root.appendingPathComponent("requirements.md"); try "# 需求\n- R1 保留真实过程。\n".write(to: url, atomically: true, encoding: .utf8)
        let result = try ProjectImporter.load(url: url)
        return Project(name: result.name, importPath: url.path, sourceRoot: result.sourceRoot, records: result.records)
    }
    func session(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name + ".jsonl")
        let rows: [[String: Any]] = [
            ["type":"session_meta", "payload":["id":name]],
            ["timestamp":"2026-10-30T03:00:00Z", "type":"response_item", "payload":["type":"message", "id":"request", "role":"user", "content":[["type":"input_text","text":"检查 " + name]]]]
        ]
        try rows.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func append(_ url: URL) throws {
        let row: [String:Any] = ["timestamp":"2026-10-30T03:00:01Z", "type":"response_item", "payload":["type":"function_call", "id":"call", "call_id":"call", "name":"observe", "arguments":"{}"]]
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: JSONSerialization.data(withJSONObject: row)); try handle.write(contentsOf: Data([10]))
    }
    func testTwoExplicitSourcesDeduplicateAndPersist() throws {
        let original = try base(); let first = try session("one"), second = try session("two")
        let bytes = try Data(contentsOf: first)
        var project = try ProjectSources.attaching(url: first, to: original)
        project = try ProjectSources.attaching(url: second, to: project)
        let count = project.records.count
        project = try ProjectSources.attaching(url: first, to: project)
        checkEqual(project.sessionSources?.count, 2); checkEqual(project.records.count, count)
        checkEqual(try Data(contentsOf: first), bytes)
        var state = WorkspaceState(); state.projects = [project]; state.selectedProjectID = project.id
        let storage = WorkspaceStorage(url: root.appendingPathComponent("workspace.json")); try storage.save(state)
        let restored = try storage.load(); checkEqual(restored.projects, state.projects); checkEqual(restored.selectedProjectID, project.id)
    }
    func testDisabledSourceKeepsHistoryAndResumeReadsNewData() throws {
        let file = try session("pause"); var project = try ProjectSources.attaching(url: file, to: base())
        let captured = project
        var current = project; current.refreshPaused = true; current.sessionSources![0].isEnabled = false
        var imported = captured; imported.name = "读取后的项目名"
        let controls = ProjectSources.preservingControls(from: current, in: imported)
        checkEqual(controls.refreshPaused, true, "异步读取期间用户暂停不能被旧快照撤销")
        checkEqual(controls.sessionSources?.first?.isEnabled, false, "保留最新会话读取开关")
        checkEqual(controls.name, "读取后的项目名", "控制合并不能丢弃新读取结果")
        let oldIDs = project.records.map(\.id); project.sessionSources![0].isEnabled = false
        try append(file)
        let paused = ProjectSources.refresh(project).project
        checkEqual(paused.records.map(\.id), oldIDs); checkTrue(paused.warnings.contains { $0.contains("已暂停") })
        project = paused; project.sessionSources![0].isEnabled = true
        let resumed = ProjectSources.refresh(project).project
        checkEqual(resumed.records.count, oldIDs.count + 1); checkTrue(Set(oldIDs).isSubset(of: Set(resumed.records.map(\.id))))
    }
    func testUnavailableSourceRetainsEvidenceAndPrimaryStillRefreshes() throws {
        let file = try session("missing"); let project = try ProjectSources.attaching(url: file, to: base())
        try FileManager.default.moveItem(at: file, to: file.appendingPathExtension("held"))
        try "# 需求\n- R1 保留真实过程。\n- R2 新增主资料。\n".write(to: URL(fileURLWithPath: project.importPath), atomically: true, encoding: .utf8)
        let result = ProjectSources.refresh(project)
        checkNil(result.primaryError); checkTrue(result.project.sessionSources![0].error != nil)
        checkEqual(result.project.sessionSources![0].records, project.sessionSources![0].records)
        checkTrue(result.project.records.contains { $0.title.contains("R2") })
        var failed = result.project
        failed.sessionSources![0].warnings.append("OLD_COVERAGE_SENTINEL")
        try FileManager.default.moveItem(at: file.appendingPathExtension("held"), to: file)
        try append(file)
        let recovered = ProjectSources.refresh(failed).project
        checkNil(recovered.sessionSources![0].error)
        checkFalse(recovered.warnings.contains { $0.contains("读取失败") }, "来源恢复后项目警告不能保留上轮失败")
        checkFalse(recovered.warnings.contains { $0.contains("OLD_COVERAGE_SENTINEL") }, "只组合当前实际来源覆盖信息")
        checkTrue(recovered.warnings.contains { $0.contains("read_lines=3") })
        checkTrue(Set(project.records.map(\.id)).isSubset(of: Set(recovered.records.map(\.id))), "恢复读取不能丢失此前历史")
        let primary = URL(fileURLWithPath: recovered.importPath)
        try FileManager.default.moveItem(at: primary, to: primary.appendingPathExtension("held"))
        let primaryFailure = ProjectSources.refresh(recovered)
        checkTrue(primaryFailure.primaryError != nil)
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(primaryFailure.project))
        checkEqual(restored.primarySourceError, primaryFailure.primaryError, "主来源失败跨项目选择和重启仍有项目级依据")
        try FileManager.default.moveItem(at: primary.appendingPathExtension("held"), to: primary)
        checkNil(ProjectSources.refresh(restored).project.primarySourceError)
    }
    func testPlanRevisionsArePreservedWithoutDuplicateSnapshots() throws {
        var project = try base()
        let a = SupervisionPlan(title: "计划", version: "1", originalRequest: "查看证据")
        var b = a; b.version = "2"; b.assumptions = ["后续真实范围修改"]
        project.supervision = a
        let result = ImportResult(name: project.name, records: project.records, warnings: [], sourceRoot: root.path, supervision: b)
        project = ProjectSources.applying(result, to: project); project = ProjectSources.applying(result, to: project)
        checkEqual(project.supervision, b); checkEqual(project.supervisionHistory, [a])
    }
    func testSchemaTwoRoundTripAndLegacyWorkspaceRemainReadable() throws {
        let project = try base(); let plan = SupervisionPlan(title: "监督", version: "1", originalRequest: "查看拆解", requirements: [SupervisionRequirement(id: "R1", title: "需求", originalText: "查看拆解")])
        let url = root.appendingPathComponent("supervision.json")
        try JSONEncoder().encode(ImportPackage(name: "监督", records: project.records, supervision: plan)).write(to: url)
        let imported = try ProjectImporter.load(url: url); checkEqual(imported.supervision, plan)
        var state = WorkspaceState(); state.projects = [project]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String:Any]
        var projects = object["projects"] as! [[String:Any]]
        for key in ["primaryRecords", "sessionSources", "refreshPaused", "supervision", "supervisionHistory"] { projects[0].removeValue(forKey: key) }
        object["projects"] = projects; object.removeValue(forKey: "selectedProjectID")
        let legacy = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        checkEqual(legacy.projects[0].records, project.records); checkNil(legacy.projects[0].supervision)
    }
    func testFeedbackCarriesRequirementAndDoesNotClaimDelivery() throws {
        let plan = SupervisionPlan(title: "监督", version: "1", originalRequest: "看见过程", requirements: [SupervisionRequirement(id: "R1", title: "具体需求", originalText: "用户一句话", details: "代理实际拆解", recordIDs: ["missing-record"])])
        let text = SupervisionFeedback.compose(targetID: "R1", plan: plan, assessment: nil, records: [])
        checkTrue(text.contains("用户一句话") && text.contains("代理实际拆解"))
        checkTrue(text.contains("关联记录尚未接入")); checkTrue(text.contains("不表示送达"))
    }
}
