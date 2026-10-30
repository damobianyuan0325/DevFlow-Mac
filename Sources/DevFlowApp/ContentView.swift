import SwiftUI
import AppKit
import DevFlowCore

private extension Project {
    var isDevelopmentSession: Bool { URL(fileURLWithPath: importPath).pathExtension.lowercased() == "jsonl" }
}

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview, all, requirement, development, test, bug, decision, delivery, feedback
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .all: return "全部记录"
        case .feedback: return "反馈草稿"
        default: return kind?.title ?? "记录"
        }
    }
    var kind: RecordKind? { RecordKind(rawValue: rawValue) }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .all: return "clock.arrow.circlepath"
        case .feedback: return "text.bubble"
        default: return kind?.symbol ?? "doc.text"
        }
    }
}

private enum SessionAttention: String, CaseIterable, Identifiable {
    case failed, missingResult, unverified
    var id: String { rawValue }
    var title: String {
        switch self {
        case .failed: return "明确失败"
        case .missingResult: return "缺少结果"
        case .unverified: return "尚未验证"
        }
    }
    var symbol: String {
        switch self {
        case .failed: return "exclamationmark.circle"
        case .missingResult: return "arrow.turn.down.right"
        case .unverified: return "questionmark.circle"
        }
    }
    var color: Color { self == .failed ? .red : .orange }
    func matches(_ record: ActivityRecord, missingResults: Set<String>) -> Bool {
        switch self {
        case .failed: return record.status == .failed
        case .missingResult: return missingResults.contains(record.id)
        case .unverified: return [.unknown, .needsReview, .notRun].contains(record.status) && !missingResults.contains(record.id)
        }
    }
}

