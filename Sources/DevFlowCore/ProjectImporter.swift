import Foundation
import CryptoKit

public struct ImportResult {
    public var name: String
    public var records: [ActivityRecord]
    public var warnings: [String]
    public var sourceRoot: String
    public var supervision: SupervisionPlan?
    public init(name: String, records: [ActivityRecord], warnings: [String], sourceRoot: String, supervision: SupervisionPlan? = nil) {
        self.name = name; self.records = records; self.warnings = warnings; self.sourceRoot = sourceRoot; self.supervision = supervision
    }
}

/// Reads selected local material. Imported commands are always inert text.
public enum ProjectImporter {
    private static let maximumRecords = 5_000
    private static let maximumFiles = 400
    private static let maximumMarkdownBytes = 2 * 1_024 * 1_024
    private static let maximumJSONBytes = 8 * 1_024 * 1_024
    private static let maximumTotalBytes = 24 * 1_024 * 1_024
    private static let inspectableExtensions: Set<String> = ["md", "markdown", "txt", "json", "log", "csv", "tsv", "png", "jpg", "jpeg", "pdf"]
    private static let excludedDirectories: Set<String> = [
        ".git", ".build", ".env", "node_modules", "evidence", "evidences", "venv", ".venv",
        "__pycache__", "build", "dist", "vendor", "secrets", "credentials", "private", "logs",
        "backups", "backup", "fixtures", "data", "runtime", "archive", "archives"
    ]

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func load(url: URL, sourceRootOverride: String? = nil) throws -> ImportResult {
        guard url.isFileURL else { throw DevFlowError.invalid("只能导入本地文件或项目目录。") }
        let selected = url.standardizedFileURL
        let info = try selected.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard info.isSymbolicLink != true else { throw DevFlowError.invalid("请直接选择真实文件或目录，不导入符号链接。") }
        let canonical = selected.resolvingSymlinksInPath()
        if info.isDirectory == true { return try loadDirectory(canonical) }
        guard info.isRegularFile == true else { throw DevFlowError.invalid("所选来源不是普通文件。") }
        switch canonical.pathExtension.lowercased() {
        case "jsonl": return try CodexSessionImporter.load(url: canonical)
        case "json": return try loadJSON(canonical, sourceRootOverride: sourceRootOverride)
        case "md", "markdown":
            let bytes = try read(canonical, limit: maximumMarkdownBytes)
            guard let content = String(data: bytes, encoding: .utf8) else { throw DevFlowError.invalid("Markdown 文件不是有效的 UTF-8 文本。") }
            var warnings: [String] = []
            let records = extract(content, path: canonical.lastPathComponent, hash: digest(bytes), warnings: &warnings)
            return ImportResult(name: canonical.deletingPathExtension().lastPathComponent, records: records, warnings: warnings, sourceRoot: canonical.deletingLastPathComponent().path)
        default: throw DevFlowError.invalid("请选择项目目录、Markdown、DevFlow JSON 或 Codex 会话 JSONL。")
        }
    }

