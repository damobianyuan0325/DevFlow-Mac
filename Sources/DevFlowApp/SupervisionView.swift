import SwiftUI
import DevFlowCore

private enum SupervisionPage: String, CaseIterable, Identifiable {
    case overview, requirements, verification, issues, intervention, sources
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "项目总览"
        case .requirements: return "需求与任务"
        case .verification: return "测试与验收"
        case .issues: return "问题与交付"
        case .intervention: return "需要我介入"
        case .sources: return "来源"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .requirements: return "list.bullet.rectangle"
        case .verification: return "checkmark.seal"
        case .issues: return "wrench.and.screwdriver"
        case .intervention: return "person.crop.circle.badge.exclamationmark"
        case .sources: return "link"
        }
    }
}

private enum VerificationPage: String, CaseIterable, Identifiable {
    case cases, executions, acceptance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cases: return "测试用例 · T"
        case .executions: return "执行证据 · E"
        case .acceptance: return "需求验收 · A"
        }
    }
}

@MainActor
struct SupervisionView: View {
    @EnvironmentObject var store: AppStore
    let project: Project
    let plan: SupervisionPlan
    let startsWithFeedback: Bool
    let onOpenRecord: (String) -> Void
    let onBrowseRecords: () -> Void
    @State private var page: SupervisionPage = .overview
    @State private var verificationPage: VerificationPage = .cases
    @State private var focusedID: String?
    @State private var feedbackTarget: FeedbackTarget?
    @State private var executionInspection: ExecutionInspectionRequest?

