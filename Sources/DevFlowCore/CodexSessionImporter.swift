import Foundation
import CoreFoundation

/// Imports explicitly selected Codex JSONL evidence. It never executes log content.
public enum CodexSessionImporter {
    private static let byteLimit = 200 * 1_024 * 1_024
    private static let eventLimit = 20_000
    private struct Row {
        var number: Int
        var object: [String: Any]
        var payload: [String: Any]
        var timestamp: String?
    }
    private struct Event {
        var record: ActivityRecord
        var identity: String
        var fingerprint: String
        var turnID: String?
        var callID: String?
        var isCall: Bool
        var isOutput: Bool
        var isRequest: Bool
    }
    private struct Call {
        var callID: String
        var name: String
    }
    private struct MessageIdentity {
        var format: String
        var role: String
        var id: String?
        var turn: String?
        var textHash: String
        var line: Int
        var time: Date?
    }
    private static let encryptedMarker = "[加密内容不可读，未还原]"

    public static func load(url: URL) throws -> ImportResult {
        guard url.isFileURL else { throw DevFlowError.invalid("请选择本地 Codex JSONL 会话文件。") }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, url.pathExtension.lowercased() == "jsonl" else {
            throw DevFlowError.invalid("会话来源必须是普通 JSONL 文件，不能是符号链接。")
        }
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= byteLimit, let chunk = try handle.read(upToCount: min(65_536, byteLimit + 1 - data.count)), !chunk.isEmpty { data.append(chunk) }
        let byteTruncated = data.count > byteLimit
        if byteTruncated { data = data.prefix(byteLimit) }
        var pieces = data.split(separator: 10, omittingEmptySubsequences: false)
        if pieces.last?.isEmpty == true { pieces.removeLast() }
        let endedWithNewline = data.last == 10
        var disposition: [Int: String] = [:]
        var rows: [Row] = []
        var warnings: [String] = []
        var sessionID: String?
        for (index, piece) in pieces.enumerated() {
            let line = index + 1
            if piece.allSatisfy({ $0 == 13 || $0 == 32 || $0 == 9 }) { disposition[line] = "excluded"; continue }
            do {
                guard let object = try JSONSerialization.jsonObject(with: Data(piece)) as? [String: Any], let payload = object["payload"] as? [String: Any] else {
                    disposition[line] = "unknown"; continue
                }
                if object["type"] as? String == "session_meta" { sessionID = sessionID ?? (payload["id"] as? String) ?? (payload["session_id"] as? String) }
                rows.append(Row(number: line, object: object, payload: payload, timestamp: timestamp(object["timestamp"])))
            } catch {
                disposition[line] = (index == pieces.count - 1 && !endedWithNewline) ? "partial" : "invalid"
            }
        }
        if byteTruncated { warnings.append("会话超过 200 MiB，本次仅读取文件前缀；后续动作尚未读取，不能代表完整会话。") }
        if !endedWithNewline, !pieces.isEmpty, disposition[pieces.count] != "partial" {
            warnings.append("会话尾行尚无换行符；已解析完整 JSON，后续刷新仍需核对追加内容。")
        }
        let namespace = sessionID ?? source.lastPathComponent
        var responseCalls: [String: [Call]] = [:]
        var outputIDs = Set<String>()
        var messagePhases: [String: String] = [:]
        for row in rows {
            let payload = row.payload
            if row.object["type"] as? String == "response_item" {
                let type = payload["type"] as? String ?? ""
                if ["function_call", "custom_tool_call"].contains(type), !isInternal(row.object), !isInternal(payload), let callID = payload["call_id"] as? String {
                    let call = Call(callID: callID, name: payload["name"] as? String ?? "")
                    for key in Set([callID, payload["id"] as? String].compactMap { $0 }) { responseCalls[key, default: []].append(call) }
                } else if ["function_call_output", "custom_tool_call_output"].contains(type), !isInternal(row.object), !isInternal(payload), let callID = payload["call_id"] as? String { outputIDs.insert(callID) }
            } else if payload["type"] as? String == "item_completed", let item = payload["item"] as? [String: Any], item["type"] as? String == "AgentMessage", let id = item["id"] as? String, let phase = item["phase"] as? String {
                messagePhases[id] = phase
            }
        }
        // Keep the earliest public representation, so appending a mirror never replaces its ID or source line.
        var duplicateMessageLines = Set<Int>()
        var messagesByID: [String: [MessageIdentity]] = [:]
        var recentMessages: [MessageIdentity] = []
        for row in rows {
            guard !isInternal(row.object), !isInternal(row.payload) else { continue }
            let format: String
            let message: [String: Any]
            let role: String
            if row.object["type"] as? String == "response_item", row.payload["type"] as? String == "message",
               let candidateRole = row.payload["role"] as? String, ["user", "assistant"].contains(candidateRole) {
                format = "response"; message = row.payload; role = candidateRole
                let phase = message["channel"] as? String ?? message["phase"] as? String ?? messagePhases[message["id"] as? String ?? ""]
                if ["analysis", "reasoning"].contains(phase ?? "") { continue }
            } else if row.object["type"] as? String == "event_msg", row.payload["type"] as? String == "item_completed",
                      let item = row.payload["item"] as? [String: Any], !isInternal(item),
                      let type = item["type"] as? String, ["UserMessage", "AgentMessage"].contains(type) {
                format = "native"; message = item; role = type == "UserMessage" ? "user" : "assistant"
            } else { continue }
            let text = messageText(message["content"], user: role == "user")
            guard !text.isEmpty else { continue }
            let candidate = MessageIdentity(format: format, role: role, id: message["id"] as? String,
                                            turn: turnID(row), textHash: hash(text), line: row.number, time: date(row.timestamp))
            recentMessages.removeAll { row.number - $0.line > 2 }
            let key = candidate.id.map { role + ":" + $0 + ":" + candidate.textHash }
            let sameID = key.map { messagesByID[$0] ?? [] } ?? []
            let mirror = (sameID + recentMessages).contains { other in
                guard other.format != format, other.role == role, other.textHash == candidate.textHash else { return false }
                if let earlierTurn = other.turn, let turn = candidate.turn, earlierTurn != turn { return false }
                if let id = candidate.id, other.id == id { return true }
                guard let turn = candidate.turn, other.turn == turn, let time = candidate.time, let earlierTime = other.time else { return false }
                return row.number - other.line <= 2 && abs(earlierTime.timeIntervalSince(time)) <= 0.005
            }
            if mirror { duplicateMessageLines.insert(row.number); continue }
            recentMessages.append(candidate)
            if let key { messagesByID[key, default: []].append(candidate) }
        }
        func matchingCall(_ item: [String: Any], names: [String]) -> Call? {
            guard let id = item["id"] as? String else { return nil }
            let matches = (responseCalls[id] ?? []).filter { names.map(leaf).contains(leaf($0.name)) }
            let distinct = Dictionary(grouping: matches, by: { $0.callID + ":" + $0.name })
            return distinct.count == 1 ? matches.first : nil
        }
        // Structured mirrors supplement the canonical result; they are not a second action.
        var supplements: [String: (row: Int, result: Any)] = [:]
        for row in rows where row.payload["type"] as? String == "item_completed" {
            guard !isInternal(row.object), !isInternal(row.payload), let item = row.payload["item"] as? [String: Any], !isInternal(item), item["type"] as? String == "McpToolCall",
                  let call = matchingCall(item, names: [item["tool"] as? String ?? ""]) else { continue }
            if let result = item["result"] { supplements[call.callID] = (row.number, result) }
        }

        var events: [Event] = []
        var truncatedPayloads = 0
        var encryptedPayloads = 0
        let baseLimitations = [
            "仅覆盖所选会话中已识别的公开消息及动作事件；不读取隐藏推理、系统指令或子代理未接入的执行历史。",
            "日志内容经过常见敏感字段与二进制过滤；此过滤不是完整的秘密检测保证。",
            "来源是追加式日志，digest 留空以免追加使所有旧记录失效；本记录并非密码学真实性证明。"
        ]
        func emit(_ row: Row, suffix: String, identity: String, kind: RecordKind, action: ActionKind,
                  title: String, text: String, status: RecordStatus = .recorded, callID: String? = nil,
                  isCall: Bool = false, isOutput: Bool = false, isRequest: Bool = false,
                  time: String? = nil, limitations: [String] = []) {
            let rawFingerprint = (try? JSONSerialization.data(withJSONObject: ["payload": row.payload, "suffix": suffix], options: [.sortedKeys])) ?? Data(suffix.utf8)
            let fingerprint = ProjectImporter.digest(rawFingerprint)
            let cleanTitle = redact(title)
            var cleanText = text.isEmpty ? "[没有可导入的文本；非文本内容已过滤]" : text
            var eventLimits = limitations
            if cleanText.contains(encryptedMarker) {
                eventLimits.append("事件含加密内容，未尝试解密；正文或报告尚未完整读取，不能据此确认其内部结论。")
                encryptedPayloads += 1
            }
            if cleanText.utf8.count > 64_000 {
                var prefix = Data(cleanText.utf8.prefix(63_700))
                while String(data: prefix, encoding: .utf8) == nil, !prefix.isEmpty { prefix.removeLast() }
                cleanText = (String(data: prefix, encoding: .utf8) ?? "") + "\n[本事件文本超过 64 KiB，后续正文未保存；事件本身仍保留。]"
                eventLimits.append("单事件正文已明确截断；不能把所显示文本当作完整输入或输出。")
                truncatedPayloads += 1
            }
            let record = ActivityRecord(id: "session-" + String(hash(namespace + ":" + identity).prefix(32)), kind: kind,
                                        title: String(cleanTitle.prefix(180)), summary: cleanText, status: status,
                                        occurredAt: time ?? row.timestamp, origin: [.toolCall, .toolResult, .command, .fileChange, .other].contains(action) ? .execution : .document,
                                        source: SourceReference(path: source.lastPathComponent, line: row.number, excerpt: cleanText, digest: nil),
                                        limitations: baseLimitations + eventLimits, action: ActionContext(kind: action, callID: callID))
            events.append(Event(record: record, identity: identity, fingerprint: fingerprint, turnID: turnID(row), callID: callID, isCall: isCall, isOutput: isOutput, isRequest: isRequest))
            disposition[row.number] = "supported"
        }
        for row in rows {
            let payload = row.payload
            let outer = row.object["type"] as? String ?? ""
            let type = payload["type"] as? String ?? ""
            if isInternal(row.object) || isInternal(payload) { disposition[row.number] = "excluded"; continue }
            if outer == "response_item" {
                let rawID = payload["id"] as? String ?? "line-\(row.number)"
                switch type {
                case "message":
                    if duplicateMessageLines.contains(row.number) { disposition[row.number] = "duplicate"; continue }
                    guard let role = payload["role"] as? String, ["user", "assistant"].contains(role) else { disposition[row.number] = "excluded"; continue }
                    let text = messageText(payload["content"], user: role == "user")
                    guard !text.isEmpty else { disposition[row.number] = "excluded"; continue }
                    let phase = payload["channel"] as? String ?? payload["phase"] as? String ?? messagePhases[rawID]
                    if ["analysis", "reasoning"].contains(phase ?? "") { disposition[row.number] = "excluded"; continue }
                    let final = ["final", "final_answer"].contains(phase ?? "")
                    emit(row, suffix: "message", identity: "message:" + rawID, kind: role == "user" ? .requirement : (final ? .delivery : .development), action: role == "user" ? .request : .progress,
                         title: role == "user" ? "用户需求 · " + String(text.prefix(70)) : (final ? "AI 完成报告" : "AI 公开进展"), text: text, isRequest: role == "user",
                         limitations: role == "assistant" ? ["AI 公开表述属于报告，不等于完成或验收凭据。"] : [])
                case "function_call", "custom_tool_call":
                    let callID = payload["call_id"] as? String
                    let name = payload["name"] as? String ?? "未记录工具名"
                    let input = payload["arguments"] ?? payload["input"] ?? NSNull()
                    emit(row, suffix: "call", identity: "call:" + (callID ?? rawID) + ":" + name, kind: .development, action: .toolCall,
                         title: "调用 · " + name, text: "工具：\(redact(name))\n输入（仅记录，不执行）：\n\(render(input))", callID: callID, isCall: true,
                         limitations: ["调用已记录；是否收到结果应查看关联结果。没有结果不能推断完成、失败或仍在运行。", "批量 exec 代码作为一次实际调用保留；不从代码文本推断其中哪些子工具已执行。"])
                case "function_call_output", "custom_tool_call_output":
                    let callID = payload["call_id"] as? String
                    let output = payload["output"] ?? NSNull()
                    let supplement = callID.flatMap { supplements[$0] }
                    let outcome = resultStatus(supplement?.result ?? output)
                    let mirror = supplement.map { ["同一工具的结构化结果还记于本文件第 \($0.row) 行；按工具名与 ID 核对后合并，未重复计为动作。"] } ?? []
                    emit(row, suffix: "output", identity: "output:" + (callID ?? rawID), kind: .development, action: .toolResult,
                         title: outcome.title, text: "\(outcome.detail)\n工具输出：\n\(render(output))", status: outcome.status, callID: callID, isOutput: true,
                         limitations: ["工具返回只证明日志记录了该结果，不能自动升级为需求实现或业务验收。"] + mirror)
                case "agent_message":
                    let text = messageText(payload["content"], user: false)
                    guard !text.isEmpty else { disposition[row.number] = "excluded"; continue }
                    emit(row, suffix: "agent", identity: "agent:" + rawID, kind: .development, action: .agentReport,
                         title: "子代理报告 · " + render(payload["author"] ?? "来源未标明"), text: text,
                         limitations: ["这是父会话收到的子代理报告，不是子代理的完整工具执行日志，也不证明独立复核。"])
                case "reasoning", "additional_tools", "configuration_update": disposition[row.number] = "excluded"
                default: disposition[row.number] = "unknown"
                }
            } else if outer == "event_msg", type == "item_completed", let item = payload["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""
                let itemID = item["id"] as? String ?? "line-\(row.number)"
                if isInternal(item) || ["Reasoning", "ContextCompaction"].contains(itemType) { disposition[row.number] = "excluded"; continue }
                switch itemType {
                case "UserMessage", "AgentMessage":
                    if duplicateMessageLines.contains(row.number) { disposition[row.number] = "duplicate"; continue }
                    let role = itemType == "UserMessage" ? "user" : "assistant"
                    let text = messageText(item["content"], user: role == "user")
                    guard !text.isEmpty else { disposition[row.number] = "excluded"; continue }
                    let final = item["phase"] as? String == "final_answer"
                    emit(row, suffix: "message", identity: "native-message:" + itemID, kind: role == "user" ? .requirement : (final ? .delivery : .development), action: role == "user" ? .request : .progress,
                         title: role == "user" ? "用户需求 · " + String(text.prefix(70)) : (final ? "AI 完成报告" : "AI 公开进展"), text: text, isRequest: role == "user",
                         limitations: role == "assistant" ? ["AI 公开表述属于报告，不等于完成或验收凭据。"] : [])
                case "CommandExecution":
                    let outcome = resultStatus(item)
                    let input = render(item["command"] ?? NSNull())
                    let text = "命令（仅记录，不执行）：\n\(input)\n工作目录：\(render(item["cwd"] ?? "未记录"))\n\(outcome.detail)\n输出：\n\(render(item["aggregated_output"] ?? ""))"
                    emit(row, suffix: "command", identity: "command:" + itemID, kind: .development, action: .command, title: "命令执行 · " + outcome.title, text: text, status: outcome.status, callID: itemID,
                         time: milliseconds(payload["completed_at_ms"]), limitations: ["实际结构化命令事件；不是从 exec 源码猜出的子步骤。命令退出成功不等于业务验收，父调用关联未记录时不推断。"])
                case "FileChange":
                    let failed = item["status"] as? String == "failed"
                    emit(row, suffix: "files", identity: "files:" + itemID, kind: .development, action: .fileChange, title: failed ? "文件变更 · 记录为失败" : "文件变更记录",
                         text: "变更（仅记录）：\n\(render(item["changes"] ?? NSNull()))\n工具状态：\(render(item["status"] ?? "unknown"))\n输出：\(render(item["stdout"] ?? ""))\n错误输出：\(render(item["stderr"] ?? ""))", status: failed ? .failed : .recorded, callID: itemID,
                         limitations: ["文件变更事件来自会话日志；不代表后续构建、测试或发布已通过。"])
                case "McpToolCall":
                    let name = item["tool"] as? String ?? "未记录工具名"
                    let existing = matchingCall(item, names: [name])
                    if let existing, outputIDs.contains(existing.callID) { disposition[row.number] = "duplicate"; continue }
                    let callID = existing?.callID ?? itemID
                    if existing == nil {
                        emit(row, suffix: "native-call", identity: "native-call:" + itemID + ":" + name, kind: .development, action: .toolCall, title: "调用 · " + name,
                             text: "工具：\(redact(name))\n输入（仅记录，不执行）：\n\(render(item["arguments"] ?? NSNull()))", callID: callID, isCall: true,
                             limitations: ["来自实际结构化工具事件，调用不等于完成；查看关联结果。"])
                    }
                    if let result = item["result"] {
                        let outcome = resultStatus(result)
                        emit(row, suffix: "native-output", identity: "native-output:" + itemID + ":" + name, kind: .development, action: .toolResult,
                             title: outcome.title + " · " + name, text: "\(outcome.detail)\n工具输出：\n\(render(result))", status: outcome.status, callID: callID, isOutput: true,
                             limitations: ["结构化工具结果不是业务验收；与匹配的调用按 ID 关联。"])
                    }
                case "SubAgentActivity":
                    if responseCalls[itemID] != nil { disposition[row.number] = "duplicate"; continue }
                    emit(row, suffix: "agent-activity", identity: "agent-activity:" + itemID, kind: .development, action: .other, title: "子代理协作事件",
                         text: render(["kind": item["kind"] ?? "unknown", "agent": item["agent_path"] ?? "未记录"]),
                         limitations: ["这是父会话的协作事件，不包含子代理内部执行；completed 不代表项目业务验收。"])
                case "Extension":
                    emit(row, suffix: "extension", identity: "extension:" + itemID, kind: .development, action: .other, title: "扩展工具事件",
                         text: render(["kind": item["kind"] ?? "unknown", "query": item["query"] ?? "", "action": item["action"] ?? NSNull(), "results": item["results"] ?? NSNull()]),
                         limitations: ["只展示日志中实际扩展事件，不推断尚未记录的网络操作。"])
                case "ImageView":
                    emit(row, suffix: "image", identity: "image:" + itemID, kind: .development, action: .other, title: "图片查看事件",
                         text: "日志记录查看图片：\(render(item["path"] ?? "未记录"))\n图片像素与 base64 未导入。")
                default: disposition[row.number] = "unknown"
                }
            } else if ["session_meta", "world_state", "turn_context", "token_usage_record", "inter_agent_communication_metadata", "compacted"].contains(outer) {
                disposition[row.number] = "excluded"
            } else if outer == "event_msg", ["task_started", "task_complete", "token_count", "thread_settings_applied"].contains(type) {
                disposition[row.number] = "excluded"
            } else { disposition[row.number] = "unknown" }
        }

        var unique: [Event] = []
        var fingerprints: [String: Set<String>] = [:]
        var conflictCount = 0
        for var event in events {
            if fingerprints[event.identity, default: []].contains(event.fingerprint) { continue }
            if !fingerprints[event.identity, default: []].isEmpty {
                conflictCount += 1
                event.record.id += "-" + String(event.fingerprint.prefix(12))
                event.record.limitations.append("同一事件 ID 出现不同内容，已并列保留；不得自动将其中一次覆盖为唯一真相。")
            }
            fingerprints[event.identity, default: []].insert(event.fingerprint)
            unique.append(event)
        }
        let supportedLines = Set(events.compactMap { $0.record.source.line })
        let retainedLines = Set(unique.compactMap { $0.record.source.line })
        for line in supportedLines.subtracting(retainedLines) { disposition[line] = "duplicate" }
        if conflictCount > 0 { warnings.append("重复 ID 内容冲突 \(conflictCount) 项，已保留各份记录，并阻止有歧义的调用关联。") }
        if truncatedPayloads > 0 { warnings.append("\(truncatedPayloads) 个事件文本超过 64 KiB，已保留事件与明确截断标记，未完整保存其正文。") }
        if encryptedPayloads > 0 { warnings.append("\(encryptedPayloads) 个已识别事件含加密内容不可读，已保留事件与占位提示；未解密、未还原，不能视为已读完报告或工具输入。") }
        if unique.count > eventLimit {
            warnings.append("已识别 \(unique.count) 个事件，超过 20000 个事件上限；本次只保留前 20000 个，后续已识别事件未导入。")
            unique = Array(unique.prefix(eventLimit))
        }
        var requests: [String: String] = [:]
        var calls: [String: [Int]] = [:]
        for index in unique.indices {
            if unique[index].isRequest, let turn = unique[index].turnID { requests[turn] = unique[index].record.id }
            else if !unique[index].isOutput, let turn = unique[index].turnID, let request = requests[turn] {
                unique[index].record.relatedIDs = [request]
                unique[index].record.limitations.append("关联用户消息仅表示同一轮对话上下文，不表示该需求已实现或验收。")
            }
            if unique[index].isCall, let callID = unique[index].callID { calls[callID, default: []].append(index) }
        }
        var linkedCalls = Set<String>()
        var orphanOutputs = 0
        for index in unique.indices where unique[index].isOutput {
            guard let callID = unique[index].callID, let matches = calls[callID], matches.count == 1 else {
                orphanOutputs += 1
                unique[index].record.limitations.append("对应调用缺失或 call_id 不唯一，未自动补造调用或关联。")
                continue
            }
            let call = unique[matches[0]].record
            unique[index].record.relatedIDs = [call.id] + call.relatedIDs
            unique[index].record.limitations.append("与需求的关联仅表示调用所在轮次的上下文，不证明需求完成。")
            linkedCalls.insert(call.id)
        }
        let missing = unique.filter { $0.isCall && !linkedCalls.contains($0.record.id) }.count
        if missing > 0 { warnings.append("\(missing) 个调用尚未找到唯一关联结果；状态未知，不能推断仍在执行或已完成。") }
        if orphanOutputs > 0 { warnings.append("\(orphanOutputs) 个结果缺少唯一调用；保留结果原件，不补造执行链。") }
        let counts = Dictionary(grouping: disposition.values, by: { $0 }).mapValues(\.count)
        if counts["partial", default: 0] > 0 { warnings.append("尾部存在尚未写完的 partial JSON 行；已保留此前完整事件，待刷新补读。") }
        if counts["invalid", default: 0] > 0 { warnings.append("\(counts["invalid", default: 0]) 行 JSON 无法解析，未将其当作已执行动作。") }
        if counts["unknown", default: 0] > 0 { warnings.append("\(counts["unknown", default: 0]) 行属于尚不支持的事件形状；当前视图不是所有动作的完整证明。") }
        warnings.insert("coverage: read_lines=\(pieces.count); supported_lines=\(counts["supported", default: 0]); excluded_lines=\(counts["excluded", default: 0]); duplicate_lines=\(counts["duplicate", default: 0]); unknown_lines=\(counts["unknown", default: 0]); invalid_lines=\(counts["invalid", default: 0]); partial_lines=\(counts["partial", default: 0]); imported_events=\(unique.count); bytes_read=\(data.count); byte_truncated=\(byteTruncated)", at: 0)
        warnings.append("内部推理、system/developer、world_state、compacted、运行元数据和二进制内容均未导入；父会话代理报告不冒充子代理执行流。")
        return ImportResult(name: "Codex 会话 · " + source.deletingPathExtension().lastPathComponent, records: unique.map(\.record), warnings: warnings, sourceRoot: source.deletingLastPathComponent().path)
    }

