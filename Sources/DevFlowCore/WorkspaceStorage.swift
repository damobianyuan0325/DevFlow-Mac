import Foundation

public struct WorkspaceStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> WorkspaceState {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceState() }
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
        guard state.schemaVersion == 1 else { throw DevFlowError.invalid("工作区版本不受支持；原文件保持不变。") }
        return state
    }
    public func save(_ state: WorkspaceState) throws {
        // Refuse to replace an unreadable existing workspace.
        _ = try load()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            try old.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try bytes.write(to: url, options: .atomic)
    }
}

public enum ProjectHistory {
    public static func merging(old: [ActivityRecord], new: [ActivityRecord]) -> [ActivityRecord] {
        var result = new
        let incoming = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        var ids = Set(new.map(\.id))
        for previous in old {
            if let current = incoming[previous.id] {
                if current == previous { continue }
                // File-wide hash changes and generated read warnings are not revisions to a claim.
                if semanticRecord(current) == semanticRecord(previous) { continue }
                var snapshot = previous
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let identity = (try? encoder.encode(previous)) ?? Data(previous.id.utf8)
                snapshot.id = previous.id + "-history-" + String(ProjectImporter.digest(identity).prefix(12))
                snapshot.limitations.append("来源后来发生变化；此条为先前导入保留的历史版本，不能代表当前状态。")
                if ids.insert(snapshot.id).inserted { result.append(snapshot) }
            } else if ids.insert(previous.id).inserted {
                var retained = previous
                let message = "最新导入未包含此记录；保留历史，当前适用性待核实。"
                if !retained.limitations.contains(message) { retained.limitations.append(message) }
                result.append(retained)
            }
        }
        return result
    }
    private static func semanticRecord(_ record: ActivityRecord) -> ActivityRecord {
        var copy = record; copy.source.digest = nil
        copy.limitations.removeAll { $0.hasPrefix("来源尚未核对（") || $0.hasPrefix("来源内容与记录摘要不一致") }
        return copy
    }
}
