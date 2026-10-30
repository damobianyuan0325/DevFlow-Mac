import Foundation

public struct ProjectRefresh {
    public var project: Project
    public var primaryError: String?
}

/// User-selected sources only. This loader never enumerates a session directory or runs imported commands.
public enum ProjectSources {
    public static func preservingControls(from current: Project, in updated: Project) -> Project {
        var result = updated
        result.refreshPaused = current.refreshPaused
        if var sources = result.sessionSources {
            for index in sources.indices {
                if let control = current.sessionSources?.first(where: { $0.id == sources[index].id }) {
                    sources[index].isEnabled = control.isEnabled
                }
            }
            result.sessionSources = sources
        }
        return result
    }

    public static func applying(_ result: ImportResult, to previous: Project) -> Project {
        var project = previous
        if let old = previous.supervision, old != result.supervision {
            if !(project.supervisionHistory ?? []).contains(old) { project.supervisionHistory = (project.supervisionHistory ?? []) + [old] }
        }
        project.name = result.name; project.sourceRoot = result.sourceRoot
        project.supervision = result.supervision; project.primaryRecords = result.records
        project.warnings = result.warnings; project.refreshedAt = Date()
        project.primarySourceError = nil
        let combined = combine(primary: result.records, sessions: project.sessionSources ?? [], warnings: &project.warnings)
        project.records = ProjectHistory.merging(old: previous.records, new: combined)
        return project
    }

    public static func attaching(url: URL, to previous: Project) throws -> Project {
        guard !previous.isSample else { throw DevFlowError.invalid("请先导入实际项目，再关联其开发会话。") }
        guard url.pathExtension.lowercased() == "jsonl" else { throw DevFlowError.invalid("关联来源必须是手动选择的 Codex JSONL。") }
        let result = try ProjectImporter.load(url: url)
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path != URL(fileURLWithPath: previous.importPath).standardizedFileURL.resolvingSymlinksInPath().path else {
            throw DevFlowError.invalid("这已经是当前项目的主来源，无需再次关联。")
        }
        var project = previous
        var sources = project.sessionSources ?? []
        if let index = sources.firstIndex(where: { $0.path == path }) {
            sources[index].name = result.name; sources[index].records = result.records
            sources[index].warnings = result.warnings; sources[index].refreshedAt = Date(); sources[index].error = nil
        } else {
            guard sources.count < 8 else { throw DevFlowError.invalid("一个项目最多关联 8 个明确选择的会话。请缩小本次监督范围。") }
            sources.append(SessionSource(path: path, name: result.name, records: result.records, warnings: result.warnings, refreshedAt: Date()))
        }
        project.sessionSources = sources
        project.primaryRecords = project.primaryRecords ?? previous.records
        let combined = combine(primary: project.primaryRecords ?? [], sessions: sources, warnings: &project.warnings)
        project.records = ProjectHistory.merging(old: previous.records, new: combined)
        return project
    }

    public static func refresh(_ previous: Project) -> ProjectRefresh {
        var project = previous
        var error: String?
        do {
            let result = try ProjectImporter.load(url: URL(fileURLWithPath: project.importPath), sourceRootOverride: project.sourceRoot)
            project = applying(result, to: previous)
            // applying preserves the old source snapshots; their old warnings must not
            // survive a successful read below. Compose warnings once from final states.
            project.warnings = result.warnings
        } catch let failure {
            error = "主来源暂不可读，保留上次资料：\(failure.localizedDescription)"
            project.warnings = [error!]
            project.primaryRecords = previous.primaryRecords ?? previous.records
        }
        var sources = project.sessionSources ?? []
        for index in sources.indices {
            guard sources[index].isEnabled else {
                project.warnings.append("来源已暂停，显示最后读取的记录：\(sources[index].name)")
                continue
            }
            do {
                let result = try ProjectImporter.load(url: URL(fileURLWithPath: sources[index].path))
                sources[index].records = result.records; sources[index].name = result.name
                sources[index].warnings = result.warnings; sources[index].refreshedAt = Date(); sources[index].error = nil
            } catch {
                sources[index].error = "读取失败，保留此前内容：\(error.localizedDescription)"
            }
        }
        project.sessionSources = sources
        let combined = combine(primary: project.primaryRecords ?? [], sessions: sources, warnings: &project.warnings)
        project.records = ProjectHistory.merging(old: previous.records, new: combined)
        project.primarySourceError = error
        return ProjectRefresh(project: project, primaryError: error)
    }

    private static func combine(primary: [ActivityRecord], sessions: [SessionSource], warnings: inout [String]) -> [ActivityRecord] {
        var result: [ActivityRecord] = []
        var indices: [String: Int] = [:]
        for row in primary + sessions.flatMap(\.records) {
            if let index = indices[row.id] {
                if result[index] != row { warnings.append("不同来源包含冲突记录 ID，保留先接入来源；请核对：\(row.id)") }
            } else { indices[row.id] = result.count; result.append(row) }
        }
        for source in sessions {
            if let error = source.error { warnings.append("\(source.name)：\(error)") }
            warnings += source.warnings.map { "\(source.name)：\($0)" }
        }
        var seen = Set<String>(); warnings = warnings.filter { seen.insert($0).inserted }
        return result
    }
}
