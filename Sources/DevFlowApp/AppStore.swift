import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DevFlowCore

@MainActor
final class AppStore: ObservableObject {
    @Published var state = WorkspaceState()
    @Published var selectedProjectID: UUID?
    @Published var selectedRecordID: String?
    @Published var errorMessage: String?
    @Published var isImporting = false
    @Published var lastRefreshError: String?
    @Published var supervisionAssessment: SupervisionAssessment?
    private var assessmentGeneration = UUID()
    private let storage: WorkspaceStorage
    private var timer: Timer?
    private var persistenceBlocked = false
    var selectedProject: Project? { state.projects.first { $0.id == selectedProjectID } }
    var selectedRecord: ActivityRecord? { selectedProject?.records.first { $0.id == selectedRecordID } }
    var isSelectedSession: Bool { selectedProject.map { URL(fileURLWithPath: $0.importPath).pathExtension.lowercased() == "jsonl" } ?? false }
    var isRefreshPaused: Bool { selectedProject?.refreshPaused == true }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DevFlow")
        if let index = args.firstIndex(of: "--workspace"), args.indices.contains(index + 1) { storage = WorkspaceStorage(url: URL(fileURLWithPath: args[index + 1])) }
        else { storage = WorkspaceStorage(url: root.appendingPathComponent("workspace.json")) }
        do { state = try storage.load() } catch { persistenceBlocked = true; errorMessage = "工作区读取失败，原文件未修改：\(error.localizedDescription)" }
        selectedProjectID = state.projects.first(where: { $0.id == state.selectedProjectID })?.id ?? state.projects.first?.id
        lastRefreshError = selectedProject?.primarySourceError
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, NSApp.isActive, !self.isImporting, !self.isRefreshPaused, self.selectedProject?.isSample == false else { return }; self.refreshSelected(silent: true) }
        }
        if let index = args.firstIndex(of: "--import"), args.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: args[index + 1]); Task { await importURL(url) }
        }
        updateAssessment()
    }

    func selectProject(_ id: UUID) { selectedProjectID = id; selectedRecordID = nil; lastRefreshError = selectedProject?.primarySourceError; updateAssessment(); persist() }
    func selectRecord(_ id: String) { selectedRecordID = id }
    func importProject() { presentImportPanel(sessionOnly: false) }
    func connectDevelopmentSession() { presentImportPanel(sessionOnly: true) }
    private func presentImportPanel(sessionOnly: Bool) {
        guard !isImporting else { return }
        // Keep refresh from competing with a source selection while its native panel is open.
        isImporting = true
        let panel = NSOpenPanel()
        panel.title = sessionOnly ? "接入开发会话" : "选择项目资料或开发会话"
        panel.message = sessionOnly
            ? "选择一个 Codex JSONL 原始会话文件。只读提取其中已记录的公开消息、工具输入与结果，不扫描其他会话，不展示内部推理与系统配置。"
            : "可选择 Markdown 资料、DevFlow JSON 或单个 Codex JSONL 会话；只读导入，不执行资料中的命令。"
        panel.prompt = sessionOnly ? "接入会话" : "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = !sessionOnly
        panel.allowsMultipleSelection = false
        if sessionOnly {
            panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .data]
            panel.allowsOtherFileTypes = false
        }
        guard panel.runModal() == .OK, let url = panel.url else { isImporting = false; return }
        if sessionOnly && url.pathExtension.lowercased() != "jsonl" {
            isImporting = false
            errorMessage = "请选择一个 .jsonl 会话文件；没有读取其他文件。"
            return
        }
        Task { await performImportURL(url) }
    }
    func importURL(_ url: URL, sample: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true
        await performImportURL(url, sample: sample)
    }
    private func performImportURL(_ url: URL, sample: Bool = false) async {
        defer { isImporting = false }
        do {
            let existing = state.projects.first { sample ? $0.isSample : $0.importPath == url.path }
            // Moving an app must not create another built-in sample or lose a user-bound source root.
            let usedBundleRoot = sample && existing.map { $0.sourceRoot == URL(fileURLWithPath: $0.importPath).deletingLastPathComponent().path } == true
            let sourceRoot = usedBundleRoot ? nil : existing?.sourceRoot
            let result = try await Task.detached(priority: .userInitiated) { try ProjectImporter.load(url: url, sourceRootOverride: sourceRoot) }.value
            if let index = state.projects.firstIndex(where: { $0.id == existing?.id }) {
                state.projects[index] = ProjectSources.applying(result, to: state.projects[index])
                state.projects[index].importPath = url.path
                selectedProjectID = state.projects[index].id
            } else {
                let project = Project(name: result.name, importPath: url.path, sourceRoot: result.sourceRoot, records: result.records, warnings: result.warnings, isSample: sample, supervision: result.supervision)
                state.projects.append(project); selectedProjectID = project.id
            }
            selectedRecordID = nil; lastRefreshError = nil; updateAssessment(); persist()
        } catch { errorMessage = "导入未完成：\(error.localizedDescription)" }
    }
    func loadSample() {
        guard let url = AppResources.bundle?.url(forResource: "example-history", withExtension: "json", subdirectory: "Resources") else { errorMessage = "复盘样本资源未找到。"; return }
        Task { await importURL(url, sample: true) }
    }
    func refreshSelected() { refreshSelected(silent: false) }
    private func refreshSelected(silent: Bool) {
        guard let project = selectedProject, !isImporting, !project.isSample else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let result = await Task.detached(priority: .utility) { ProjectSources.refresh(project) }.value
                guard let index = state.projects.firstIndex(where: { $0.id == project.id }) else { return }
                // Controls can change during I/O; never undo a user's pause.
                let updated = ProjectSources.preservingControls(from: state.projects[index], in: result.project)
                state.projects[index] = updated
                if selectedProjectID == project.id { lastRefreshError = result.primaryError; updateAssessment() }
                if !silent, let error = result.primaryError { errorMessage = error }
                persist()
            }
        }
    }
    func openSource(_ record: ActivityRecord) {
        guard let project = selectedProject else { return }
        guard !isSelectedSession, URL(fileURLWithPath: record.source.path).pathExtension.lowercased() != "jsonl" else {
            errorMessage = "会话来源仅在应用内展示过滤后的公开摘录，不直接打开含其他私密信息的原始文件。"
            return
        }
        do { let url = try ProjectImporter.resolveSource(record.source, root: project.sourceRoot); NSWorkspace.shared.open(url) }
        catch { errorMessage = "原文件不可用。已保存的摘录仍可查看。\n\(error.localizedDescription)" }
    }
    func revealSource(_ record: ActivityRecord) {
        guard let project = selectedProject else { return }
        guard !isSelectedSession, URL(fileURLWithPath: record.source.path).pathExtension.lowercased() != "jsonl" else {
            errorMessage = "会话的本地来源位置和行号已显示在详情中，仅提供过滤后的公开摘录。"
            return
        }
        do { let url = try ProjectImporter.resolveSource(record.source, root: project.sourceRoot); NSWorkspace.shared.activateFileViewerSelecting([url]) }
        catch { errorMessage = error.localizedDescription }
    }
    func attachSourceRoot() {
        guard let project = selectedProject, !isImporting, URL(fileURLWithPath: project.importPath).pathExtension.lowercased() == "json" else { return }
        isImporting = true; defer { isImporting = false }
        let panel = NSOpenPanel(); panel.title = "关联原始资料目录"; panel.message = "选择记录中相对路径所属的项目目录。只建立来源关联，不修改原文件。"; panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url,
              let index = state.projects.firstIndex(where: { $0.id == project.id }) else { return }
        do {
            let result = try ProjectImporter.load(url: URL(fileURLWithPath: project.importPath), sourceRootOverride: url.path)
            state.projects[index] = ProjectSources.applying(result, to: state.projects[index])
            lastRefreshError = nil
            updateAssessment(); persist()
        } catch { errorMessage = "来源关联未修改：\(error.localizedDescription)" }
    }
    func feedbackText(for record: ActivityRecord) -> String {
        guard let project = selectedProject else { return "" }
        return state.drafts.first { $0.projectID == project.id && $0.recordID == record.id }?.text ?? FeedbackComposer.compose(record: record, project: project)
    }
    func saveFeedback(_ text: String, for record: ActivityRecord) {
        guard let project = selectedProject else { return }
        if let index = state.drafts.firstIndex(where: { $0.projectID == project.id && $0.recordID == record.id }) {
            state.drafts[index].text = text; state.drafts[index].updatedAt = Date()
        } else { state.drafts.append(FeedbackDraft(projectID: project.id, recordID: record.id, text: text)) }
        updateAssessment(); persist()
    }
    func copyFeedback(_ text: String, for record: ActivityRecord) {
        saveFeedback(text, for: record)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        if let index = state.drafts.firstIndex(where: { $0.projectID == selectedProjectID && $0.recordID == record.id }) { state.drafts[index].copiedAt = Date(); persist() }
    }
    func removeProject(_ id: UUID) {
        state.projects.removeAll { $0.id == id }; state.drafts.removeAll { $0.projectID == id }
        if selectedProjectID == id { selectedProjectID = state.projects.first?.id; selectedRecordID = nil }
        updateAssessment(); persist()
    }
    func attachSessionToSelectedProject() {
        guard let project = selectedProject, !project.isSample, !isImporting else { return }
        isImporting = true
        let panel = NSOpenPanel(); panel.title = "关联开发会话到 \(project.name)"
        panel.message = "只读取你选择的这个会话；与项目的需求和验证资料一起查看。不会扫描其他聊天。"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .data]; panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else { isImporting = false; return }
        Task {
            defer { isImporting = false }
            do {
                let updated = try await Task.detached(priority: .userInitiated) { try ProjectSources.attaching(url: url, to: project) }.value
                guard let index = state.projects.firstIndex(where: { $0.id == project.id }) else { return }
                state.projects[index] = ProjectSources.preservingControls(from: state.projects[index], in: updated)
                if selectedProjectID == project.id { updateAssessment() }
                persist()
            } catch { errorMessage = "关联未完成：\(error.localizedDescription)" }
        }
    }
    func toggleRefreshPause() {
        guard let index = state.projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        state.projects[index].refreshPaused = !(state.projects[index].refreshPaused ?? false)
        persist()
        if !isRefreshPaused { refreshSelected() }
    }
    func setSessionEnabled(id: UUID, enabled: Bool) {
        guard let index = state.projects.firstIndex(where: { $0.id == selectedProjectID }),
              let sourceIndex = state.projects[index].sessionSources?.firstIndex(where: { $0.id == id }) else { return }
        state.projects[index].sessionSources![sourceIndex].isEnabled = enabled
        persist()
        if enabled && !isRefreshPaused { refreshSelected() }
    }
    func openSupervisionSource(_ source: SourceReference) {
        guard let project = selectedProject else { return }
        do { NSWorkspace.shared.open(try ProjectImporter.resolveSource(source, root: project.sourceRoot)) }
        catch { errorMessage = "来源无法打开：\(error.localizedDescription)" }
    }
    func supervisionFeedbackText(targetID: String) -> String {
        guard let project = selectedProject, let plan = project.supervision else { return "" }
        if let saved = state.drafts.first(where: { $0.projectID == project.id && $0.recordID == "supervision:" + targetID }) { return saved.text }
        return SupervisionFeedback.compose(targetID: targetID, plan: plan, assessment: supervisionAssessment, records: project.records)
    }
    func saveSupervisionFeedback(_ text: String, targetID: String) {
        guard let project = selectedProject else { return }
        let key = "supervision:" + targetID
        if let index = state.drafts.firstIndex(where: { $0.projectID == project.id && $0.recordID == key }) {
            state.drafts[index].text = text; state.drafts[index].updatedAt = Date()
        } else { state.drafts.append(FeedbackDraft(projectID: project.id, recordID: key, text: text)) }
        persist()
    }
    func copySupervisionFeedback(_ text: String, targetID: String) {
        saveSupervisionFeedback(text, targetID: targetID)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        if let index = state.drafts.firstIndex(where: { $0.projectID == selectedProjectID && $0.recordID == "supervision:" + targetID }) { state.drafts[index].copiedAt = Date(); persist() }
    }
    private func updateAssessment() {
        let generation = UUID(); assessmentGeneration = generation
        guard let project = selectedProject, let plan = project.supervision else { supervisionAssessment = nil; return }
        supervisionAssessment = nil
        Task {
            let result = await Task.detached(priority: .utility) { SupervisionEvaluator.evaluate(plan: plan, root: project.sourceRoot, records: project.records) }.value
            guard assessmentGeneration == generation, selectedProjectID == project.id else { return }
            supervisionAssessment = result
        }
    }
    func exportProject() {
        guard let project = selectedProject else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "devflow-records.json"; panel.title = "导出本地记录"; panel.message = "包含记录与摘录，请在对外分享前检查内容。"
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(ImportPackage(name: project.name, records: project.records, supervision: project.supervision)).write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func persist() {
        state.selectedProjectID = selectedProjectID
        guard !persistenceBlocked else { errorMessage = "原工作区无法读取，本次操作仅暂存内存，未覆盖原文件。请先恢复工作区文件。"; return }
        do { try storage.save(state) } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }
}
