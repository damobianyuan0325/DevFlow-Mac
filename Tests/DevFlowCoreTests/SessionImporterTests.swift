import Foundation
import DevFlowCore

final class SessionImporterTests: CheckCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("devflow-session-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func row(_ payload: [String: Any], outer: String = "response_item", time: String = "2026-10-30T02:23:37.204Z") -> [String: Any] {
        ["timestamp": time, "type": outer, "payload": payload]
    }
    private func message(_ id: String, role: String, text: String, turn: String? = "turn1", channel: String? = nil) -> [String: Any] {
        var payload: [String: Any] = ["type": "message", "id": id, "role": role, "content": [["type": role == "user" ? "input_text" : "output_text", "text": text]]]
        if let turn { payload["internal_chat_message_metadata_passthrough"] = ["turn_id": turn] }
        if let channel { payload["channel"] = channel }
        return row(payload)
    }
    private func call(_ id: String = "c1", turn: String? = "turn1", name: String = "exec") -> [String: Any] {
        var payload: [String: Any] = ["type": "custom_tool_call", "id": "item-" + id, "call_id": id, "name": name, "input": "await tools.exec_command({cmd: 'swift test'});", "status": "completed"]
        if let turn { payload["internal_chat_message_metadata_passthrough"] = ["turn_id": turn] }
        return row(payload)
    }
    private func output(_ value: Any, id: String = "c1") -> [String: Any] { row(["type": "custom_tool_call_output", "id": "out-" + id, "call_id": id, "output": value]) }
    private func native(_ item: [String: Any], turn: String = "turn1", time: String = "2026-10-30T02:23:37.204Z") -> [String: Any] {
        row(["type": "item_completed", "turn_id": turn, "item": item], outer: "event_msg", time: time)
    }
    private func bytes(_ rows: [[String: Any]]) throws -> Data {
        var result = Data()
        for row in rows { result.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); result.append(10) }
        return result
    }
    @discardableResult private func write(_ rows: [[String: Any]], tail: String = "") throws -> URL {
        let file = root.appendingPathComponent("session.jsonl")
        var data = try bytes(rows); data.append(Data(tail.utf8)); try data.write(to: file); return file
    }

    func testPublicMessagesAndInternalContentAreSeparated() throws {
        let file = try write([
            message("user", role: "user", text: "帮我把一句话需求拆解并记录"),
            message("progress", role: "assistant", text: "先梳理需求", channel: "commentary"),
            message("final", role: "assistant", text: "本轮报告", channel: "final"),
            row(["type": "agent_message", "id": "agent1", "author": "/root/check", "content": [["type": "text", "text": "检查报告"]]]),
            message("internal", role: "assistant", text: "INTERNAL_SENTINEL", channel: "analysis"),
            message("system", role: "system", text: "INTERNAL_SENTINEL"),
            message("developer", role: "developer", text: "INTERNAL_SENTINEL"),
            row(["type": "reasoning", "summary": "INTERNAL_SENTINEL"]),
            row(["state": "INTERNAL_SENTINEL"], outer: "world_state"),
            row(["message": "INTERNAL_SENTINEL"], outer: "compacted"),
            native(["type": "Reasoning", "id": "hidden", "raw_content": ["INTERNAL_SENTINEL"]]),
            message("environment", role: "user", text: "<environment_context>INTERNAL_SENTINEL</environment_context>")
        ])
        let imported = try CodexSessionImporter.load(url: file)
        checkEqual(imported.records.count, 4)
        checkEqual(imported.records.filter { $0.action?.kind == .request }.count, 1)
        checkTrue(imported.records.contains { $0.action?.kind == .agentReport && $0.limitations.joined().contains("不是子代理") })
        checkFalse(imported.records.map(\.summary).joined().contains("INTERNAL_SENTINEL"))
        checkTrue(imported.records.allSatisfy { $0.source.digest == nil && $0.source.line != nil && $0.occurredAt != nil })

        var hiddenOutput = output("INTERNAL_SENTINEL", id: "public-mcp")
        var hiddenPayload = hiddenOutput["payload"] as! [String: Any]
        hiddenPayload["channel"] = "analysis"; hiddenOutput["payload"] = hiddenPayload
        try write([call("public-mcp", name: "read_file"), hiddenOutput,
                   native(["type": "McpToolCall", "id": "item-public-mcp", "tool": "read_file", "arguments": [:], "result": ["isError": true, "content": [["type": "text", "text": "public failure"]]]])])
        let publicResult = try CodexSessionImporter.load(url: file)
        checkEqual(publicResult.records.filter { $0.action?.kind == .toolResult }.count, 1, "隐藏输出不能占用公开结果的位置")
        checkEqual(publicResult.records.first { $0.action?.kind == .toolResult }?.status, .failed)
        checkFalse(publicResult.records.map(\.summary).joined().contains("INTERNAL_SENTINEL"))
        checkFalse(publicResult.warnings.contains { $0.contains("尚未找到唯一关联结果") })
    }

    func testToolCallsOutputsStayStableAcrossAppendAndOutOfOrder() throws {
        let rows = [message("u1", role: "user", text: "增加导入"), output(["exit_code": 0, "output": "done"]), call()]
        let file = try write(rows)
        let before = try CodexSessionImporter.load(url: file)
        guard let callRecord = before.records.first(where: { $0.action?.kind == .toolCall }), let result = before.records.first(where: { $0.action?.kind == .toolResult }), let request = before.records.first(where: { $0.action?.kind == .request }) else { throw DevFlowError.invalid("Missing expected actions") }
        checkEqual(result.status, .recorded)
        checkTrue(result.title.contains("命令返回成功"))
        checkEqual(result.relatedIDs, [callRecord.id, request.id])
        try write(rows + [message("p2", role: "assistant", text: "继续处理", channel: "commentary")])
        let after = try CodexSessionImporter.load(url: file)
        checkEqual(after.records.first { $0.id == callRecord.id }, callRecord)
        checkEqual(Array(after.records.prefix(3)), before.records)
        checkEqual(before.sourceRoot, root.path)

        for responseID in ["native-first", "different-response-id"] {
            let firstMessage = native(["type": "UserMessage", "id": "native-first", "content": [["type": "text", "text": "按实际顺序保留需求"]]])
            try write([firstMessage, call()])
            let initial = try CodexSessionImporter.load(url: file)
            let initialRequest = initial.records.first { $0.action?.kind == .request }
            try write([firstMessage, call(), message(responseID, role: "user", text: "按实际顺序保留需求"), output(["exit_code": 0])])
            let appended = try CodexSessionImporter.load(url: file)
            checkEqual(appended.records.filter { $0.action?.kind == .request }.count, 1)
            checkEqual(appended.records.first { $0.action?.kind == .request }, initialRequest, "追加镜像不能替换此前需求的 ID 或原始行")
            checkEqual(appended.records.first { $0.action?.kind == .toolCall }, initial.records.first { $0.action?.kind == .toolCall }, "镜像出现在调用后仍应关联最早真实需求")
            checkEqual(appended.records.first { $0.action?.kind == .toolCall }?.relatedIDs, initialRequest.map { [$0.id] })
            checkEqual(appended.records.first { $0.action?.kind == .request }?.source.line, 1)
        }
    }

    func testCallsWithoutResultsDoNotClaimCompletion() throws {
        let file = try write([call()])
        let before = try CodexSessionImporter.load(url: file)
        checkEqual(before.records.count, 1)
        checkEqual(before.records[0].status, .recorded)
        checkTrue(before.warnings.contains { $0.contains("尚未找到唯一关联结果") })
        try write([call(), output(["exit_code": 1, "output": "failed"] )])
        let after = try CodexSessionImporter.load(url: file)
        checkEqual(after.records[0], before.records[0])
        checkEqual(after.records[1].status, .failed)
        checkFalse(after.warnings.contains { $0.contains("尚未找到唯一关联结果") })

        try write([native(["type": "CommandExecution", "id": "failed-command", "command": ["swift", "test"], "status": "failed", "exit_code": NSNull(), "aggregated_output": "could not start"])])
        let failedCommand = try CodexSessionImporter.load(url: file)
        checkEqual(failedCommand.records.first?.status, .failed, "明确的结构化 failed 不依赖退出码存在")
        checkEqual(failedCommand.records.first?.action?.kind, .command)
        checkFalse(failedCommand.records.first?.summary.contains("验收通过") == true)
    }

    func testDuplicateIdentityConflictsRetainBothResults() throws {
        let first = output(["exit_code": 1, "output": "first failure"])
        let file = try write([call(), first, first, output(["exit_code": 0, "output": "later success"])])
        let result = try CodexSessionImporter.load(url: file)
        checkEqual(result.records.count, 3)
        checkEqual(Set(result.records.map(\.id)).count, 3)
        checkEqual(result.records.filter { $0.action?.kind == .toolResult }.map(\.status), [.failed, .recorded])
        checkTrue(result.warnings.contains { $0.contains("重复 ID 内容冲突") })
        checkTrue(result.warnings[0].contains("duplicate_lines=1"))
    }

    func testStructuredInnerActionsAndMirrorsAreNotDoubleCounted() throws {
        let command: [String: Any] = ["type": "CommandExecution", "id": "cmd-native", "command": ["/bin/zsh", "-lc", "swift test"], "cwd": "/Users/example/DevFlow", "exit_code": 0, "aggregated_output": "31 checks"]
        let mirror: [String: Any] = ["type": "McpToolCall", "id": "item-mcp", "tool": "read_file", "arguments": ["path": "README.md"], "result": ["isError": true, "content": [["type": "text", "text": "unavailable"]]]]
        let file = try write([
            message("u1", role: "user", text: "继续检查"),
            native(["type": "UserMessage", "id": "different-user-id", "content": [["type": "text", "text": "继续检查"]]], time: "2026-10-30T02:23:37.205Z"),
            call("batch"), native(command),
            call("mcp", name: "read_file"), native(mirror), output("unavailable", id: "mcp"),
            native(["type": "FileChange", "id": "files1", "changes": ["file.swift": ["type": "add", "content": "let n = 1"]], "status": "completed"]),
            native(["type": "McpToolCall", "id": "item-mcp", "tool": "different_tool", "arguments": [:], "result": ["isError": false]]),
            native(["type": "UserMessage", "id": "later-repeat", "content": [["type": "text", "text": "继续检查"]]], time: "2026-10-30T02:25:00.000Z")
        ])
        let result = try CodexSessionImporter.load(url: file)
        checkEqual(result.records.filter { $0.action?.kind == .command }.count, 1)
        checkEqual(result.records.filter { $0.action?.kind == .fileChange }.count, 1)
        checkEqual(result.records.filter { $0.action?.kind == .request }.count, 2)
        checkEqual(result.records.filter { $0.action?.kind == .toolResult && $0.action?.callID == "mcp" }.count, 1)
        checkEqual(result.records.first { $0.action?.kind == .toolResult && $0.action?.callID == "mcp" }?.status, .failed)
        checkTrue(result.records.contains { $0.title.contains("different_tool") })
        checkTrue(result.records.first { $0.action?.kind == .toolResult && $0.action?.callID == "mcp" }?.limitations.contains { $0.contains("合并") } == true)
    }

    func testPartialUnknownAndInvalidLinesHaveCoverage() throws {
        let file = try write([message("u1", role: "user", text: "保存历史"), row(["type": "future_action", "id": "unknown"])], tail: "not json\n{\"type\":\"response_item\"")
        let result = try CodexSessionImporter.load(url: file)
        checkEqual(result.records.count, 1)
        for expected in ["read_lines=4", "supported_lines=1", "unknown_lines=1", "invalid_lines=1", "partial_lines=1"] { checkTrue(result.warnings[0].contains(expected), expected) }
        checkTrue(result.warnings.contains { $0.contains("partial") })
        checkTrue(result.warnings.contains { $0.contains("尚不支持") })
    }

    func testSensitiveFieldsBinaryAndHomePathsAreRedacted() throws {
        let secret = "SUPERSECRET_123456789"
        let cipher = "gAAAAAB" + String(repeating: "Ab9-_", count: 80) + "=="
        let rows = [
            message("u1", role: "user", text: "项目路径 /Users/alice/Project，API_KEY=\(secret)，Authorization: Bearer \(secret)"),
            call(), output(["api_key": secret, "nested": ["password": secret, "authorization": "Bearer " + secret], "analysis": "HIDDEN_REASONING", "content": [["type": "image", "data": String(repeating: "B", count: 300)], ["type": "text", "text": "用户目录 /Users/alice/Project"]]]),
            row(["type": "function_call", "id": "encrypted-call", "call_id": "encrypted", "name": "collaboration.send_message", "arguments": ["message": cipher]]),
            row(["type": "agent_message", "id": "encrypted-agent", "author": "/root/check", "content": [["type": "text", "text": "报告标题\nPayload:"], ["type": "encrypted_text", "text": cipher]]]),
            row(["type": "agent_message", "id": "encrypted-only", "author": "/root/check", "content": [["type": "encrypted_text", "encrypted_text": cipher]]]),
            output(["content": [["type": "encrypted_text", "text": cipher]]], id: "encrypted")
        ]
        let file = try write(rows)
        let result = try CodexSessionImporter.load(url: file)
        let all = result.records.map { $0.title + $0.summary + $0.source.excerpt + $0.limitations.joined() }.joined()
        checkFalse(all.contains(secret)); checkFalse(all.contains("/Users/alice")); checkFalse(all.contains("HIDDEN_REASONING"))
        checkFalse(all.contains(String(repeating: "B", count: 100)))
        checkTrue(all.contains("[已脱敏]") && all.contains("[用户]") && all.contains("二进制内容已过滤"))
        checkFalse(all.contains(cipher)); checkFalse(all.contains("gAAAAAB"))
        checkEqual(result.records.filter { $0.action?.kind == .agentReport }.count, 2, "仅有加密正文的报告仍保留事件")
        checkTrue(result.records.filter { $0.action?.kind == .agentReport }.allSatisfy { $0.summary.contains("[加密内容不可读，未还原]") && $0.limitations.joined().contains("加密") })
        checkTrue(result.warnings.contains { $0.contains("加密内容不可读") })
        checkEqual(try Data(contentsOf: file), try bytes(rows), "只读导入不得改动源日志")
    }

    func testRequestContextDoesNotCrossTurns() throws {
        let file = try write([message("u1", role: "user", text: "需求一", turn: "turn1"), call("c1", turn: "turn1"), call("c2", turn: "turn2"), call("c3", turn: nil), message("env", role: "user", text: "<environment_context>环境元数据</environment_context>", turn: "turn2"), output(["exit_code": 0], id: "c2")])
        let records = try CodexSessionImporter.load(url: file).records
        checkEqual(records.first { $0.action?.kind == .toolCall && $0.action?.callID == "c1" }?.relatedIDs.count, 1)
        checkEqual(records.first { $0.action?.kind == .toolCall && $0.action?.callID == "c2" }?.relatedIDs.count, 0)
        checkEqual(records.first { $0.action?.kind == .toolCall && $0.action?.callID == "c3" }?.relatedIDs.count, 0)
        checkEqual(records.first { $0.action?.kind == .toolResult }?.relatedIDs.count, 1)
        checkEqual(records.filter { $0.action?.kind == .request }.count, 1)
    }

    func testByteAndEventLimitsReportIncompleteCoverage() throws {
        var rows: [[String: Any]] = []
        for i in 0..<20_001 { rows.append(message("m\(i)", role: "assistant", text: "记录 \(i)", turn: nil, channel: "commentary")) }
        let file = try write(rows)
        let limited = try CodexSessionImporter.load(url: file)
        checkEqual(limited.records.count, 20_000)
        checkTrue(limited.warnings.contains { $0.contains("超过 20000") })
        try write([output(["exit_code": 0, "output": String(repeating: "bounded text line\n", count: 8_000)])])
        let longEvent = try CodexSessionImporter.load(url: file)
        checkEqual(longEvent.records.count, 1)
        checkTrue(longEvent.records[0].summary.utf8.count <= 64_000)
        checkTrue(longEvent.records[0].summary.contains("后续正文未保存"))
        checkTrue(longEvent.warnings.contains { $0.contains("64 KiB") })
        var large = try bytes([message("u1", role: "user", text: "保留此前事件")])
        large.append(Data(repeating: 65, count: 32 * 1_024 * 1_024))
        try large.write(to: file)
        let prefix = try CodexSessionImporter.load(url: file)
        checkEqual(prefix.records.count, 1)
        checkTrue(prefix.warnings.contains { $0.contains("32 MiB") })
        checkTrue(prefix.warnings[0].contains("byte_truncated=true"))
    }

    func testSymlinkAndNonRegularInputsRejected() throws {
        let file = try write([call()])
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        checkThrows(try CodexSessionImporter.load(url: link))
        checkThrows(try CodexSessionImporter.load(url: root))
        checkThrows(try CodexSessionImporter.load(url: URL(string: "https://example.com/session.jsonl")!))
    }
}
