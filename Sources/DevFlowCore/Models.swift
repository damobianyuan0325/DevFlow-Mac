import Foundation

public enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case requirement, development, test, bug, decision, delivery
    public var id: String { rawValue }
    public var title: String { switch self { case .requirement: return "需求"; case .development: return "研发"; case .test: return "测试"; case .bug: return "缺陷"; case .decision: return "决策"; case .delivery: return "交付" } }
    public var symbol: String { switch self { case .requirement: return "text.alignleft"; case .development: return "hammer"; case .test: return "checkmark.seal"; case .bug: return "ladybug"; case .decision: return "arrow.triangle.branch"; case .delivery: return "shippingbox" } }
}

public enum RecordStatus: String, Codable, CaseIterable {
    case recorded, inProgress, passed, failed, open, notRun, blocked, unknown, needsReview
    public var title: String { switch self { case .recorded: return "已记录"; case .inProgress: return "记录为进行中"; case .passed: return "记录为通过"; case .failed: return "记录为失败"; case .open: return "尚未关闭"; case .notRun: return "未验证"; case .blocked: return "受阻"; case .unknown: return "状态未知"; case .needsReview: return "待复核" } }
    public var needsAttention: Bool { [.failed, .open, .notRun, .blocked, .unknown, .needsReview].contains(self) }
}

public enum EvidenceOrigin: String, Codable, CaseIterable {
    case document, execution, retrospective
    public var title: String { switch self { case .document: return "文档记载"; case .execution: return "执行凭据"; case .retrospective: return "复盘归纳" } }
}

public struct SourceReference: Codable, Equatable {
    public var path: String
    public var line: Int?
    public var excerpt: String
    public var digest: String?
    public init(path: String, line: Int? = nil, excerpt: String = "", digest: String? = nil) { self.path = path; self.line = line; self.excerpt = excerpt; self.digest = digest }
}

/// The observable source event type; this is not a claim of requirement completion.
public enum ActionKind: String, Codable {
    case request, progress, toolCall, toolResult, command, fileChange, agentReport, other
}

public struct ActionContext: Codable, Equatable {
    public var kind: ActionKind
    public var callID: String?
    public init(kind: ActionKind, callID: String? = nil) { self.kind = kind; self.callID = callID }
}

public struct ActivityRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var kind: RecordKind
    public var title: String
    public var summary: String
    public var status: RecordStatus
    public var occurredAt: String?
    public var version: String?
    public var origin: EvidenceOrigin
    public var source: SourceReference
    public var relatedIDs: [String]
    public var limitations: [String]
    public var action: ActionContext?
    public init(id: String, kind: RecordKind, title: String, summary: String, status: RecordStatus = .recorded, occurredAt: String? = nil, version: String? = nil, origin: EvidenceOrigin = .document, source: SourceReference, relatedIDs: [String] = [], limitations: [String] = [], action: ActionContext? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.summary = summary; self.status = status; self.occurredAt = occurredAt; self.version = version; self.origin = origin; self.source = source; self.relatedIDs = relatedIDs; self.limitations = limitations
        self.action = action
    }
}

public struct ImportPackage: Codable {
    public var schemaVersion: Int
    public var name: String
    public var records: [ActivityRecord]
    public var supervision: SupervisionPlan?
    public init(name: String, records: [ActivityRecord], supervision: SupervisionPlan? = nil) { schemaVersion = supervision == nil ? 1 : 2; self.name = name; self.records = records; self.supervision = supervision }
}

/// Only an explicit user selection can add an external session source.
public struct SessionSource: Codable, Equatable, Identifiable {
    public var id: UUID
    public var path: String
    public var name: String
    public var records: [ActivityRecord]
    public var warnings: [String]
    public var refreshedAt: Date?
    public var error: String?
    public var isEnabled: Bool
    public init(id: UUID = UUID(), path: String, name: String = "开发会话", records: [ActivityRecord] = [], warnings: [String] = [], refreshedAt: Date? = nil, error: String? = nil, isEnabled: Bool = true) {
        self.id = id; self.path = path; self.name = name; self.records = records; self.warnings = warnings; self.refreshedAt = refreshedAt; self.error = error; self.isEnabled = isEnabled
    }
}