enum DevFlowStyle {
    static let accent = Color(nsColor: NSColor(name: "DevFlowAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.37, green: 0.84, blue: 0.74, alpha: 1)
            : NSColor(red: 0.12, green: 0.43, blue: 0.43, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static func statusColor(_ status: RecordStatus) -> Color {
        switch status {
        case .failed: return .red
        case .blocked, .open, .needsReview: return .orange
        case .passed: return accent
        case .inProgress: return .blue
        default: return .secondary
        }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var section: WorkspaceSection = .overview
    @State private var searchText = ""
    @State private var usesCutoff = false
    @State private var cutoff = Date()
    @State private var feedbackEdits: [String: String] = [:]
    @State private var sessionAttention: SessionAttention?
    @State private var showsSourceManagement = false

    private func missingResultIDs(in project: Project) -> Set<String> {
        let answeredCalls = Set(project.records.filter { $0.action?.kind == .toolResult }.flatMap(\.relatedIDs))
        return Set(project.records.filter {
            $0.action?.kind == .toolCall && !answeredCalls.contains($0.id)
                && !$0.limitations.contains(where: { $0.hasPrefix("来源后来发生变化；此条为先前导入保留的历史版本") })
        }.map(\.id))
    }

    private func attentionCount(in project: Project) -> Int {
        let missing = project.isDevelopmentSession ? missingResultIDs(in: project) : []
        return project.records.filter { $0.status.needsAttention || missing.contains($0.id) }.count
    }

    private func sectionTitle(_ item: WorkspaceSection) -> String {
        if store.selectedProject?.supervision != nil, item == .overview { return "监督工作台" }
        if store.selectedProject?.supervision != nil, item == .feedback { return "介入与反馈" }
        guard store.isSelectedSession else { return item.title }
        if item == .all { return "动作与消息" }
        if item == .overview { return "会话概览" }
        return item.title
    }

    private var cutoffString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: cutoff)
    }

    private func eventDay(_ record: ActivityRecord) -> String? {
        guard let value = record.occurredAt else { return nil }
        let day = String(value.prefix(10))
        return day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil ? nil : day
    }

    private var visibleRecords: [ActivityRecord] {
        guard let project = store.selectedProject else { return [] }
        let draftIDs = Set(store.state.drafts.filter { $0.projectID == project.id }.map(\.recordID))
        let missing = project.isDevelopmentSession ? missingResultIDs(in: project) : []
        return project.records.filter { record in
            if let kind = section.kind, record.kind != kind { return false }
            if section == .feedback && !draftIDs.contains(record.id) { return false }
            if project.isDevelopmentSession, section == .all, let focus = sessionAttention,
               !focus.matches(record, missingResults: missing) { return false }
            if usesCutoff, let day = eventDay(record), day > cutoffString { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || [record.title, record.summary, record.id, record.source.path]
                .contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { lhs, rhs in
            let left = lhs.occurredAt ?? ""
            let right = rhs.occurredAt ?? ""
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    private var datedRecords: [ActivityRecord] { visibleRecords.filter { eventDay($0) != nil } }
    private var undatedRecords: [ActivityRecord] { visibleRecords.filter { eventDay($0) == nil } }

    private var showsSupervision: Bool {
        store.selectedProject?.supervision != nil && (section == .overview || section == .feedback)
    }

    var body: some View {
        workspace
        .navigationSplitViewStyle(.balanced)
        .tint(DevFlowStyle.accent)
        .frame(minWidth: 1060, minHeight: 680)
        .navigationTitle(store.selectedProject?.name ?? "DevFlow")
        .toolbar { workspaceToolbar }
        .sheet(isPresented: $showsSourceManagement) {
            ProjectSourceManagementSheet().environmentObject(store)
        }
        .alert("操作未完成", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "请稍后重试。")
        }
        .onChange(of: store.selectedProjectID) { _, _ in
            searchText = ""
            sessionAttention = nil
            if store.isSelectedSession || store.selectedProject?.supervision != nil {
                section = .overview
                usesCutoff = false
            }
        }
    }

    @ViewBuilder private var workspace: some View {
        if showsSupervision, let project = store.selectedProject, let plan = project.supervision {
            NavigationSplitView {
                sidebar.navigationSplitViewColumnWidth(min: 195, ideal: 220, max: 275)
            } detail: {
                SupervisionView(project: project, plan: plan, startsWithFeedback: section == .feedback) { id in
                    searchText = ""; usesCutoff = false; sessionAttention = nil; section = .all
                    store.selectRecord(id)
                } onBrowseRecords: {
                    section = .all; sessionAttention = nil
                }
                .id(project.id.uuidString + section.rawValue)
            }
        } else {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 195, ideal: 220, max: 275)
        } content: {
            recordColumn
                .navigationSplitViewColumnWidth(min: 305, ideal: 365, max: 500)
        } detail: {
            if let record = store.selectedRecord, let project = store.selectedProject {
                RecordDetailView(
                    record: record,
                    project: project,
                    outsideFilter: !visibleRecords.contains(where: { $0.id == record.id }),
                    feedbackText: feedbackBinding(record, project: project)
                )
                .id(project.id.uuidString + record.id)
            } else {
                detailPlaceholder
            }
        }
        }
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isImporting { ProgressView().controlSize(.small) }
                Button { store.connectDevelopmentSession() } label: {
                    Label("接入开发会话", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(store.isImporting)
                .help("选择一个 Codex JSONL 会话，查看已记录的公开动作")
                .accessibilityIdentifier("connectDevelopmentSession")
                if store.selectedProject != nil {
                    Button { store.attachSessionToSelectedProject() } label: {
                        Label("关联开发会话到此项目", systemImage: "link.badge.plus")
                    }
                    .disabled(store.isImporting || store.selectedProject?.isSample == true)
                    .help("将自行选择的会话归入此项目；只读提取公开记录")
                    .accessibilityIdentifier("attachSessionToProject")
                    Button { store.toggleRefreshPause() } label: {
                        Label(store.isRefreshPaused ? "恢复资料刷新" : "暂停资料刷新", systemImage: store.isRefreshPaused ? "play.circle" : "pause.circle")
                    }
                    .help("只改变 DevFlow 读取资料的频率，不会暂停或恢复 Agent")
                    .accessibilityIdentifier("toggleRefreshPause")
                }
                Button { store.refreshSelected() } label: {
                    Label("刷新记录", systemImage: "arrow.clockwise")
                }
                .disabled(store.selectedProject == nil || store.selectedProject?.isSample == true || store.isImporting)
                .help(store.selectedProject?.isSample == true ? "内置复盘样本是固定的历史资料" : "重新读取项目资料，不运行项目命令")
                .accessibilityIdentifier("refreshProject")
                Button { store.exportProject() } label: {
                    Label("导出记录", systemImage: "square.and.arrow.up")
                }
                .disabled(store.selectedProject == nil)
                .accessibilityIdentifier("exportProject")
                Button { store.attachSourceRoot() } label: {
                    Label("关联原始资料", systemImage: "link")
                }
                .disabled(store.selectedProject == nil || store.isImporting || URL(fileURLWithPath: store.selectedProject?.importPath ?? "").pathExtension.lowercased() != "json")
                .accessibilityIdentifier("attachSourceRoot")
                Button { store.importProject() } label: {
                    Label("导入项目", systemImage: "plus")
                }
                .disabled(store.isImporting)
                .accessibilityIdentifier("importProjectToolbar")
            }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let logo = AppResources.logo {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 38, height: 38)
                        .accessibilityLabel("DevFlow 标志")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DevFlow").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("让每一步有迹可循").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)

            List {
                Section("项目") {
                    if store.state.projects.isEmpty {
                        Text("还没有项目").font(.callout).foregroundStyle(.tertiary)
                    }
                    ForEach(store.state.projects) { project in
                        Button {
                            store.selectProject(project.id)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: project.isDevelopmentSession ? "text.bubble" : (project.isSample ? "book.closed" : "folder"))
                                    .foregroundStyle(store.selectedProjectID == project.id ? DevFlowStyle.accent : .secondary)
                                Text(project.name).lineLimit(1)
                                Spacer(minLength: 0)
                                if store.selectedProjectID == project.id {
                                    Circle().fill(DevFlowStyle.accent).frame(width: 6, height: 6)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("project.\(project.id.uuidString)")
                        .contextMenu {
                            Button("管理项目来源") { store.selectProject(project.id); showsSourceManagement = true }
                            Button("从工作台移除", role: .destructive) { store.removeProject(project.id) }
                        }
                    }
                }
                Section("项目记录") {
                    ForEach(WorkspaceSection.allCases) { item in
                        Button { section = item; sessionAttention = nil } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol).frame(width: 18)
                                Text(sectionTitle(item))
                                Spacer()
                                if let count = sectionCount(item), count > 0 {
                                    Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .foregroundStyle(section == item ? DevFlowStyle.accent : Color.primary)
                            .background(section == item ? DevFlowStyle.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        .accessibilityIdentifier("section.\(item.rawValue)")
                    }
                }
            }
            .listStyle(.sidebar)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Label("本地保存 · 来源只读", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { store.loadSample() } label: {
                    Label("打开复盘样本", systemImage: "book")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DevFlowStyle.accent)
                .disabled(store.isImporting)
                .accessibilityIdentifier("loadSampleSidebar")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private func sectionCount(_ item: WorkspaceSection) -> Int? {
        guard let project = store.selectedProject else { return nil }
        if item == .overview { return nil }
        if item == .feedback { return store.state.drafts.filter { $0.projectID == project.id }.count }
        if let kind = item.kind { return project.records.filter { $0.kind == kind }.count }
        return project.records.count
    }

    private var recordColumn: some View {
        VStack(spacing: 0) {
            if let project = store.selectedProject {
                columnHeader(project)
                Divider()
                if section == .overview {
                    overview(project)
                } else if visibleRecords.isEmpty {
                    ContentUnavailableView {
                        Label(section == .feedback ? "还没有反馈草稿" : "没有匹配的记录", systemImage: section.symbol)
                    } description: {
                        Text(section == .feedback ? "打开一条记录，整理问题并保存反馈。" : "试试其他关键词、栏目或截止日期。")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    recordsList
                }
            } else {
                welcome
            }
        }
        .background(DevFlowStyle.canvas)
    }

    private func columnHeader(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sectionTitle(section)).font(.system(size: 23, weight: .semibold))
                Spacer()
                if project.isSample { SmallBadge(text: "历史样本", color: DevFlowStyle.accent) }
                else if project.isDevelopmentSession { SmallBadge(text: "只读接入", color: DevFlowStyle.accent) }
                Button { showsSourceManagement = true } label: {
                    Label("来源", systemImage: "link")
                }
                .font(.caption)
                .accessibilityIdentifier("manageProjectSources")
            }
            Text(project.isDevelopmentSession ? "\(visibleRecords.count) 条公开记录 · 命令、变更与消息" : (section == .overview ? "从记录走向判断，先看依据。" : "\(visibleRecords.count) 条记录 · 保留来源与未知"))
                .font(.caption).foregroundStyle(.secondary)
            if project.isDevelopmentSession {
                Text(store.isRefreshPaused ? "资料刷新已暂停；Agent 的运行不受影响。可手动刷新读取新记录。" : "覆盖本项目已接入会话记录的公开动作。当前选中且应用前台时，每 15 秒刷新。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sessionTrackingSummary")
                if section == .all, let focus = sessionAttention {
                    HStack {
                        SmallBadge(text: "筛选：\(focus.title)", color: focus.color)
                        Spacer()
                        Button("查看全部动作") { sessionAttention = nil }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(DevFlowStyle.accent)
                            .accessibilityIdentifier("clearSessionAttentionFilter")
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标题、内容或来源", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("recordSearch")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                        .accessibilityLabel("清除搜索")
                }
            }
            .padding(9)
            .background(DevFlowStyle.card, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Toggle("历史截止日期", isOn: $usesCutoff)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityIdentifier("historyCutoffToggle")
                Spacer(minLength: 4)
                if usesCutoff {
                    DatePicker("截止日期", selection: $cutoff, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).controlSize(.small)
                        .accessibilityIdentifier("historyCutoffDate")
                }
            }
            if usesCutoff {
                Text("按事件日期筛选。事后复盘不代表当时已知；日期未知的记录单列。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = store.lastRefreshError {
                Label(error, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(3)
                    .accessibilityIdentifier("refreshError")
            }
        }
        .padding(18)
    }

    private var recordsList: some View {
        List(selection: Binding<String?>(
            get: { store.selectedRecordID },
            set: { if let id = $0 { store.selectRecord(id) } }
        )) {
            if !datedRecords.isEmpty {
                Section(usesCutoff ? "截至 \(cutoffString) 的记录" : "已有日期") {
                    ForEach(datedRecords) { record in
                        RecordRow(record: record, showsEventTime: store.isSelectedSession)
                            .tag(record.id)
                            .accessibilityIdentifier("record.\(record.id)")
                    }
                }
            }
            if !undatedRecords.isEmpty {
                Section {
                    ForEach(undatedRecords) { record in
                        RecordRow(record: record, showsEventTime: store.isSelectedSession)
                            .tag(record.id)
                            .accessibilityIdentifier("record.\(record.id)")
                    }
                } header: {
                    Text(usesCutoff ? "日期未知 · 不纳入历史时点判断" : "日期未知")
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("recordsList")
    }

    private func overview(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    OverviewMetric(title: project.isDevelopmentSession ? "公开过程记录" : "已载入记录", value: "\(project.records.count)", symbol: "tray.full", color: DevFlowStyle.accent)
                    OverviewMetric(title: "需留意记录", value: "\(attentionCount(in: project))", symbol: "flag", color: .orange)
                }
                if project.isDevelopmentSession {
                    sessionAttentionCard(project)
                    SectionCard(title: "本次接入覆盖", symbol: "viewfinder") {
                        Text("展开本项目已接入会话日志中实际记录的公开消息、工具输入与结果、命令和文件变更。")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(store.isRefreshPaused ? "资料刷新已暂停，仍可手动读取；这不会暂停 Agent。" : "只读取当前选中项目的来源；应用前台时每 15 秒读取一次，也可手动刷新。没有新记录不能据此判断 Agent 是否仍在工作。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("批量脚本中未独立记录的步骤不能还原；未接入会话和子代理的内部动作不在本次覆盖内。代理汇报不等于已记录其所有子步骤。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("仅展示过滤后的公开记录，排除内部推理与系统配置。这里不会指挥 Agent 或自动判定任务闭环。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("sessionCoverage")
                }
                SectionCard(title: "如何阅读这些记录", symbol: "info.circle") {
                    Text(project.isSample ? "这是一份历史复盘样本。记录展示当时的文档与后续归纳，不代表项目当前运行状态。" : "这里保留项目的历史与进行中记录。记录为通过、执行凭据和人工验收各有边界。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("导入时间不是事件时间；没有证据的部分保持未知。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("需留意记录包含历史失败与未验证事项，条数不表示当前未解决问题数。")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("最近读取", value: project.refreshedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                let attention = visibleRecords.filter { $0.status.needsAttention }
                if !project.isDevelopmentSession {
                    overviewRecordGroup("失败与未验证记录（含历史）", symbol: "flag", records: Array(attention.prefix(5)), empty: "当前筛选下没有标记为待核查的记录；这不表示项目已经完成验收。")
                }
                overviewRecordGroup(project.isDevelopmentSession ? "最近的动作与消息" : "最近的记录", symbol: "clock", records: Array(datedRecords.prefix(5)), empty: "当前筛选下没有带有效日期的记录。")
                if !undatedRecords.isEmpty {
                    overviewRecordGroup("日期未知", symbol: "calendar.badge.questionmark", records: Array(undatedRecords.prefix(3)), empty: "")
                }
                if !project.warnings.isEmpty {
                    SectionCard(title: "导入时发现的限制", symbol: "exclamationmark.triangle") {
                        ForEach(Array(project.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func sessionAttentionCard(_ project: Project) -> some View {
        let missing = missingResultIDs(in: project)
        let filtered = visibleRecords
        let failures = filtered.filter { $0.status == .failed }
        return SectionCard(title: "需要关注", symbol: "flag") {
            ForEach(SessionAttention.allCases) { focus in
                let count = filtered.filter { focus.matches($0, missingResults: missing) }.count
                Button {
                    sessionAttention = focus
                    section = .all
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: focus.symbol).foregroundStyle(focus.color).frame(width: 18)
                        Text(focus.title).font(.callout)
                        Spacer()
                        Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sessionAttention.\(focus.rawValue)")
            }
            Text("按当前筛选统计。缺少结果只表示尚未找到关联的工具结果，不代表失败或 Agent 卡住。")
                .font(.caption).foregroundStyle(.secondary)
            if !failures.isEmpty {
                Divider()
                Text("最近的明确失败").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(failures.prefix(3))) { failure in
                    Button { store.selectRecord(failure.id) } label: {
                        RecordRow(record: failure, showsEventTime: true)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sessionFailure.\(failure.id)")
                }
            }
            Button("查看全部动作与消息") { sessionAttention = nil; section = .all }
                .font(.caption)
                .accessibilityIdentifier("showAllSessionActions")
            Text("返回了结果不等于检查通过。这里按记录区分待关注项，尚未生成完整阶段总结或整体质量判定；历史失败也不会自动视为当前未解决。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("sessionAttention")
    }

    private func overviewRecordGroup(_ title: String, symbol: String, records: [ActivityRecord], empty: String) -> some View {
        SectionCard(title: title, symbol: symbol) {
            if records.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    Button { store.selectRecord(record.id) } label: {
                        RecordRow(record: record, showsEventTime: store.isSelectedSession)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overview.record.\(record.id)")
                    if record.id != records.last?.id { Divider() }
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 42, weight: .light)).foregroundStyle(DevFlowStyle.accent)
            VStack(alignment: .leading, spacing: 10) {
                Text("从一个项目开始").font(.system(size: 27, weight: .semibold))
                Text("把需求、研发、测试和交付放回同一条脉络。看清已有依据，也看见尚未验证的部分。")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
            }
            VStack(alignment: .leading, spacing: 12) {
                Button { store.connectDevelopmentSession() } label: {
                    Label("接入开发会话", systemImage: "text.bubble").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(store.isImporting)
                .accessibilityIdentifier("connectSessionWelcome")
                Button { store.importProject() } label: {
                    Label("导入项目资料", systemImage: "folder.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(store.isImporting)
                .accessibilityIdentifier("importProjectWelcome")
                Button { store.loadSample() } label: {
                    Label("先看看教学复盘样本", systemImage: "book.closed").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(store.isImporting)
                .accessibilityIdentifier("loadSampleWelcome")
            }
            Text("会话接入：自行选择一个 Codex JSONL 文件，不自动扫描其他聊天。")
                .font(.caption).foregroundStyle(.secondary)
            Text("项目来源保持只读，反馈由你带回原开发聊天。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
    }

    private var detailPlaceholder: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(DevFlowStyle.accent.opacity(0.07)).frame(width: 100, height: 100)
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40, weight: .light)).foregroundStyle(DevFlowStyle.accent)
            }
            Text(store.selectedProject == nil ? "把过程留下，把判断交给你" : "选择一条记录，查看它的依据")
                .font(.title2).fontWeight(.medium)
            Text("需求如何变化，问题怎样发现，检查覆盖了哪里。\n从原文到关联记录，逐步还原项目的真实过程。")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DevFlowStyle.card)
    }

    private func feedbackBinding(_ record: ActivityRecord, project: Project) -> Binding<String> {
        let key = project.id.uuidString + ":" + record.id
        return Binding(
            get: { feedbackEdits[key] ?? store.feedbackText(for: record) },
            set: { feedbackEdits[key] = $0 }
        )
    }
}

private struct RecordRow: View {
    let record: ActivityRecord
    var showsEventTime = false
    private var historyLabel: String? {
        if record.limitations.contains(where: { $0.hasPrefix("来源后来发生变化；此条为先前导入保留的历史版本") }) { return "历史版本" }
        if record.limitations.contains(where: { $0.hasPrefix("最新导入未包含此记录") }) { return "旧记录，待核实" }
        return nil
    }
    private var displayedTime: String {
        guard let timestamp = record.occurredAt else { return "日期未知" }
        guard showsEventTime else { return String(timestamp.prefix(10)) }
        let value = String(timestamp.prefix(19)).replacingOccurrences(of: "T", with: " ")
        if timestamp.hasSuffix("Z") { return value + "Z" }
        if timestamp.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil { return value + String(timestamp.suffix(6)) }
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(record.kind.title, systemImage: record.kind.symbol)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 5)
                Text(displayedTime)
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
            Text(record.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                .foregroundStyle(.primary)
            Text(record.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 7) {
                if let historyLabel {
                    SmallBadge(text: historyLabel, color: .secondary)
                        .accessibilityIdentifier("recordHistoryBadge.\(record.id)")
                }
                SmallBadge(text: record.status.title, color: DevFlowStyle.statusColor(record.status))
                Text(record.origin.title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

@MainActor
private struct RecordDetailView: View {
    @EnvironmentObject var store: AppStore
    let record: ActivityRecord
    let project: Project
    let outsideFilter: Bool
    @Binding var feedbackText: String
    @State private var feedbackNotice: String?

    private var isSessionSource: Bool {
        project.isDevelopmentSession || URL(fileURLWithPath: record.source.path).pathExtension.lowercased() == "jsonl"
    }

    private var relatedRecordIDs: [String] {
        var result = record.relatedIDs
        var seen = Set(result)
        for candidate in project.records where candidate.id != record.id && candidate.relatedIDs.contains(record.id) {
            if seen.insert(candidate.id).inserted { result.append(candidate.id) }
        }
        return result
    }

    private var originExplanation: String {
        if isSessionSource {
            return record.origin == .execution
                ? "来自所选会话的工具调用或结果，DevFlow 没有重新执行。调用被记录不等于执行成功，工具结果也不代表整体任务已验收。"
                : "来自所选会话的用户消息或代理公开汇报；汇报不能证明其所有子步骤已独立记录或验收。"
        }
        switch record.origin {
        case .document: return "以下状态来自文档记载，尚不能据此认定已经独立验证。"
        case .execution: return "这是一份执行凭据。仍需结合版本、环境与检查范围判断，不能据此保证业务正确。"
        case .retrospective: return "这条记录是事后复盘归纳。即使标注了事件日期，也不表示当时已经知道这些结论。"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if outsideFilter {
                    Label("正在查看的关联记录不在当前列表筛选范围内。", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DevFlowStyle.canvas, in: RoundedRectangle(cornerRadius: 9))
                }
                metadata
                SectionCard(title: "记录摘要", symbol: "text.alignleft") {
                    Text(record.summary.isEmpty ? "原记录未提供摘要。" : record.summary)
                        .font(.body).lineSpacing(5).textSelection(.enabled)
                }
                sourceCard
                if !relatedRecordIDs.isEmpty { relatedCard }
                limitationsCard
                feedbackCard
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DevFlowStyle.card)
        .accessibilityIdentifier("recordDetail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(record.kind.title, systemImage: record.kind.symbol)
                    .font(.callout).foregroundStyle(DevFlowStyle.accent)
                Spacer()
                Text(record.id).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
            Text(record.title).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recordDetailTitle")
            HStack(spacing: 8) {
                SmallBadge(text: record.status.title, color: DevFlowStyle.statusColor(record.status))
                SmallBadge(text: record.origin.title, color: .secondary)
            }
            Text(originExplanation).font(.callout).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                metadataItem("原记录时间", value: record.occurredAt ?? "未知，未用导入时间替代")
                metadataItem("适用版本", value: record.version ?? "未记录，适用性待核查")
            }
            GridRow {
                metadataItem("资料导入", value: project.importedAt.formatted(date: .abbreviated, time: .shortened))
                metadataItem("来源级别", value: record.origin.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(DevFlowStyle.canvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metadataItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceCard: some View {
        SectionCard(title: isSessionSource ? "会话公开摘录与本地位置" : "原文与来源", symbol: "doc.text.magnifyingglass") {
            Text(record.source.path + (record.source.line.map { ":\($0)" } ?? ""))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if isSessionSource {
                Label("本地会话 · 仅展示过滤后的公开内容", systemImage: "lock.doc")
                    .font(.caption).foregroundStyle(.secondary)
                Text("原始会话可能还含内部推理或私密配置，因此这里不提供原文件打开入口。输入、结果及变更以以下摘录为准；相关记录可从下方查阅。")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionSourceBoundary")
            } else {
                HStack {
                    Button { store.openSource(record) } label: { Label("打开原文件", systemImage: "arrow.up.forward.square") }
                        .accessibilityIdentifier("openSource")
                    Button { store.revealSource(record) } label: { Label("在 Finder 中显示", systemImage: "folder") }
                        .accessibilityIdentifier("revealSource")
                }
                .controlSize(.small)
            }
            Divider().padding(.vertical, 3)
            if record.source.excerpt.isEmpty {
                Text(isSessionSource ? "这条会话记录没有可展示的公开摘录，不能补推未记录的动作。" : "没有保存原文摘录，可尝试打开来源文件。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(record.source.excerpt)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sourceExcerpt")
            }
            if let digest = record.source.digest {
                Text("来源摘要  \(digest)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .textSelection(.enabled).lineLimit(2)
            }
        }
    }

    private var relatedCard: some View {
        SectionCard(title: "相关上下文", symbol: "link") {
            Text("同时显示本条引用及引用本条的记录。关联提供查阅上下文，不代表实现、修复或验收关系。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(relatedRecordIDs, id: \.self) { id in
                if let related = project.records.first(where: { $0.id == id }) {
                    Button { store.selectRecord(id) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: related.kind.symbol).foregroundStyle(DevFlowStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(related.title).font(.callout)
                                Text("\(related.kind.title) · \(related.status.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("related.\(id)")
                } else {
                    Label("\(id) · 关联记录尚未导入", systemImage: "link.badge.plus")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var limitationsCard: some View {
        SectionCard(title: "未验证与适用限制", symbol: "exclamationmark.bubble") {
            if record.limitations.isEmpty {
                Text("原记录未列出额外限制；这不等于已经验证所有场景。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(record.limitations.enumerated()), id: \.offset) { _, limitation in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5).padding(.top, 6)
                        Text(limitation).font(.callout).lineSpacing(3).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var feedbackCard: some View {
        SectionCard(title: "整理反馈", symbol: "text.bubble") {
            Text("补充你的判断和希望核查的内容，复制后带回原来的 AI 开发聊天。")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $feedbackText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 240)
                .background(DevFlowStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
                .accessibilityLabel("反馈草稿")
                .accessibilityIdentifier("feedbackEditor")
                .onChange(of: feedbackText) { _, _ in feedbackNotice = nil }
            HStack(spacing: 10) {
                Button("保存草稿") {
                    store.saveFeedback(feedbackText, for: record)
                    if store.errorMessage == nil { feedbackNotice = "草稿已保存" }
                }
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("saveFeedback")
                Button {
                    store.copyFeedback(feedbackText, for: record)
                    if store.errorMessage == nil { feedbackNotice = "已复制，请粘贴回原开发聊天" }
                } label: {
                    Label("复制反馈", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("copyFeedback")
                Spacer(minLength: 0)
            }
            if let notice = feedbackNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(DevFlowStyle.accent)
                    .accessibilityIdentifier("feedbackNotice")
            } else {
                Text("保存草稿后，下次可继续编辑。复制不会发送消息或改变问题状态。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DevFlowStyle.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct SmallBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(color.opacity(0.09), in: Capsule())
            .fixedSize()
    }
}

private struct OverviewMetric: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.callout).foregroundStyle(color)
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
    }
}