    private static func turnID(_ row: Row) -> String? {
        (row.payload["internal_chat_message_metadata_passthrough"] as? [String: Any])?["turn_id"] as? String ?? row.payload["turn_id"] as? String ?? (row.object["metadata"] as? [String: Any])?["turn_id"] as? String
    }
    private static func leaf(_ name: String) -> String { name.components(separatedBy: "__").last?.components(separatedBy: ".").last ?? name }
    private static func hash(_ text: String) -> String { ProjectImporter.digest(Data(text.utf8)) }
    private static func isInternal(_ object: [String: Any]) -> Bool {
        let forbidden = ["analysis", "reasoning", "system", "developer", "world_state", "compacted"]
        for key in ["type", "role", "channel", "phase"] {
            if let value = object[key] as? String, forbidden.contains(value.lowercased()) { return true }
        }
        if let metadata = object["metadata"] as? [String: Any], let channel = metadata["channel"] as? String, forbidden.contains(channel.lowercased()) { return true }
        return false
    }
    private static func messageText(_ content: Any?, user: Bool) -> String {
        let blocks = content as? [[String: Any]] ?? []
        var texts = blocks.compactMap { block -> String? in
            if block["type"] as? String == "encrypted_text" || block["encrypted_text"] != nil || block["encrypted_content"] != nil { return encryptedMarker }
            guard ["input_text", "output_text", "text"].contains(block["type"] as? String ?? ""), let text = block["text"] as? String else { return nil }
            return text
        }
        if let plain = content as? String { texts = [plain] }
        var text = texts.joined(separator: "\n")
        if user {
            for tag in ["environment_context", "external_codex_apps_open_page", "permissions", "permissions_instructions", "collaboration_mode", "codex_apps_open_page_instructions"] {
                text = text.replacingOccurrences(of: "(?s)<" + tag + "\\b[^>]*>.*?</" + tag + ">", with: "", options: .regularExpression)
            }
        }
        return redact(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func timestamp(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: string) != nil { return string }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string) != nil ? string : nil
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    private static func milliseconds(_ value: Any?) -> String? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: number.doubleValue / 1000))
    }
    private static func resultStatus(_ value: Any) -> (status: RecordStatus, title: String, detail: String) {
        var object = value as? [String: Any]
        if let string = value as? String, let data = string.data(using: .utf8) { object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        if let code = object?["exit_code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID() {
            return code.intValue == 0 ? (.recorded, "命令返回成功", "结构化退出码：0；只表示命令返回成功，不等于业务验收。") : (.failed, "命令返回失败", "结构化退出码：\(code.intValue)；仅为命令层失败，不自动归因为产品缺陷。")
        }
        if object?["isError"] as? Bool == true { return (.failed, "工具返回错误", "结构化 isError=true；这不自动说明业务缺陷根因。") }
        if (object?["status"] as? String)?.lowercased() == "failed" { return (.failed, "执行记录为失败", "结构化状态：failed；仅为该动作层失败，退出码未记录，不自动归因为产品缺陷。") }
        return (.recorded, "工具结果已记录", "已收到工具结果；没有可判定退出码，不能自动标为检查通过。")
    }
    private static func render(_ value: Any) -> String {
        let cleaned = sanitize(value, depth: 0)
        if let string = cleaned as? String { return string }
        guard JSONSerialization.isValidJSONObject(cleaned), let data = try? JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) else { return "[未支持的非文本内容]" }
        return string
    }
    private static func sanitize(_ value: Any, depth: Int) -> Any {
        guard depth < 20 else { return "[嵌套内容过深，未导入]" }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")), let bytes = string.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: bytes) {
                return sanitize(parsed, depth: depth + 1)
            }
            return redact(string)
        }
        if let array = value as? [Any] { return array.map { sanitize($0, depth: depth + 1) } }
        if let object = value as? [String: Any] {
            if (object["type"] as? String)?.lowercased() == "encrypted_text" { return encryptedMarker }
            if let type = object["type"] as? String, ["image", "input_image", "image_url", "audio", "input_audio", "video"].contains(type.lowercased()) { return "[二进制内容已过滤]" }
            if isInternal(object) { return "[内部内容未导入]" }
            var result: [String: Any] = [:]
            for (key, item) in object {
                let lower = key.lowercased()
                if ["reasoning", "analysis", "world_state", "system", "developer", "compacted", "internal_chat_message_metadata_passthrough"].contains(lower) { continue }
                if ["encrypted_text", "encrypted_content"].contains(lower) { result[redact(key)] = encryptedMarker; continue }
                if key.range(of: "(?i)api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|password|passwd|secret|private[_-]?key|cookie|^token$", options: .regularExpression) != nil {
                    result[redact(key)] = "[已脱敏]"
                } else { result[redact(key)] = sanitize(item, depth: depth + 1) }
            }
            return result
        }
        return value
    }
    private static func redact(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("(?<![A-Za-z0-9_-])gAAAAA[A-Za-z0-9_-]{58,}={0,2}(?![A-Za-z0-9_-])", encryptedMarker),
            ("(?s)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", "[私钥已脱敏]"),
            ("(?is)<(?:analysis|reasoning|system|developer|world_state|compacted)\\b[^>]*>.*?</(?:analysis|reasoning|system|developer|world_state|compacted)>", "[内部内容未导入]"),
            ("(?i)data:(?:image|audio|video)/[^\\s\"']+", "[二进制内容已过滤]"),
            ("(?i)\\b(?:Bearer|Basic)\\s+[A-Za-z0-9._~+/=-]+", "[授权信息已脱敏]"),
            ("(?i)([\"']?(?:[A-Za-z][A-Za-z0-9_]*(?:_TOKEN|_KEY|_SECRET|_PASSWORD)|api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|password|passwd|secret|private[_-]?key|cookie|token)[\"']?\\s*[:=]\\s*)(?:\"[^\"]*\"|'[^']*'|[^\\s,;}&]+)", "$1[已脱敏]"),
            ("\\b(?:sk-[A-Za-z0-9_-]{12,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\\b", "[密钥已脱敏]"),
            ("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b", "[令牌已脱敏]"),
            ("(?i)(https?://)[^/\\s:@]+:[^/\\s@]+@", "$1[凭据已脱敏]@"),
            ("/Users/[^/\\s\"'<>\\\\]+", "/Users/[用户]"),
            ("/home/[^/\\s\"'<>\\\\]+", "/home/[用户]"),
            ("(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{256,}={0,2}(?![A-Za-z0-9+/])", "[长二进制串已过滤]")
        ]
        for (pattern, replacement) in replacements { result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression) }
        return result
    }
}