public struct Project: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var importPath: String
    public var sourceRoot: String
    public var importedAt: Date
    public var refreshedAt: Date
    public var records: [ActivityRecord]
    public var warnings: [String]
    public var isSample: Bool
    public var supervision: SupervisionPlan?
    public var supervisionHistory: [SupervisionPlan]?
    public var sessionSources: [SessionSource]?
    public var primaryRecords: [ActivityRecord]?
    public var refreshPaused: Bool?
    public var primarySourceError: String?
    public init(id: UUID = UUID(), name: String, importPath: String, sourceRoot: String, records: [ActivityRecord], warnings: [String] = [], isSample: Bool = false, supervision: SupervisionPlan? = nil, sessionSources: [SessionSource]? = nil) { self.id = id; self.name = name; self.importPath = importPath; self.sourceRoot = sourceRoot; self.importedAt = Date(); self.refreshedAt = Date(); self.records = records; self.warnings = warnings; self.isSample = isSample; self.supervision = supervision; self.sessionSources = sessionSources; self.primaryRecords = records }
}

public struct FeedbackDraft: Codable, Identifiable, Equatable {
    public var id: UUID
    public var projectID: UUID
    public var recordID: String
    public var text: String
    public var updatedAt: Date
    public var copiedAt: Date?
    public init(projectID: UUID, recordID: String, text: String) { self.id = UUID(); self.projectID = projectID; self.recordID = recordID; self.text = text; self.updatedAt = Date() }
}

public struct WorkspaceState: Codable {
    public var schemaVersion = 1
    public var projects: [Project] = []
    public var drafts: [FeedbackDraft] = []
    public var selectedProjectID: UUID?
    public init() {}
}

public enum DevFlowError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum FeedbackComposer {
    public static func compose(record: ActivityRecord, project: Project) -> String {
        func location(_ item: ActivityRecord) -> String {
            item.source.path + (item.source.line.map { ":\($0)" } ?? "")
        }
        let excerpt = record.source.excerpt.isEmpty ? "未提供原文摘录，请查看来源。" : String(record.source.excerpt.prefix(4_000)) + (record.source.excerpt.count > 4_000 ? "\n[摘录已截断，请查看原文件]" : "")
        var limits = record.limitations.prefix(10).map { "- " + $0 }.joined(separator: "\n")
        if limits.isEmpty { limits = "未记录额外限制；这不表示已经验证所有场景。" }
        if record.limitations.count > 10 { limits += "\n[其余\(record.limitations.count - 10)条限制请在客户端查看]" }
        var contextIDs = record.relatedIDs
        for other in project.records where other.id != record.id && other.relatedIDs.contains(record.id) && !contextIDs.contains(other.id) { contextIDs.append(other.id) }
        var related = contextIDs.prefix(10).map { id in
            guard let item = project.records.first(where: { $0.id == id }) else { return "- \(id)：关联记录未导入" }
            return "- \(id) · \(item.title)；\(item.status.title)；版本：\(item.version ?? "未记录，适用性待核查")；\(location(item))（\(item.origin.title)）"
        }.joined(separator: "\n")
        if related.isEmpty { related = "尚无明确关联记录；不能据此判断已有完整验证。" }
        if contextIDs.count > 10 { related += "\n[其余\(contextIDs.count - 10)条关联请在客户端查看]" }
        return "项目：\(project.name)\n事项：\(record.title)\n记录状态：\(record.status.title)\n对应版本：\(record.version ?? "未记录，适用性待核查")\n原记录时间：\(record.occurredAt ?? "未知")\n\n现象与依据：\n\(record.summary)\n\n来源：\(location(record))（\(record.origin.title)）\n原文摘录：\n\(excerpt)\n\n已知限制与待补证据：\n\(limits)\n\n关联记录（关联不等于验证或修复关系）：\n\(related)\n\n希望核查或调整：\n请核对以上记录在当前版本是否仍适用，区分历史失败与当前问题，说明实际影响、已有验证与待补证据。\n\n我的补充：\n"
    }
}