    private struct FeedbackTarget: Identifiable { let id: String }
    private var assessment: SupervisionAssessment? { store.supervisionAssessment }
    private var sources: [SessionSource] { project.sessionSources ?? [] }
    private var drafts: [FeedbackDraft] {
        store.state.drafts.filter { $0.projectID == project.id && $0.recordID.hasPrefix("supervision:") }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var recordDrafts: [FeedbackDraft] {
        store.state.drafts.filter { $0.projectID == project.id && !$0.recordID.hasPrefix("supervision:") }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 5) {
                ForEach(SupervisionPage.allCases) { item in
                    Button { page = item; focusedID = nil } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 12, weight: page == item ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(page == item ? DevFlowStyle.accent : Color.secondary)
                            .background(page == item ? DevFlowStyle.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandButtonStyle(base: PlainButtonStyle()))
                    .accessibilityIdentifier("supervision.page.\(item.rawValue)")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let focusedID {
                        HStack {
                            Label("正在定位 \(focusedID)", systemImage: "scope").font(.callout)
                            Spacer()
                            Button("查看本栏全部") { self.focusedID = nil }
                                .accessibilityIdentifier("supervision.clearFocus")
                        }
                        .padding(12).background(DevFlowStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                    switch page {
                    case .overview: overview
                    case .requirements: requirements
                    case .verification: verification
                    case .issues: issuesAndDelivery
                    case .intervention: interventions
                    case .sources: sourceStatus
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 30).padding(.top, 4)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(page.rawValue + (focusedID ?? ""))
        }
        .background(DevFlowStyle.canvas)
        .accessibilityIdentifier("supervisionWorkspace")
        .onAppear { if startsWithFeedback { page = .intervention } }
        .sheet(item: $executionInspection) { request in ExecutionInspectionSheet(request: request) }
        .sheet(item: $feedbackTarget) { target in
            SupervisionFeedbackSheet(targetID: target.id, initialText: store.supervisionFeedbackText(targetID: target.id))
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("监督工作台").font(.system(size: 26, weight: .semibold))
                    Text(plan.title.isEmpty ? project.name : plan.title).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                SmallBadge(text: "计划版本 \(known(plan.version))", color: DevFlowStyle.accent)
                Button(action: onBrowseRecords) {
                    Label("回查动作与历史", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("supervision.browseRecords")
            }
            HStack(spacing: 8) {
                Circle().fill(store.isRefreshPaused ? Color.orange : DevFlowStyle.accent).frame(width: 6, height: 6)
                Text(store.isRefreshPaused ? "资料刷新已暂停 · Agent 的运行不受影响" : "每 15 秒后台读取 · 保持当前页面和编辑")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(store.isAssessing ? "后台核验中 · 暂保留上次结果" : " ")
                    .font(.caption).foregroundStyle(.secondary)
                Text("上次读取 \(project.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.lastRefreshError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("supervision.refreshError")
            }
        }
        .padding(.horizontal, 26).padding(.top, 23).padding(.bottom, 18)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "这次要做到什么", symbol: "quote.opening") {
                Text(known(plan.originalRequest)).font(.system(size: 17, weight: .medium)).lineSpacing(6).textSelection(.enabled)
                Text("以下拆解由开发过程记录提供；有用例、有执行、满足验收是三件不同的事。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("查看需求拆解与假设") { page = .requirements }
                    .accessibilityIdentifier("supervision.showRequirements")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryTile("需求", value: "\(plan.requirements.count)", detail: "按原话拆解，保留假设", symbol: "text.alignleft", destination: .requirements)
                summaryTile("任务记录", value: "\(plan.tasks.count)", detail: "\(plan.tasks.filter { $0.status == .inProgress }.count) 项记录为进行中", symbol: "hammer", destination: .requirements)
                summaryTile("待介入事项", value: assessment.map { "\($0.interventions.count)" } ?? "待评估", detail: "查看缺口与可带回的反馈", symbol: "flag", destination: .intervention)
            }
            SectionCard(title: "当前证据简报", symbol: "text.badge.checkmark") {
                if let assessment {
                    textLines(assessment.briefing, empty: "暂未形成阶段结论；请逐项查看需求、任务与证据。")
                    if !assessment.validationErrors.isEmpty {
                        Label("计划关联存在待核查项", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        textLines(assessment.validationErrors, empty: "")
                    }
                } else {
                    Text("正在读取证据，尚不能给出阶段结论。").foregroundStyle(.secondary)
                }
                Text("结论仅针对已导入的计划、来源与证据。任务的完成声明、工具返回和文档中的通过字样不能单独证明需求完成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let assessment, !assessment.interventions.isEmpty {
                SectionCard(title: "优先查看", symbol: "flag") {
                    ForEach(Array(assessment.interventions.prefix(3))) { item in interventionRow(item) }
                    Button("查看全部需要我介入的事项") { page = .intervention }
                        .accessibilityIdentifier("supervision.showInterventions")
                }
            }
            SectionCard(title: "过程与来源", symbol: "point.3.connected.trianglepath.dotted") {
                Text("当前主来源 \(project.primaryRecords?.count.description ?? "未知") 条；累计过程与历史 \(project.records.count) 条（含已保留的旧记录），关联 \(sources.count) 个开发会话。历史中的状态不代表现状；需求完成请看当前验收，记录数量不表示完成度。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("查看来源与覆盖范围") { page = .sources }
                    Button("回查原始动作与历史", action: onBrowseRecords)
                }
                Text("你可以整理反馈并带回原来的 AI 开发聊天。DevFlow 不会代你发送，也不会控制 Agent。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageIntro("原话 → 拆解 → 验收 → 任务", detail: "R 是需求，A 是可观察的验收标准，U 是工作任务。展开可查看依据与关联；任务状态是来源声明。")
            if focusedID == nil {
                SectionCard(title: "共同范围与假设", symbol: "scope") {
                    labeledLines("范围", plan.scope, empty: "未记录范围")
                    labeledLines("假设", plan.assumptions, empty: "未记录假设；不能据此认为不存在假设")
                }
            }
            if plan.requirements.isEmpty { emptyCard("尚未接入需求拆解", detail: "保留用户原话后，由开发过程补充需求与验收标准。") }
            PagedItems(items: plan.requirements.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { requirement in
                requirementCard(requirement)
            }
            if focusedID == nil || plan.tasks.contains(where: { $0.id == focusedID }) {
                SectionCard(title: "工作任务 · U", symbol: "hammer") {
                    if plan.tasks.isEmpty { Text("尚未记录工作任务。").foregroundStyle(.secondary) }
                    PagedItems(items: plan.tasks.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { task in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("\(task.id) · \(task.title)").font(.callout.weight(.medium))
                                Spacer()
                                SmallBadge(text: taskStatus(task.status), color: task.status == .blocked ? .orange : .secondary)
                            }
                            entityLinks("对应验收", ids: task.criterionIDs)
                            recordLinks(task.recordIDs)
                            feedbackButton(task.id)
                        }
                        .padding(.vertical, 7)
                        .accessibilityIdentifier("supervision.task.\(task.id)")
                        if task.id != plan.tasks.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func requirementCard(_ item: SupervisionRequirement) -> some View {
        let result = assessment?.requirements.first { $0.id == item.id }
        let criteria = plan.criteria.filter { $0.requirementID == item.id }
        return SectionCard(title: "\(item.id) · \(item.title)", symbol: "text.alignleft") {
            assessmentSummary(result)
            Text(item.originalText.isEmpty ? "原话未知，待补来源" : "“\(item.originalText)”")
                .font(.callout).lineSpacing(4).textSelection(.enabled)
            Text(known(item.details)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                SmallBadge(text: "\(criteria.count) 项验收标准", color: .secondary)
                Spacer()
                feedbackButton(item.id)
            }
            DeferredDisclosure("拆解、假设与证据链") {
                VStack(alignment: .leading, spacing: 12) {
                    labeledLines("假设", item.assumptions, empty: "未记录，待核查")
                    labeledLines("范围", item.scope, empty: "未记录")
                    labeledLines("本次不含", item.outOfScope, empty: "未声明额外排除范围")
                    recordLinks(item.recordIDs)
                    if criteria.isEmpty { Text("尚无验收标准关联，不能判断需求已经完成。").font(.caption).foregroundStyle(.orange) }
                    ForEach(criteria) { criterion in
                        Divider()
                        Button { navigate(to: criterion.id) } label: {
                            HStack {
                                Text("\(criterion.id) · \(criterion.title)")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(HandButtonStyle(base: PlainButtonStyle())).foregroundStyle(DevFlowStyle.accent)
                        .accessibilityIdentifier("supervision.link.\(item.id).\(criterion.id)")
                        Text(criterion.expected).font(.caption).foregroundStyle(.secondary)
                        let tasks = plan.tasks.filter { $0.criterionIDs.contains(criterion.id) }
                        let tests = plan.testCases.filter { $0.criterionIDs.contains(criterion.id) }
                        entityLinks("任务 U", ids: tasks.map(\.id))
                        entityLinks("用例 T", ids: tests.map(\.id))
                        entityLinks("证据 E", ids: plan.executions.filter { execution in tests.contains { $0.id == execution.testCaseID } }.map(\.id))
                    }
                }.padding(.top, 10)
            }
            .accessibilityIdentifier("supervision.requirementDetails.\(item.id)")
        }
        .accessibilityIdentifier("supervision.requirement.\(item.id)")
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageIntro("用例、执行、验收分开看", detail: "用例定义怎么查；执行记录实际发生了什么；验收还需匹配要求、源码与证据层级。未知字段不会被补成通过。")
            Picker("验证层次", selection: $verificationPage) {
                ForEach(VerificationPage.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .handCursor()
            .accessibilityIdentifier("supervision.verificationLayers")
            .onChange(of: verificationPage) { _, _ in
                if let focusedID, !belongsToVerificationPage(focusedID) { self.focusedID = nil }
            }
            switch verificationPage {
            case .cases:
                if plan.testCases.isEmpty { emptyCard("尚无测试用例", detail: "不能从工具日志的数量推断测试覆盖。") }
                PagedItems(items: plan.testCases.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { test in testCaseCard(test) }
            case .executions:
                if plan.executions.isEmpty { emptyCard("尚无执行证据", detail: "有测试代码或计划，不代表已经运行。") }
                PagedItems(items: plan.executions.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { execution in executionCard(execution) }
            case .acceptance:
                if plan.criteria.isEmpty { emptyCard("尚无验收标准", detail: "需要可观察的预期结果及所需验证层级。") }
                PagedItems(items: plan.criteria.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { criterion in criterionCard(criterion) }
            }
        }
    }

    private func testCaseCard(_ item: SupervisionTestCase) -> some View {
        SectionCard(title: "\(item.id) · \(item.title)", symbol: "list.bullet.clipboard") {
            HStack {
                SmallBadge(text: item.level.title, color: .secondary)
                if !plan.executions.contains(where: { $0.testCaseID == item.id }) {
                    SmallBadge(text: "尚无执行证据 · 未运行或未接入", color: .orange)
                        .accessibilityIdentifier("supervision.testNotRun.\(item.id)")
                }
                Text("最低通过数 \(item.minimumPassed)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                feedbackButton(item.id)
            }
            field("输入与前提", item.input)
            field("预期结果", item.expected)
            entityLinks("对应验收 A", ids: item.criterionIDs)
            entityLinks("对应任务 U", ids: item.taskIDs)
            sourcePaths(item.sourcePaths)
            entityLinks("执行证据 E", ids: plan.executions.filter { $0.testCaseID == item.id }.map(\.id))
        }
        .accessibilityIdentifier("supervision.testCase.\(item.id)")
    }

    private func executionCard(_ item: VerificationExecution) -> some View {
        let result = assessment?.executions.first { $0.id == item.id }
        return SectionCard(title: "\(item.id) · 执行证据", symbol: "terminal") {
            HStack {
                stateBadge(result?.state)
                SmallBadge(text: "记录结果：\(verificationResult(item.result))", color: .secondary)
                SmallBadge(text: item.level.title, color: .secondary)
                Spacer()
                Button("单独核验") {
                    executionInspection = ExecutionInspectionRequest(plan: plan, root: project.sourceRoot, records: project.records, executionID: item.id)
                }
                .help("使用独立读取预算核验这次执行；不改变项目验收或问题闭环结论")
                .accessibilityIdentifier("supervision.inspectExecution.\(item.id)")
                feedbackButton(item.id)
            }
            textLines(result?.reasons ?? [], empty: "尚未完成证据适用性核查")
            entityLinks("测试用例 T", ids: [item.testCaseID])
            HStack(alignment: .top, spacing: 24) {
                field("执行时间", item.occurredAt)
                field("执行环境", item.environment)
            }
            HStack(alignment: .top, spacing: 24) {
                field("开始时间", item.startedAt)
                field("结束时间", item.finishedAt)
                field("退出码", item.exitCode.map(String.init))
            }
            HStack(alignment: .top, spacing: 24) {
                field("被验收候选版本", item.candidateVersion)
                field("提交标识", item.commit, monospaced: true)
            }
            Label(item.contractDigest?.isEmpty == false ? "已记录验收约束绑定，适用性以上方核查为准" : "未绑定验收约束，不能证明符合当前预期", systemImage: item.contractDigest?.isEmpty == false ? "link" : "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
            field("实际命令 / 操作", item.command, monospaced: true)
            HStack(spacing: 18) {
                countField("总计", item.counts?.total)
                countField("通过", item.counts?.passed)
                countField("失败", item.counts?.failed)
                countField("跳过", item.counts?.skipped)
            }
            Text("计数按来源记录展示；未知不视为 0，通过条数不等于需求验收。").font(.caption).foregroundStyle(.secondary)
            DeferredDisclosure("源码版本与原始证据") {
                VStack(alignment: .leading, spacing: 12) {
                    field("验收约束摘要", item.contractDigest, monospaced: true)
                    if item.sourceFiles.isEmpty { Text("未绑定源码指纹，不能确认该执行适用于当前代码。").font(.caption).foregroundStyle(.orange) }
                    PagedItems(items: Array(item.sourceFiles.enumerated()), id: \.offset, pageSize: 20) { _, file in
                        field(file.path, "SHA256  \(known(file.sha256))", monospaced: true)
                    }
                    if let log = item.log { sourceReference(log) }
                    else { Text("原始日志未知 / 未关联。").font(.caption).foregroundStyle(.orange) }
                    recordLinks(item.recordIDs)
                }.padding(.top, 10)
            }
            .accessibilityIdentifier("supervision.executionDetails.\(item.id)")
        }
        .accessibilityIdentifier("supervision.execution.\(item.id)")
    }

    private func criterionCard(_ item: AcceptanceCriterion) -> some View {
        let result = assessment?.criteria.first { $0.id == item.id }
        return SectionCard(title: "\(item.id) · \(item.title)", symbol: "checkmark.seal") {
            assessmentSummary(result)
            field("可观察的验收结果", item.expected)
            HStack {
                SmallBadge(text: "要求：\(item.requiredLevel.title)", color: .secondary)
                Spacer()
                feedbackButton(item.id)
            }
            entityLinks("需求 R", ids: [item.requirementID])
            entityLinks("测试用例 T", ids: plan.testCases.filter { $0.criterionIDs.contains(item.id) }.map(\.id))
            entityLinks("纳入判断的证据 E", ids: result?.evidenceIDs ?? [])
            sourcePaths(item.sourcePaths)
        }
        .accessibilityIdentifier("supervision.criterion.\(item.id)")
    }

    private var issuesAndDelivery: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageIntro("修复声明与有效复验分开", detail: "历史失败持续保留。是否闭环取决于关联复验及其适用性；交付物也需对应来源、指纹和验证记录。")
            if plan.issues.isEmpty && focusedID == nil { emptyCard("尚未接入问题记录", detail: "未记录问题，不表示所有场景都已验证。") }
            PagedItems(items: plan.issues.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { issue in issueCard(issue) }
            if focusedID == nil || plan.artifacts.contains(where: { $0.id == focusedID }) {
                Text("交付物").font(.title3.weight(.semibold)).padding(.top, 4)
                if plan.artifacts.isEmpty { emptyCard("尚无交付物关联", detail: "源码版本与最终运行的 App 或压缩包仍需分别核对。") }
                PagedItems(items: plan.artifacts.filter { focusedID == nil || $0.id == focusedID }, id: \.id) { item in
                    SectionCard(title: "\(item.id) · \(item.title)", symbol: "shippingbox") {
                        assessmentSummary(assessment?.artifacts.first { $0.id == item.id })
                        field("本地产物位置", item.path, monospaced: true)
                        field("SHA256", item.sha256, monospaced: true)
                        entityLinks("交付验证 E", ids: item.executionIDs)
                        recordLinks(item.recordIDs)
                        feedbackButton(item.id)
                    }
                    .accessibilityIdentifier("supervision.artifact.\(item.id)")
                }
            }
        }
    }

    private func issueCard(_ item: SupervisionIssue) -> some View {
        let result = assessment?.issues.first { $0.id == item.id }
        return SectionCard(title: "\(item.id) · \(item.title)", symbol: "ladybug") {
            HStack {
                SmallBadge(text: item.declaredClosed ? "来源声明已关闭" : "来源未声明关闭", color: .secondary)
                SmallBadge(text: closureTitle(result?.state), color: result?.state == .closed ? DevFlowStyle.accent : .orange)
                if item.blocking { SmallBadge(text: "记录为阻塞项", color: .orange) }
                Spacer()
                feedbackButton(item.id)
            }
            textLines(result?.reasons ?? [], empty: "复验闭环尚未核查")
            field("问题根因", item.rootCause)
            field("为什么此前没有查到", item.missedCheckCause)
            entityLinks("受影响验收 A", ids: item.criterionIDs)
            entityLinks("关联测试 T", ids: item.testCaseIDs)
            VStack(alignment: .leading, spacing: 8) {
                Text("修复记录").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                recordLinks(item.fixRecordIDs)
            }
            entityLinks("声明的复验 E", ids: item.verificationExecutionIDs)
            entityLinks("有效复验 E", ids: result?.effectiveRetestIDs ?? [])
        }
        .accessibilityIdentifier("supervision.issue.\(item.id)")
    }

    private var interventions: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageIntro("把疑点变成可执行的反馈", detail: "选择事项后生成可编辑草稿，复制并由你带回原来的 AI 开发聊天。保存或复制不会发送消息、停止 Agent 或关闭问题。")
            SectionCard(title: "待核查与待补证据", symbol: "flag") {
                if let assessment {
                    if assessment.interventions.isEmpty { Text("当前规则未列出待介入项；这不表示已覆盖全部业务场景。").foregroundStyle(.secondary) }
                    PagedItems(items: assessment.interventions, id: \.id) { item in interventionRow(item) }
                } else { Text("正在读取证据，待介入事项尚未形成。").foregroundStyle(.secondary) }
            }
            SectionCard(title: "已保存的反馈草稿", symbol: "text.bubble") {
                if drafts.isEmpty { Text("尚无监督反馈草稿。需求、测试、问题和缺证事项旁都可以整理反馈。").font(.callout).foregroundStyle(.secondary) }
                ForEach(drafts) { draft in
                    let targetID = String(draft.recordID.dropFirst("supervision:".count))
                    Button { feedbackTarget = FeedbackTarget(id: targetID) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(targetTitle(targetID)).font(.callout.weight(.medium))
                                Text(draft.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("保存于 \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))" + (draft.copiedAt == nil ? "" : " · 曾复制，送达未知"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(DevFlowStyle.accent)
                        }.padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(HandButtonStyle(base: PlainButtonStyle()))
                    .accessibilityIdentifier("supervision.draft.\(targetID)")
                }
            }
            if !recordDrafts.isEmpty {
                SectionCard(title: "记录反馈草稿", symbol: "doc.text") {
                    Text("之前从动作或历史记录整理的反馈仍保留，可回到对应记录继续编辑。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(recordDrafts) { draft in recordLinks([draft.recordID]) }
                }
            }
        }
    }

    private func interventionRow(_ item: SupervisionIntervention) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.callout.weight(.medium))
                Text(item.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("查看依据 · \(item.targetID)") { navigate(to: item.targetID) }
                    .buttonStyle(HandButtonStyle(base: PlainButtonStyle())).foregroundStyle(DevFlowStyle.accent)
                    .accessibilityIdentifier("supervision.interventionEvidence.\(item.id)")
            }
            Spacer(minLength: 4)
            feedbackButton(item.targetID)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("supervision.intervention.\(item.id)")
    }

    private var sourceStatus: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageIntro("明确接入，明确边界", detail: "只读取你选择的项目资料与会话文件。多个会话可归入同一个项目；无法据此获知未接入的 Agent 内部动作。")
            SectionCard(title: "项目资料", symbol: "folder") {
                field("导入位置", project.importPath, monospaced: true)
                field("原始资料根目录", project.sourceRoot, monospaced: true)
                field("计划版本", plan.version)
                Text("计划里的版本标签与执行时源码指纹分别展示；标签相同不能替代指纹核对。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { store.refreshSelected() } label: { Label("立即读取资料", systemImage: "arrow.clockwise") }
                        .disabled(store.isImporting || project.isSample)
                        .accessibilityIdentifier("supervision.refreshSources")
                    Button(store.isRefreshPaused ? "恢复资料刷新" : "暂停资料刷新") { store.toggleRefreshPause() }
                        .accessibilityIdentifier("supervision.toggleRefreshPause")
                }
                Text(store.isRefreshPaused ? "已暂停自动读取。仍可手动刷新；Agent 没有被暂停。" : "仅当前选中项目且应用前台时每 15 秒刷新；没有新记录不能证明 Agent 停止工作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SectionCard(title: "关联的开发会话", symbol: "point.3.connected.trianglepath.dotted") {
                if sources.isEmpty { Text("尚未关联额外会话。选择实际开发聊天对应的 JSONL 后，可将其公开过程归入本项目。").font(.callout).foregroundStyle(.secondary) }
                ForEach(sources) { source in sessionSourceRow(source) }
                Button { store.attachSessionToSelectedProject() } label: { Label("关联开发会话到此项目", systemImage: "plus") }
                    .disabled(store.isImporting || project.isSample)
                    .accessibilityIdentifier("supervision.attachSession")
            }
            SectionCard(title: "本次能看到什么", symbol: "viewfinder") {
                textLines([
                    "读取已接入会话实际记录的公开消息、工具输入与结果、命令及文件变更。",
                    "批量脚本里未独立记录的步骤不能还原；未接入的子代理内部动作、其他聊天和日志外动作不在覆盖范围。",
                    "排除内部推理与系统配置。原始会话可能包含私密内容，因此只展示过滤后的摘录与本地位置，不提供原始 JSONL 打开入口。",
                    "来源只读；反馈由你手动带回开发聊天。暂停资料刷新不会暂停 Agent。"
                ], empty: "")
            }
            if !project.warnings.isEmpty {
                SectionCard(title: "导入限制", symbol: "exclamationmark.triangle") { textLines(project.warnings, empty: "") }
            }
            if let history = project.supervisionHistory, !history.isEmpty {
                SectionCard(title: "先前导入的需求快照", symbol: "clock.arrow.circlepath") {
                    Text("以下保留先前计划中的原话与拆解。导入次序不是需求变更发生时间；当前证据简报只评估现行计划。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(history.enumerated().reversed()), id: \.offset) { index, snapshot in
                        DeferredDisclosure("第 \(index + 1) 份留存 · \(known(snapshot.version)) · \(snapshot.title)") {
                            VStack(alignment: .leading, spacing: 12) {
                                field("当时记录的原话", snapshot.originalRequest)
                                labeledLines("假设", snapshot.assumptions, empty: "未记录")
                                labeledLines("范围", snapshot.scope, empty: "未记录")
                                ForEach(snapshot.requirements) { requirement in
                                    Divider()
                                    Text("\(requirement.id) · \(requirement.title)").font(.callout.weight(.medium))
                                    field("原话", requirement.originalText)
                                    field("拆解", requirement.details)
                                    labeledLines("假设", requirement.assumptions, empty: "未记录")
                                }
                            }.padding(.top, 10)
                        }
                        .accessibilityIdentifier("supervision.requirementSnapshot.\(index)")
                    }
                }
            }
        }
    }

    private func sessionSourceRow(_ source: SessionSource) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(source.name).font(.callout.weight(.medium))
                Spacer()
                Toggle("读取此会话", isOn: Binding(get: { source.isEnabled }, set: { store.setSessionEnabled(id: source.id, enabled: $0) }))
                    .handCursor()
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(store.isImporting)
                    .accessibilityIdentifier("supervision.sessionEnabled.\(source.id.uuidString)")
            }
            Text(source.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text("\(source.records.count) 条已保存记录 · 最近读取：\(source.refreshedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未知")")
                .font(.caption).foregroundStyle(.secondary)
            if let error = source.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if !source.isEnabled { Text("已停用此来源的后续读取，历史记录仍保留；Agent 的运行不受影响。").font(.caption).foregroundStyle(.secondary) }
            textLines(source.warnings, empty: "")
            Divider()
        }
        .padding(.vertical, 5)
        .accessibilityIdentifier("supervision.sessionSource.\(source.id.uuidString)")
    }

    // These links open existing records, never synthesize execution or acceptance evidence.
    @ViewBuilder private func recordLinks(_ ids: [String]) -> some View {
        if ids.isEmpty {
            Text("关联原文未知 / 尚未接入").font(.caption).foregroundStyle(.secondary)
        } else {
            PagedItems(items: ids, id: \.self, pageSize: 20) { id in
                if let record = project.records.first(where: { $0.id == id }) {
                    Button { onOpenRecord(id) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(id) · \(record.title)").font(.caption)
                                Text(record.source.path + (record.source.line.map { ":\($0)" } ?? "") + " · " + record.origin.title)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(HandButtonStyle(base: PlainButtonStyle())).foregroundStyle(DevFlowStyle.accent)
                    .accessibilityIdentifier("supervision.record.\(id)")
                } else {
                    Text("\(id) · 关联记录尚未导入").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func entityLinks(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if ids.isEmpty { Text("尚无关联 / 未知").font(.caption).foregroundStyle(.secondary) }
            else {
                PagedItems(items: ids, id: \.self, pageSize: 20) { id in
                    Button { navigate(to: id) } label: {
                        Label(targetTitle(id), systemImage: "arrow.up.right").font(.caption)
                    }
                    .buttonStyle(HandButtonStyle(base: PlainButtonStyle())).foregroundStyle(DevFlowStyle.accent)
                    .accessibilityIdentifier("supervision.entity.\(id)")
                }
            }
        }
    }

    private func sourcePaths(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("相关源码 / 资料路径").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if paths.isEmpty { Text("未记录，适用范围待核查").font(.caption).foregroundStyle(.secondary) }
            PagedItems(items: paths, id: \.self, pageSize: 20) { path in
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func sourceReference(_ source: SourceReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            field("原始日志位置", source.path + (source.line.map { ":\($0)" } ?? ""), monospaced: true)
            field("日志 SHA256", source.digest, monospaced: true)
            if URL(fileURLWithPath: source.path).pathExtension.lowercased() != "jsonl" {
                Button("查看原始日志") { store.openSupervisionSource(source) }
                    .accessibilityIdentifier("supervision.openLog")
            } else {
                Text("会话来源仅展示过滤后的公开摘录，不直接打开原始 JSONL。").font(.caption).foregroundStyle(.secondary)
            }
            Text(source.excerpt.isEmpty ? "未保存日志摘录，请核查来源及其摘要。" : source.excerpt)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).lineSpacing(3)
        }
    }

    private func feedbackButton(_ id: String) -> some View {
        Button { feedbackTarget = FeedbackTarget(id: id) } label: {
            Label("整理反馈", systemImage: "text.bubble").font(.caption)
        }
        .accessibilityIdentifier("supervision.feedback.\(id)")
    }

    private func assessmentSummary(_ result: SupervisionItemAssessment?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            stateBadge(result?.state)
            textLines(result?.reasons ?? [], empty: result == nil ? "尚未完成证据核查" : "未记录补充说明")
        }
    }

    private func stateBadge(_ state: SupervisionState?) -> some View {
        let color: Color = state == .satisfied ? DevFlowStyle.accent : (state == .failed ? .red : .orange)
        return SmallBadge(text: state?.title ?? "尚未核查", color: color)
    }

    private func summaryTile(_ title: String, value: String, detail: String, symbol: String, destination: SupervisionPage) -> some View {
        Button { page = destination; focusedID = nil } label: {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(17)
            .background(DevFlowStyle.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.07)))
        }.buttonStyle(HandButtonStyle(base: PlainButtonStyle()))
    }

    private func pageIntro(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(.bottom, 3)
    }

    private func emptyCard(_ title: String, detail: String) -> some View {
        SectionCard(title: title, symbol: "questionmark.circle") { Text(detail).font(.callout).foregroundStyle(.secondary) }
    }

    private func field(_ label: String, _ value: String?, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(known(value)).font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countField(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "未知").font(.callout.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledLines(_ title: String, _ lines: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            textLines(lines, empty: empty)
        }
    }

    @ViewBuilder private func textLines(_ lines: [String], empty: String) -> some View {
        if lines.isEmpty {
            if !empty.isEmpty { Text(empty).font(.callout).foregroundStyle(.secondary) }
        } else {
            PagedItems(items: Array(lines.enumerated()), id: \.offset, pageSize: 20) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 7)
                    Text(line).font(.callout).foregroundStyle(.secondary).lineSpacing(3).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func known(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "未知 / 未记录" }
        return value
    }

    private func taskStatus(_ status: DevelopmentTaskStatus) -> String {
        switch status {
        case .planned: return "记录为待开始"
        case .inProgress: return "记录为进行中"
        case .completed: return "记录为已完成"
        case .blocked: return "记录为受阻"
        }
    }

    private func verificationResult(_ result: VerificationResult) -> String {
        switch result {
        case .passed: return "通过"
        case .failed: return "失败"
        case .unknown: return "未知"
        case .notRun: return "未运行"
        case .blocked: return "受阻"
        }
    }

    private func closureTitle(_ state: IssueClosureState?) -> String {
        switch state {
        case .closed: return "复验证据支持关闭"
        case .open: return "尚未闭环"
        default: return "关闭状态未证实"
        }
    }

    private func targetTitle(_ id: String) -> String {
        var title = plan.requirements.first { $0.id == id }?.title
        if title == nil { title = plan.criteria.first { $0.id == id }?.title }
        if title == nil { title = plan.tasks.first { $0.id == id }?.title }
        if title == nil { title = plan.testCases.first { $0.id == id }?.title }
        if title == nil { title = plan.issues.first { $0.id == id }?.title }
        if title == nil { title = plan.artifacts.first { $0.id == id }?.title }
        if let title { return "\(id) · \(title)" }
        if let execution = plan.executions.first(where: { $0.id == id }) { return "\(id) · 执行 \(execution.testCaseID)" }
        return id
    }

    private func belongsToVerificationPage(_ id: String) -> Bool {
        switch verificationPage {
        case .cases: return plan.testCases.contains { $0.id == id }
        case .executions: return plan.executions.contains { $0.id == id }
        case .acceptance: return plan.criteria.contains { $0.id == id }
        }
    }

    private func navigate(to id: String) {
        if plan.requirements.contains(where: { $0.id == id }) || plan.tasks.contains(where: { $0.id == id }) { page = .requirements }
        else if plan.testCases.contains(where: { $0.id == id }) { page = .verification; verificationPage = .cases }
        else if plan.executions.contains(where: { $0.id == id }) { page = .verification; verificationPage = .executions }
        else if plan.criteria.contains(where: { $0.id == id }) { page = .verification; verificationPage = .acceptance }
        else if plan.issues.contains(where: { $0.id == id }) || plan.artifacts.contains(where: { $0.id == id }) { page = .issues }
        else if project.records.contains(where: { $0.id == id }) { onOpenRecord(id); return }
        else { feedbackTarget = FeedbackTarget(id: id); return }
        focusedID = id
    }
}

@MainActor
private struct SupervisionFeedbackSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let targetID: String
    @State private var text: String
    @State private var notice: String?
    init(targetID: String, initialText: String) {
        self.targetID = targetID
        _text = State(initialValue: initialText)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("整理反馈 · \(targetID)").font(.title2.weight(.semibold))
                Spacer()
                Button("保存并关闭") {
                    store.saveSupervisionFeedback(text, targetID: targetID)
                    if store.errorMessage == nil { dismiss() }
                    else { notice = store.errorMessage }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("supervision.closeFeedback")
            }
            Text("检查并补充以下内容，复制后由你带回原来的 AI 开发聊天。").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 13))
                .padding(8).background(DevFlowStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityIdentifier("supervision.feedbackEditor")
                .onChange(of: text) { _, _ in notice = nil }
            HStack {
                Button("保存草稿") {
                    store.saveSupervisionFeedback(text, targetID: targetID)
                    notice = store.errorMessage == nil ? "草稿已保存。" : store.errorMessage
                }
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("supervision.saveFeedback")
                Button {
                    store.copySupervisionFeedback(text, targetID: targetID)
                    notice = store.errorMessage == nil ? "已复制，请粘贴回原开发聊天。" : store.errorMessage
                } label: { Label("复制反馈", systemImage: "doc.on.doc") }
                .buttonStyle(HandButtonStyle(base: BorderedProminentButtonStyle()))
                .accessibilityIdentifier("supervision.copyFeedback")
                Spacer()
            }
            Text(notice ?? "保存和复制都不会发送消息、暂停 Agent 或改变问题状态。")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("supervision.feedbackNotice")
        }
        .padding(24).frame(width: 700, height: 590)
        .interactiveDismissDisabled()
    }
}

/// Available to ordinary imported projects as well as projects with a supervision plan.
@MainActor
struct ProjectSourceManagementSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("管理项目来源").font(.title2.weight(.semibold))
                    Text(store.selectedProject?.name ?? "未选择项目").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sourceManager.close")
            }
            ScrollView {
                if let project = store.selectedProject {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionCard(title: "主来源", symbol: "folder") {
                            Text(project.importPath).font(.caption.monospaced()).textSelection(.enabled)
                            Text("最近读取：\(project.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let error = store.lastRefreshError {
                                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                            HStack {
                                Button { store.refreshSelected() } label: { Label("立即读取资料", systemImage: "arrow.clockwise") }
                                    .disabled(store.isImporting || project.isSample)
                                    .accessibilityIdentifier("sourceManager.refresh")
                                Button(store.isRefreshPaused ? "恢复资料刷新" : "暂停资料刷新") { store.toggleRefreshPause() }
                                    .disabled(project.isSample)
                                    .accessibilityIdentifier("sourceManager.pause")
                            }
                            Text(project.isSample ? "内置样本是固定的历史资料。" : (store.isRefreshPaused ? "自动资料刷新已暂停，仍可手动读取。Agent 的运行不受影响。" : "仅当前选中项目且应用前台时，每 15 秒读取一次资料。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        SectionCard(title: "关联的开发会话", symbol: "point.3.connected.trianglepath.dotted") {
                            if (project.sessionSources ?? []).isEmpty {
                                Text("尚未关联额外会话。可以将自行选择的开发会话归入此项目。").font(.callout).foregroundStyle(.secondary)
                            }
                            ForEach(project.sessionSources ?? []) { source in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(source.name).font(.callout.weight(.medium))
                                        Spacer()
                                        Toggle("读取此会话", isOn: Binding(get: { source.isEnabled }, set: { store.setSessionEnabled(id: source.id, enabled: $0) }))
                    .handCursor()
                                            .toggleStyle(.switch).controlSize(.small).disabled(store.isImporting)
                                            .accessibilityIdentifier("sourceManager.enabled.\(source.id.uuidString)")
                                    }
                                    Text(source.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text("\(source.records.count) 条保存记录 · 最近读取：\(source.refreshedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未知")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let error = source.error {
                                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                    }
                                    if !source.isEnabled {
                                        Text("后续读取已停用，历史记录仍保留。").font(.caption).foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(source.warnings.enumerated()), id: \.offset) { _, warning in
                                        Text(warning).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                }.padding(.vertical, 5)
                            }
                            Button { store.attachSessionToSelectedProject() } label: { Label("关联开发会话到此项目", systemImage: "plus") }
                                .disabled(store.isImporting || project.isSample)
                                .accessibilityIdentifier("sourceManager.attachSession")
                        }
                        Text("只读提取已选择会话中的公开记录，不扫描其他聊天；未接入代理的内部动作和批量脚本中未独立记录的步骤无法还原。原始 JSONL 不直接打开，过滤后的摘录可从记录详情回查。停用读取与暂停刷新都不会停止 Agent。")
                            .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }
            }
        }
        .padding(24).frame(width: 750, height: 610)
        .accessibilityIdentifier("sourceManagement")
    }
}
