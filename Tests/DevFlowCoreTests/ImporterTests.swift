import Foundation
import DevFlowCore

final class ImporterTests: CheckCase {
    func testBundledTeachingSampleHasResolvableSyntheticHistory() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = repository.appendingPathComponent("Sources/DevFlowApp/Resources")
        let result = try ProjectImporter.load(url: resources.appendingPathComponent("example-history.json"))
        checkEqual(result.records.count, 6)
        checkEqual(Set(result.records.map(\.kind)), Set(RecordKind.allCases))
        checkTrue(result.warnings.isEmpty, result.warnings.joined(separator: "\n"))
        checkTrue(result.records.allSatisfy { $0.occurredAt == nil && $0.origin == .document && $0.limitations.contains { $0.contains("合成教学") } })
        checkTrue(result.records.contains { $0.status == .failed })
        checkTrue(result.records.contains { $0.status == .open })
        checkTrue(result.records.contains { $0.status == .notRun })
        for record in result.records {
            let source = try ProjectImporter.resolveSource(record.source, root: resources.path)
            let contents = try String(contentsOf: source, encoding: .utf8)
            checkEqual(ProjectImporter.digest(Data(contents.utf8)), record.source.digest)
            checkEqual(contents.components(separatedBy: "\n")[record.source.line! - 1], record.source.excerpt)
        }
        checkEqual(Set(try FileManager.default.contentsOfDirectory(atPath: resources.path)), Set(["DevFlowLogo.png", "placeholder.txt", "example-history.json", "example-notes.md"]))
    }

    func testJSONCapacityBoundaryHasActionableWarning() throws {
        let limit = 8 * 1024 * 1024
        let base = "{\"schemaVersion\":1,\"name\":\"Capacity fixture\",\"records\":[]}"
        let url = try write("capacity.json", base + String(repeating: " ", count: limit - base.utf8.count))
        let imported = try ProjectImporter.load(url: url)
        checkTrue(imported.warnings.contains { $0.contains("接近 8 MiB") })
        let original = try Data(contentsOf: url) + Data([32])
        try original.write(to: url)
        do {
            _ = try ProjectImporter.load(url: url)
            checkTrue(false, "Oversize JSON must fail")
        } catch {
            checkTrue(error.localizedDescription.contains("8388609"))
            checkTrue(error.localizedDescription.contains("不要删除失败历史"))
        }
        checkEqual(try Data(contentsOf: url), original, "Read-only import must preserve the entire input")
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("devflow-importer-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    @discardableResult private func write(_ path: String, _ content: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    private func record(_ id: String = "r1", path: String = "docs/report.md", related: [String] = [], hash: String? = nil) -> ActivityRecord {
        ActivityRecord(id: id, kind: .test, title: "历史检查", summary: "原始检查记录", status: .passed, source: SourceReference(path: path, line: 1, excerpt: "检查通过", digest: hash), relatedIDs: related)
    }
    @discardableResult private func package(_ records: [ActivityRecord], name: String = "项目") throws -> URL {
        let url = root.appendingPathComponent("import.json")
        try JSONEncoder().encode(ImportPackage(name: name, records: records)).write(to: url)
        return url
    }

    func testJSONRetainsHistoryRelationsAndDeclaredOrigin() throws {
        try write("docs/report.md", "checks")
        var first = record("attempt1"); first.status = .failed; first.occurredAt = "2026-09-21"
        var second = record("attempt2", related: ["attempt1"]); second.origin = .execution
        let result = try ProjectImporter.load(url: package([first, second]))
        checkEqual(result.records.map(\.status), [.failed, .passed])
        checkEqual(result.records[1].relatedIDs, ["attempt1"])
        checkTrue(result.records[1].limitations.contains(where: { $0.contains("未执行") }))
        checkEqual(result.sourceRoot, root.path)
    }

    func testMalformedJSONAndUnsupportedSchemaAreRejected() throws {
        checkThrows(try ProjectImporter.load(url: write("broken.json", "{\"schemaVersion\":1}")))
        var value = ImportPackage(name: "project", records: []); value.schemaVersion = 2
        let url = root.appendingPathComponent("v2.json")
        try JSONEncoder().encode(value).write(to: url)
        checkThrows(try ProjectImporter.load(url: url))
        checkThrows(try ProjectImporter.load(url: write("unknown.json", "{\"schemaVersion\":1,\"name\":\"p\",\"records\":[],\"execute\":\"command\"}")))
    }

    func testDuplicateIDsDanglingAndSelfRelationsAreRejected() throws {
        checkThrows(try ProjectImporter.load(url: package([record(), record()])))
        checkThrows(try ProjectImporter.load(url: package([record(related: ["missing"])])))
        checkThrows(try ProjectImporter.load(url: package([record(related: ["r1"])])))
    }

    func testJSONTraversalAbsoluteAndSensitiveReferencesAreRejected() throws {
        for path in ["../outside.md", "/etc/passwd", "docs/../../outside.md", "docs\\..\\outside.md", "C:/secret.md", ".env", ".git/config", "secrets/key.txt", "docs//report.md"] {
            checkThrows(try ProjectImporter.load(url: package([record(path: path)])), path)
            checkThrows(try ProjectImporter.resolveSource(SourceReference(path: path), root: root.path), path)
        }
    }

    func testResolveRejectsFileAndDirectorySymlinksIncludingInsideRoot() throws {
        let real = try write("docs/report.md", "safe")
        let link = root.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-docs"), withDestinationURL: real.deletingLastPathComponent())
        for path in ["link.md", "linked-docs/report.md"] {
            checkThrows(try ProjectImporter.resolveSource(SourceReference(path: path), root: root.path))
            checkThrows(try ProjectImporter.load(url: package([record(path: path)])))
        }
        checkEqual(try ProjectImporter.resolveSource(SourceReference(path: "docs/report.md"), root: root.path), real)
    }

    func testMissingSourcePreservesRecordWithExplicitWarning() throws {
        let result = try ProjectImporter.load(url: package([record()]))
        checkEqual(result.records.count, 1)
        checkFalse(result.warnings.isEmpty)
        checkThrows(try ProjectImporter.resolveSource(result.records[0].source, root: root.path))
    }

    func testExecutableAndWebSourceTypesCannotBeOpened() throws {
        for path in ["run.sh", "run.command", "run.py", "run.scpt", "attack.html", "payload.svg", "Tool.app"] {
            try write(path, "untrusted content")
            checkThrows(try ProjectImporter.resolveSource(SourceReference(path: path), root: root.path), path)
        }
        let safe = try write("evidence/result.json", "{}")
        checkEqual(try ProjectImporter.resolveSource(SourceReference(path: "evidence/result.json"), root: root.path), safe)
    }

    func testDateNeverComesFromFilenameDirectoryOrModificationTime() throws {
        let file = try write("docs/2026-10-28/2026-10-29.md", "一次检查\n没有记录执行时间。")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)], ofItemAtPath: file.path)
        let result = try ProjectImporter.load(url: root)
        checkFalse(result.records.isEmpty, result.warnings.joined(separator: "\n"))
        checkTrue(result.records.allSatisfy { $0.occurredAt == nil })
    }

    func testExplicitBodyDatesAreRetainedAndAmbiguityIsNotInvented() throws {
        let file = try write("report.md", "# 执行证据\n- E1：2026-09-21 测试通过。\n- E2：2026-09-22 失败，2026-09-23 通过。\n- E3：2026-02-30 无效日期。\n")
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records[0].occurredAt, "2026-09-21")
        checkNil(records[1].occurredAt)
        checkTrue(records[1].limitations.contains { $0.contains("多个日期") })
        checkNil(records[2].occurredAt)
    }

    func testChineseNotPassedAndUnknownAreNotMisclassified() throws {
        let file = try write("report.md", """
        # 测试结果
        | ID | 说明 | 状态 |
        | --- | --- | --- |
        | T1 | 全套测试 | 未通过 |
        | T2 | 完整生产路径 | NOT_RUN |
        | T3 | 回执状态 | unknown |
        | T4 | 定向回归 | PASSED |
        | T5 | 仍被依赖阻断 | BLOCKED |
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.map(\.status), [.failed, .notRun, .unknown, .passed, .blocked])
    }

    func testExpectationsAndMixedScopesDoNotBecomeBroadSuccess() throws {
        let file = try write("report.md", """
        # 验收标准
        - 未知卖出路线不得通过测试。
        # 测试结果
        - 11项通过，完整生产路径未验证。
        - 3项测试通过，0 failures。
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.map(\.status), [.recorded, .needsReview, .passed])
    }

    func testRequirementIDsStayRecordedWithoutExplicitStatusColumns() throws {
        let file = try write("PRODUCT.md", """
        # DevFlow 第一版产品契约
        ## 已确认结果
        - R03 历史：保留不同范围/版本的检查、原失败及后续修复；支持按已知记录时间筛选，未知日期单列。复盘归纳不冒当时已知事实。
        - R04 质量：局部通过不等于整体完成，未验不等于失败，暂时缓解不等于根因修复。
        ## 接口清单
        | ID | 结果 |
        | --- | --- |
        | A03 | 计划让回归测试通过，并保留检查失败记录。 |
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.count, 3)
        checkTrue(records.allSatisfy { $0.kind == .requirement })
        checkTrue(records.allSatisfy { $0.status == .recorded }, "需求描述中的失败/通过不是执行结果")
    }

    func testCommandOpenIsNotAnOpenFinding() throws {
        let file = try write("ACCEPTANCE.md", """
        # 0.1.0 本机验收记录
        ## 原生交互观察
        | 检查 | 实际结果 | 证据与限制 |
        | --- | --- | --- |
        | 打包应用启动 | 成功打开三栏原生窗口，空态可导入和载入样本 | 通过原生Computer Use启动；shell `open` 曾报-10827，不能由该错误认定应用缺失，随后真实启动和操作成功 |
        ## 缺陷
        - D01：状态：OPEN，仍需补齐后台结果。
        - D02：状态：OPEN_BACKEND_WITH_DISPLAY_MITIGATION_RELEASED，文案缓解不表示根因修复。
        | ID | 状态 |
        | --- | --- |
        | D03 | Open |
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.first { $0.title.hasPrefix("打包应用启动") }?.status, .recorded)
        for id in ["D01", "D02", "D03"] {
            checkEqual(records.first { $0.title.hasPrefix(id) }?.status, .open, "显式未关闭状态仍须保留：\(id)")
        }
    }

    func testNestedAcceptanceHeadingsRetainTestKindWithoutInheritingDates() throws {
        let file = try write("ACCEPTANCE.md", """
        # 2026-10-30 0.1.0 本机验收记录
        ## 核心检查
        `bash scripts/test.sh` 返回0，26个检查项通过、0个断言错误。
        ## 原生交互观察
        | 检查 | 实际结果 | 证据与限制 |
        | --- | --- | --- |
        | 打包应用启动 | 成功打开三栏原生窗口 | 真实启动和操作成功 |
        ## 需求与验收标准
        计划让测试通过，同时保留原失败。
        ### 补充说明
        回归通过应当保留原始记录。
        ## 技术决策
        采用本地文件。
        ### 核心检查
        定向检查通过。
        # 其他材料
        另一个独立章节。
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.count, 7)
        checkEqual(records.filter { $0.kind == .test }.count, 3)
        checkEqual(records.first { $0.title.hasPrefix("打包应用启动") }?.kind, .test)
        checkEqual(records.first { $0.title == "补充说明" }?.kind, .requirement)
        checkEqual(records.first { $0.title == "补充说明" }?.status, .recorded)
        checkEqual(records.first { $0.title == "技术决策" }?.kind, .decision)
        checkEqual(records.first { $0.title == "其他材料" }?.kind, .development)
        checkTrue(records.allSatisfy { $0.occurredAt == nil }, "父标题日期不应被借作子记录事件时间")
    }

    func testExplicitLocalAcceptanceStatusDoesNotPromotePlannedProse() throws {
        let file = try write("ROADMAP.md", """
        # 第一版有限交付与验收
        | 单元 | 验收标准 | 状态 |
        | --- | --- | --- |
        | U01 导入及来源 | 有效JSON/Markdown可导入 | 本机已验收，见ACCEPTANCE |
        | U02 项目与历史 | 搜索/类型/时间筛选 | 待验证 |
        | R03 历史 | 保留原失败 | 本机已验收，见ACCEPTANCE |
        ## 后续计划
        计划未来检查通过后，再记录为已验收。
        """)
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.first { $0.title.hasPrefix("U01") }?.status, .passed)
        checkEqual(records.first { $0.title.hasPrefix("U02") }?.status, .notRun)
        checkEqual(records.first { $0.title.hasPrefix("R03") }?.status, .passed)
        checkEqual(records.first { $0.title == "后续计划" }?.status, .recorded)
        checkTrue(records.allSatisfy { $0.origin == .document })
    }

    func testStableIDsExactSourceLineAndChangedDigest() throws {
        let file = try write("docs/history.md", "# 缺陷\n\n- D01：检查失败。\n- D02：检查通过。\n")
        let first = try ProjectImporter.load(url: root)
        let repeated = try ProjectImporter.load(url: root)
        checkEqual(first.records.map(\.id), repeated.records.map(\.id))
        checkEqual(first.records.map(\.source.line), [3, 4])
        guard first.records.count == 2 else { throw DevFlowError.invalid(first.warnings.joined(separator: "\n")) }
        checkEqual(first.records[0].status, .failed)
        try Data("# 缺陷\n\n- D01：检查失败，等待修复。\n- D02：检查通过。\n".utf8).write(to: file)
        let changed = try ProjectImporter.load(url: root)
        checkEqual(first.records[0].id, changed.records[0].id)
        checkNotEqual(first.records[0].source.digest, changed.records[0].source.digest)
        checkEqual(changed.records[0].source.digest, ProjectImporter.digest(try Data(contentsOf: file)))
    }

    func testSeparateFailureAndSuccessEntriesRemainSeparate() throws {
        let file = try write("report.md", "# 执行证据\n- E1：2026-09-21 测试失败。\n- E2：2026-09-22 测试通过。\n")
        let records = try ProjectImporter.load(url: file).records
        checkEqual(records.count, 2)
        checkEqual(records.map(\.status), [.failed, .passed])
        checkNotEqual(records[0].id, records[1].id)
    }

    func testChineseIdentifiersRemainStableWhenAnEarlierItemIsInserted() throws {
        let file = try write("history.md", "# 缺陷\n- D01：检查失败。\n- D02：检查通过。\n")
        let before = try ProjectImporter.load(url: file).records
        checkTrue(before.contains { $0.title.hasPrefix("D01：") })
        try Data("# 缺陷\n- D00：新的检查记录。\n- D01：检查失败。\n- D02：检查通过。\n".utf8).write(to: file)
        let after = try ProjectImporter.load(url: file).records
        checkEqual(before.first { $0.title.hasPrefix("D01：") }?.id, after.first { $0.title.hasPrefix("D01：") }?.id)
        checkEqual(before.first { $0.title.hasPrefix("D02：") }?.id, after.first { $0.title.hasPrefix("D02：") }?.id)
    }

    func testJSONChangedSourceWarnsWithoutReplacingHistoricalClaim() throws {
        let source = try write("docs/report.md", "old")
        let url = try package([record(hash: ProjectImporter.digest(Data("old".utf8)))])
        try Data("new".utf8).write(to: source)
        let result = try ProjectImporter.load(url: url)
        checkEqual(result.records[0].status, .passed)
        checkTrue(result.warnings.contains { $0.contains("摘要不一致") })
        checkEqual(result.records[0].source.digest, ProjectImporter.digest(Data("old".utf8)))
    }

    func testDirectorySkipsEvidenceSecretsDependenciesAndCodeFences() throws {
        try write("docs/plan.md", "# 需求\n需要本地导入。\n```sh\nrm -rf /\n```\n")
        for path in ["docs/evidence/hidden.md", "docs/.git/hidden.md", "docs/node_modules/hidden.md", "docs/secrets/hidden.md", "src/unrelated.md", ".build/hidden.md"] {
            try write(path, "# 不应读取\n私有材料")
        }
        let result = try ProjectImporter.load(url: root)
        checkEqual(result.records.count, 1)
        guard result.records.count == 1 else { throw DevFlowError.invalid(result.warnings.joined(separator: "\n")) }
        checkEqual(result.records[0].source.path, "docs/plan.md")
        checkFalse(result.records[0].summary.contains("rm -rf"))
    }

    func testOversizeDocumentAndFileCountHaveVisibleWarnings() throws {
        try write("docs/oversize.md", String(repeating: "x", count: 2 * 1_024 * 1_024 + 1))
        let oversized = try ProjectImporter.load(url: root)
        checkTrue(oversized.warnings.contains { $0.contains("上限") })
        for i in 0..<401 { try write(String(format: "docs/record-%03d.md", i), "# 需求\n一条记录") }
        let many = try ProjectImporter.load(url: root)
        checkTrue(many.warnings.contains { $0.contains("400") })
        checkTrue(many.records.count <= 400)
    }

    func testInvalidDatesLinesAndDigestsAreRejectedInJSON() throws {
        var bad = record(); bad.occurredAt = "2026-02-30"
        checkThrows(try ProjectImporter.load(url: package([bad])))
        bad = record(); bad.source.line = 0
        checkThrows(try ProjectImporter.load(url: package([bad])))
        bad = record(hash: "not-a-hash")
        checkThrows(try ProjectImporter.load(url: package([bad])))
        bad = record(); bad.occurredAt = "2026-10-29T25:01:00+08:00"
        checkThrows(try ProjectImporter.load(url: package([bad])))
    }

    func testAttachedSourceRootRevalidatesDigest() throws {
        let other = root.appendingPathComponent("actual-project")
        try FileManager.default.createDirectory(at: other.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("current".utf8).write(to: other.appendingPathComponent("docs/report.md"))
        let url = try package([record(hash: ProjectImporter.digest(Data("old".utf8)))])
        let result = try ProjectImporter.load(url: url, sourceRootOverride: other.path)
        checkEqual(result.sourceRoot, other.path)
        checkTrue(result.warnings.contains { $0.contains("摘要不一致") })
        checkFalse(result.warnings.contains { $0.contains("不存在") })
    }
    func testSHA256UsesFileBytes() {
        checkEqual(ProjectImporter.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