    /// Rejects traversal, absolute references and every symbolic link below the selected root.
    public static func resolveSource(_ ref: SourceReference, root: String) throws -> URL {
        let candidate = try sourceURL(ref.path, root: root)
        guard inspectableExtensions.contains(candidate.pathExtension.lowercased()) else {
            throw DevFlowError.invalid("来源类型不在可查阅文档/图片白名单中：\(ref.path)")
        }
        let values: URLResourceValues
        do { values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) }
        catch { throw DevFlowError.invalid("来源文件不存在或不可读取：\(ref.path)") }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DevFlowError.invalid("来源必须是根目录内的普通文件：\(ref.path)")
        }
        return candidate
    }

    private static func sourceURL(_ path: String, root: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, path.utf8.count <= 4_096, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !components.contains(where: { [".git", ".env", ".ssh", ".aws", "secrets", "credentials"].contains($0.lowercased()) || $0.lowercased().hasPrefix(".env.") }) else {
            throw DevFlowError.invalid("来源路径必须是安全的项目内相对路径：\(path.prefix(160))")
        }
        let base = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard (try? base.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw DevFlowError.invalid("来源根目录不存在或不可读取。")
        }
        var candidate = base
        for component in components {
            candidate.appendPathComponent(component)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw DevFlowError.invalid("来源路径包含符号链接：\(path)")
            }
        }
        candidate = candidate.standardizedFileURL
        let prefix = base.path == "/" ? "/" : base.path + "/"
        guard candidate.path.hasPrefix(prefix), candidate.resolvingSymlinksInPath().path == candidate.path else {
            throw DevFlowError.invalid("来源路径越过项目边界：\(path)")
        }
        return candidate
    }

    private static func loadJSON(_ url: URL, sourceRootOverride: String?) throws -> ImportResult {
        let bytes = try read(url, limit: maximumJSONBytes)
        let package: ImportPackage
        do {
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  Set(object.keys).isSubset(of: ["schemaVersion", "name", "records", "supervision"]),
                  let rows = object["records"] as? [[String: Any]] else { throw DevFlowError.invalid("顶层字段不符合导入格式。") }
            let recordKeys: Set<String> = ["id", "kind", "title", "summary", "status", "occurredAt", "version", "origin", "source", "relatedIDs", "limitations", "action"]
            for row in rows {
                guard Set(row.keys).isSubset(of: recordKeys), let source = row["source"] as? [String: Any],
                      Set(source.keys).isSubset(of: ["path", "line", "excerpt", "digest"]) else {
                    throw DevFlowError.invalid("记录或来源中包含未支持字段。")
                }
                if let action = row["action"], !(action is NSNull) {
                    guard let fields = action as? [String: Any], Set(fields.keys).isSubset(of: ["kind", "callID"]) else {
                        throw DevFlowError.invalid("动作上下文包含未支持字段。")
                    }
                }
            }
            package = try JSONDecoder().decode(ImportPackage.self, from: bytes)
        }
        catch { throw DevFlowError.invalid("JSON 格式或必填字段无效：\(error.localizedDescription)") }
        guard [1, 2].contains(package.schemaVersion), (package.schemaVersion == 2) == (package.supervision != nil) else { throw DevFlowError.invalid("记录包使用 schemaVersion 1；带 supervision 的监督包使用 schemaVersion 2。") }
        try package.supervision?.validate()
        guard !package.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, package.name.count <= 200 else {
            throw DevFlowError.invalid("项目名称不能为空，且最多 200 字符。")
        }
        guard package.records.count <= maximumRecords else { throw DevFlowError.invalid("JSON 记录超过 \(maximumRecords) 条，未导入。") }
        let root = sourceRootOverride ?? url.deletingLastPathComponent().path
        var ids = Set<String>()
        for record in package.records {
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, record.id.count <= 200,
                  !record.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), ids.insert(record.id).inserted else {
                throw DevFlowError.invalid("记录 ID 为空、无效或重复：\(record.id.prefix(100))")
            }
            guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, record.title.count <= 500,
                  record.summary.utf8.count <= 100_000, record.source.excerpt.utf8.count <= 100_000,
                  record.relatedIDs.count <= 100, Set(record.relatedIDs).count == record.relatedIDs.count,
                  record.limitations.count <= 100, record.limitations.allSatisfy({ $0.utf8.count <= 10_000 }),
                  (record.source.line == nil || (record.source.line! > 0 && record.source.line! <= 10_000_000)),
                  (record.version?.count ?? 0) <= 200,
                  (record.action?.callID?.count ?? 0) <= 500 else {
                throw DevFlowError.invalid("记录字段超出允许范围：\(record.id)")
            }
            if let date = record.occurredAt, !validExplicitDate(date) { throw DevFlowError.invalid("记录日期无效：\(record.id)") }
            if let hash = record.source.digest, !matches(hash, "^[a-fA-F0-9]{64}$") {
                throw DevFlowError.invalid("来源摘要必须为 SHA-256：\(record.id)")
            }
            _ = try sourceURL(record.source.path, root: root)
        }
        for record in package.records {
            guard record.relatedIDs.allSatisfy({ ids.contains($0) && $0 != record.id }) else {
                throw DevFlowError.invalid("关联记录不存在或引用自身：\(record.id)")
            }
        }
        var warnings: [String] = []
        var records = package.records
        var fileResults: [String: Result<String, Error>] = [:]
        var verifiedBytes = 0
        for index in records.indices {
            let reference = records[index].source
            if fileResults[reference.path] == nil {
                do {
                    let source = try resolveSource(reference, root: root)
                    guard fileResults.count < maximumFiles, verifiedBytes < maximumTotalBytes else {
                        throw DevFlowError.invalid("来源核对达到文件数或总字节预算，本来源尚未核对。")
                    }
                    let data = try read(source, limit: min(maximumMarkdownBytes, maximumTotalBytes - verifiedBytes))
                    verifiedBytes += data.count
                    fileResults[reference.path] = .success(digest(data))
                } catch { fileResults[reference.path] = .failure(error) }
            }
            switch fileResults[reference.path]! {
            case .success(let current):
                if let expected = reference.digest, current != expected.lowercased() {
                    let message = "来源内容与记录摘要不一致，原结论需复核：\(reference.path)"
                    appendUnique(message, to: &warnings)
                    appendUnique(message, to: &records[index].limitations)
                }
            case .failure(let error):
                let message = "来源尚未核对（\(reference.path)）：\(error.localizedDescription)"
                appendUnique(message, to: &warnings)
                appendUnique(message, to: &records[index].limitations)
            }
            if records[index].origin == .execution {
                appendUnique("执行凭据类别由导入包声明；本应用未执行该检查，也未独立验证其真实性或业务正确性。", to: &records[index].limitations)
            }
        }
        return ImportResult(name: package.name, records: records, warnings: warnings, sourceRoot: root, supervision: package.supervision)
    }

    private static func loadDirectory(_ root: URL) throws -> ImportResult {
        var files: [URL] = []
        var warnings: [String] = []
        var stopped = false
        func walk(_ directory: URL, depth: Int, descend: Bool) throws {
            guard !stopped else { return }
            guard depth <= 12 else { appendUnique("部分文档目录深度超过 12 层，已跳过。", to: &warnings); return }
            let children: [URL]
            do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent } }
            catch {
                if depth == 0 { throw DevFlowError.invalid("所选目录不可读取。") }
                appendUnique("部分文档目录不可读取：\(relative(directory, root: root))", to: &warnings); return
            }
            for child in children {
                guard !stopped else { break }
                let name = child.lastPathComponent.lowercased()
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { appendUnique("已跳过符号链接：\(relative(child, root: root))", to: &warnings); continue }
                if values?.isDirectory == true {
                    guard !excludedDirectories.contains(name), !name.hasPrefix("."), !name.hasPrefix("private-") else { continue }
                    if descend || name == "docs" || name == "documentation" { try walk(child, depth: depth + 1, descend: true) }
                } else if values?.isRegularFile == true, ["md", "markdown"].contains(child.pathExtension.lowercased()) {
                    if files.count == maximumFiles {
                        appendUnique("文档超过 \(maximumFiles) 个，本次仅扫描按路径排序的前 \(maximumFiles) 个；其余未导入。请缩小目录。", to: &warnings)
                        stopped = true; break
                    }
                    files.append(child)
                }
            }
        }
        try walk(root, depth: 0, descend: ["docs", "documentation"].contains(root.lastPathComponent.lowercased()))
        var records: [ActivityRecord] = []
        var total = 0
        for file in files {
            let path = relative(file, root: root)
            guard total < maximumTotalBytes else { appendUnique("已达到 24 MiB 文档读取上限，后续文件未导入。", to: &warnings); break }
            do {
                let safe = try resolveSource(SourceReference(path: path), root: root.path)
                let data = try read(safe, limit: min(maximumMarkdownBytes, maximumTotalBytes - total))
                total += data.count
                guard let text = String(data: data, encoding: .utf8) else { appendUnique("已跳过非 UTF-8 文档：\(path)", to: &warnings); continue }
                let extracted = extract(text, path: path, hash: digest(data), warnings: &warnings)
                let remaining = maximumRecords - records.count
                if extracted.count > remaining {
                    records.append(contentsOf: extracted.prefix(remaining))
                    appendUnique("抽取结果超过 \(maximumRecords) 条，后续内容未导入；请缩小目录。", to: &warnings)
                    break
                }
                records.append(contentsOf: extracted)
            } catch { appendUnique("已跳过文档 \(path)：\(error.localizedDescription)", to: &warnings) }
        }
        if records.isEmpty { appendUnique("未发现可导入记录。目录导入只读取根层 Markdown 和 docs/documentation 内的 Markdown，证据、依赖、私密与构建目录不扫描。", to: &warnings) }
        return ImportResult(name: root.lastPathComponent, records: records, warnings: warnings, sourceRoot: root.path)
    }

    private struct Section {
        var heading: String
        var headingLine: Int
        var lines: [(number: Int, text: String)]
        var explicitHeading: Bool
        var kind: RecordKind
        var isExpectation: Bool
    }

    private static func extract(_ text: String, path: String, hash: String, warnings: inout [String]) -> [ActivityRecord] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [Section] = []
        var current = Section(heading: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, headingLine: 1, lines: [], explicitHeading: false, kind: .development, isExpectation: false)
        // Only semantic classification is inherited. Parent dates are never event dates for child records.
        var headingContexts: [(level: Int, kind: RecordKind, isExpectation: Bool)] = []
        var fence: String?
        for (offset, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == marker { fence = nil } else if fence == nil { fence = marker }
                continue
            }
            guard fence == nil else { continue }
            if let expression = try? NSRegularExpression(pattern: "^ {0,3}(#{1,6})\\s+(.+?)\\s*#*\\s*$"),
               let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let range = Range(match.range(at: 2), in: raw) {
                if !current.lines.isEmpty { sections.append(current) }
                let heading = String(raw[range])
                let level = match.range(at: 1).length
                while let parent = headingContexts.last, parent.level >= level { headingContexts.removeLast() }
                let explicitKind = headingKind(heading)
                let kind = explicitKind ?? headingContexts.last?.kind ?? .development
                let expectation = explicitKind == nil ? (headingContexts.last?.isExpectation ?? false) : isExpectationHeading(heading)
                headingContexts.append((level: level, kind: kind, isExpectation: expectation))
                current = Section(heading: heading, headingLine: offset + 1, lines: [], explicitHeading: true, kind: kind, isExpectation: expectation)
            } else { current.lines.append((offset + 1, raw)) }
        }
        if !current.lines.isEmpty { sections.append(current) }
        var records: [ActivityRecord] = []
        var occurrences: [String: Int] = [:]
        func emit(title: String, summary: String, line: Int, kind: RecordKind, heading: String, dateHeading: String, anchor: String, isExpectation: Bool, declaredStatus: String? = nil) {
            guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard records.count < maximumRecords else {
                appendUnique("\(path) 抽取达到 \(maximumRecords) 条上限，后续内容未导入。", to: &warnings); return
            }
            let seed = path + "\n" + heading + "\n" + anchor
            let ordinal = occurrences[seed, default: 0]
            occurrences[seed] = ordinal + 1
            let id = "md-" + String(digest(Data((seed + "\n\(ordinal)").utf8)).prefix(32))
            var limitations = ["从 Markdown 有限抽取，属于文档记载，未独立执行或验证；原文中的计划不代表已经完成。"]
            let dates = explicitDates(in: dateHeading + "\n" + summary)
            let date = dates.count == 1 ? dates.first : nil
            if dates.count > 1 { limitations.append("本段包含多个日期，未自动指定事件时间。") }
            else if date != nil { limitations.append("日期来自本段正文标注，未独立核实实际发生时间。") }
            // A requirement can describe a failed attempt without claiming that the requirement itself failed.
            let status: RecordStatus = ((kind == .requirement || isExpectation) && declaredStatus == nil) ? .recorded : inferStatus(declaredStatus ?? summary, explicitDeclaration: declaredStatus != nil)
            if status == .needsReview { limitations.append("同段含不同状态或范围，需查看原文区分先后与验收层级。") }
            var clipped = summary
            if clipped.count > 12_000 {
                clipped = String(clipped.prefix(12_000)) + "\n[此记录正文超过 12000 字符，后续内容请查看来源]"
                appendUnique("\(path):\(line) 的单条正文超过 12000 字符，记录已明确截断，来源文件未修改。", to: &warnings)
                limitations.append("正文已截断；状态判定基于完整段落。")
            }
            records.append(ActivityRecord(id: id, kind: kind, title: String(title.prefix(200)), summary: clipped, status: status, occurredAt: date, origin: .document, source: SourceReference(path: path, line: line, excerpt: clipped, digest: hash), limitations: limitations))
        }
        for section in sections {
            var prose: [(number: Int, text: String)] = []
            var tableHeader: [String]?
            for i in section.lines.indices {
                let item = section.lines[i]
                let trimmed = item.text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                    let cells = tableCells(trimmed)
                    if cells.allSatisfy({ matches($0, "^:?-{3,}:?$") }) { continue }
                    let nextIsSeparator = i + 1 < section.lines.count && tableCells(section.lines[i + 1].text).allSatisfy({ matches($0, "^:?-{3,}:?$") }) && section.lines[i + 1].text.contains("|")
                    if nextIsSeparator { tableHeader = cells; continue }
                    guard !cells.isEmpty, !cells.allSatisfy({ $0.isEmpty }) else { continue }
                    let first = cells[0]
                    let title = cells.prefix(2).filter { !$0.isEmpty }.joined(separator: " · ")
                    let statusIndex = tableHeader?.firstIndex(where: { matches($0, "(?i)^(?:当前)?状态$|^status$") })
                    let declared = statusIndex.flatMap { cells.indices.contains($0) ? cells[$0] : nil }
                    emit(title: title, summary: item.text, line: item.number, kind: inferKind(section.heading, rowID: first, inherited: section.kind), heading: section.heading, dateHeading: section.explicitHeading ? section.heading : "", anchor: "row:" + first, isExpectation: section.isExpectation, declaredStatus: declared)
                } else {
                    if !trimmed.isEmpty { prose.append(item) }
                    if !trimmed.isEmpty { tableHeader = nil }
                }
            }
            if !prose.isEmpty {
                // List entries are separate historical statements; keep an earlier failure even if a later entry passes.
                var block: [(number: Int, text: String)] = []
                var blockIndex = 0
                func flush() {
                    guard let first = block.first else { return }
                    let summary = block.map(\.text).joined(separator: "\n")
                    let identifier = first.text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^[-*+]\\s+", with: "", options: .regularExpression)
                    let rowID = matches(identifier, "^[RATEUD][0-9]+(?:[.:： ]|$)") ? (identifier.components(separatedBy: CharacterSet(charactersIn: ":： .")).first ?? "") : nil
                    let title = rowID == nil ? section.heading : String(identifier.prefix(160))
                    emit(title: title, summary: summary, line: first.number, kind: inferKind(section.heading, rowID: rowID, inherited: section.kind), heading: section.heading, dateHeading: section.explicitHeading ? section.heading : "", anchor: rowID.map { "item:" + $0 } ?? "prose:\(blockIndex)", isExpectation: section.isExpectation)
                    blockIndex += 1; block = []
                }
                for item in prose {
                    if matches(item.text, "^\\s*(?:[-*+]\\s+|[0-9]+[.)]\\s+)") { flush() }
                    block.append(item)
                }
                flush()
            }
        }
        return records
    }

    private static func inferKind(_ heading: String, rowID: String? = nil, inherited: RecordKind = .development) -> RecordKind {
        if let rowID {
            if matches(rowID, "^[RA][0-9]+(?:\\W|$)") { return .requirement }
            if matches(rowID, "^[TE][0-9]+(?:\\W|$)") { return .test }
            if matches(rowID, "^D[0-9]+(?:\\W|$)") { return .bug }
            if matches(rowID, "^U[0-9]+(?:\\W|$)") { return .development }
        }
        return headingKind(heading) ?? inherited
    }

    private static func headingKind(_ heading: String) -> RecordKind? {
        if matches(heading, "(?i)缺陷|漏检|问题|bug|failure|复盘") { return .bug }
        if matches(heading, "(?i)需求|目标|验收标准|requirements|acceptance criteria") { return .requirement }
        if matches(heading, "(?i)测试|验证|回归|执行证据|验收结果|验收记录|核心检查|tests?|evidence") { return .test }
        if matches(heading, "(?i)交付|发布|部署|delivery|release") { return .delivery }
        if matches(heading, "(?i)决策|原则|约束|边界|decision") { return .decision }
        if matches(heading, "(?i)研发|开发|实施|计划|规划|待办|下一步|development|implementation") { return .development }
        return nil
    }

    private static func isExpectationHeading(_ heading: String) -> Bool {
        matches(heading, "(?i)需求|目标|验收标准|测试用例|计划|规划|待办|下一步|requirements|acceptance criteria|test cases")
    }

    private static func inferStatus(_ text: String, explicitDeclaration: Bool = false) -> RecordStatus {
        var value = text.replacingOccurrences(of: "`", with: "")
        for pattern in ["(?i)\\b(?:no|zero|0)\\s+(?:failures?|failed|errors?)\\b", "(?:零|0)\\s*(?:项|个)?(?:失败|错误)", "(?:没有|无)(?:失败|错误)", "(?i)\\bnot failed\\b"] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let pendingDeclaration = explicitDeclaration && matches(value, "^\\s*(?:待验证|待验收)(?:\\s*$|[，,。;；])")
        let notRun = pendingDeclaration || matches(value, "(?i)NOT_RUN|NOT_ACCEPTED|未(?:运行|执行|验收|验证|测试|复跑)|未经验证|尚未验")
        let failed = matches(value, "(?i)\\b(?:FAILED|FAIL)\\b|未通过|not\\s+ok|(?:测试|检查|构建|回归|执行|用例|断言).{0,12}(?:失败|报错)|[1-9][0-9]*\\s*(?:项|个)?失败|[1-9][0-9]*\\s+(?:failures?|errors?)")
        let acceptedDeclaration = explicitDeclaration && matches(value, "^\\s*(?:本机)?已验收(?:\\s*$|[，,。;；])")
        let passed = acceptedDeclaration || matches(value, "(?i)\\bPASSED\\b|\\bGREEN\\b|FIXED_RELEASED|(?:测试|检查|回归|验收).{0,12}(?<!未)通过|[0-9]+\\s*(?:项|个)?(?:测试|方法)?(?:全部)?通过|^(?:已)?通过$")
        if passed && (failed || notRun) { return .needsReview }
        if failed { return .failed }
        if notRun { return .notRun }
        if matches(value, "(?i)\\bBLOCKED\\b|受阻") { return .blocked }
        let openToken = "OPEN(?:_[A-Z_]+)?\\b"
        let openDeclaration = explicitDeclaration && matches(value, "(?i)^\\s*" + openToken + "(?:\\s*$|\\s*[，,;；。:(（])")
        let openStatement = matches(value, "(?i)(?:状态|status|state)\\s*[:：=]\\s*" + openToken + "|(?:仍(?:为)?|保持|remains?)\\s*" + openToken)
        if openDeclaration || openStatement || matches(value, "仍未(?:完成|关闭|解决)|尚未关闭") { return .open }
        if matches(value, "(?i)\\b(?:UNKNOWN|awaiting_evidence)\\b|状态未知|结果未知|结果未确认") { return .unknown }
        if matches(value, "(?i)NEEDS_REVIEW|待复核") { return .needsReview }
        if passed { return .passed }
        if matches(value, "(?i)IN_PROGRESS|VERIFYING|进行中|验证中") { return .inProgress }
        return .recorded
    }

    private static func tableCells(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return [] }
        return trimmed.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func explicitDates(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?<![0-9])20[0-9]{2}-[0-9]{2}-[0-9]{2}(?:[T ][0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\\.[0-9]+)?)?(?:Z|[+-][0-9]{2}:[0-9]{2})?)?(?![0-9])") else { return [] }
        var result: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                let date = String(text[range])
                if validExplicitDate(date), !result.contains(date) { result.append(date) }
            }
        }
        return result
    }

    private static func validExplicitDate(_ value: String) -> Bool {
        guard matches(value, "^20[0-9]{2}-[0-9]{2}-[0-9]{2}(?:[T ][0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\\.[0-9]+)?)?(?:Z|[+-][0-9]{2}:[0-9]{2})?)?$") else { return false }
        let day = String(value.prefix(10)).split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: day[0], month: day[1], day: day[2])
        guard let date = calendar.date(from: components) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        guard checked.year == day[0], checked.month == day[1], checked.day == day[2] else { return false }
        if value.count > 10 {
            let suffix = String(value.dropFirst(11))
            let parts = suffix.prefix(8).split(separator: ":")
            guard parts.count >= 2, let hour = Int(parts[0]), hour < 24,
                  let minute = Int(parts[1].prefix(2)), minute < 60 else { return false }
            if parts.count > 2, let second = Int(parts[2].prefix(2)), second >= 60 { return false }
            if let range = value.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) {
                let zone = value[range].dropFirst().split(separator: ":").compactMap { Int($0) }
                guard zone.count == 2, zone[0] < 24, zone[1] < 60 else { return false }
            }
        }
        return true
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    private static func relative(_ url: URL, root: URL) -> String {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        return canonicalURL.pathComponents.dropFirst(canonicalRoot.pathComponents.count).joined(separator: "/")
    }
    private static func appendUnique(_ message: String, to array: inout [String]) { if !array.contains(message) { array.append(message) } }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        guard limit > 0 else { throw DevFlowError.invalid("文档读取总预算已用尽。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw DevFlowError.invalid("文件超过本次读取上限 \(limit) 字节，未导入该文件。") }
        }
        return data
    }
}
