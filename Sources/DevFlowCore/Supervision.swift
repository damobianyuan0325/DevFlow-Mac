import Foundation

public enum VerificationLevel: String, Codable, CaseIterable {
    case unit, integration, native, runtime, release
    public var title: String { switch self { case .unit: return "组件检查"; case .integration: return "集成检查"; case .native: return "原生交互验收"; case .runtime: return "实际运行"; case .release: return "交付产物" } }
}
public enum SupervisionState: String, Codable, CaseIterable {
    case satisfied, partial, failed, unverified, stale, blocked
    public var title: String { switch self { case .satisfied: return "证据满足"; case .partial: return "部分覆盖"; case .failed: return "存在失败"; case .unverified: return "缺少验证"; case .stale: return "证据已过期"; case .blocked: return "受阻" } }
}
public enum DevelopmentTaskStatus: String, Codable { case planned, inProgress, completed, blocked }
public enum VerificationResult: String, Codable { case passed, failed, unknown, notRun, blocked }
public enum IssueClosureState: String, Codable { case open, closed, unverified }

public struct SupervisionRequirement: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var originalText: String
    public var details: String
    public var assumptions: [String]
    public var scope: [String]
    public var outOfScope: [String]
    public var recordIDs: [String]
    public init(id: String, title: String, originalText: String, details: String = "", assumptions: [String] = [], scope: [String] = [], outOfScope: [String] = [], recordIDs: [String] = []) {
        self.id = id; self.title = title; self.originalText = originalText; self.details = details; self.assumptions = assumptions; self.scope = scope; self.outOfScope = outOfScope; self.recordIDs = recordIDs
    }
}
public struct AcceptanceCriterion: Codable, Equatable, Identifiable {
    public var id: String
    public var requirementID: String
    public var title: String
    public var expected: String
    public var requiredLevel: VerificationLevel
    public var sourcePaths: [String]
    public init(id: String, requirementID: String, title: String, expected: String, requiredLevel: VerificationLevel, sourcePaths: [String]) {
        self.id = id; self.requirementID = requirementID; self.title = title; self.expected = expected; self.requiredLevel = requiredLevel; self.sourcePaths = sourcePaths
    }
}
public struct DevelopmentTask: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var criterionIDs: [String]
    public var status: DevelopmentTaskStatus
    public var recordIDs: [String]
    public init(id: String, title: String, criterionIDs: [String], status: DevelopmentTaskStatus = .planned, recordIDs: [String] = []) {
        self.id = id; self.title = title; self.criterionIDs = criterionIDs; self.status = status; self.recordIDs = recordIDs
    }
}
public struct SupervisionTestCase: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var criterionIDs: [String]
    public var taskIDs: [String]
    public var input: String
    public var expected: String
    public var level: VerificationLevel
    public var sourcePaths: [String]
    public var minimumPassed: Int
    public init(id: String, title: String, criterionIDs: [String], taskIDs: [String], input: String, expected: String, level: VerificationLevel, sourcePaths: [String] = [], minimumPassed: Int = 1) {
        self.id = id; self.title = title; self.criterionIDs = criterionIDs; self.taskIDs = taskIDs; self.input = input; self.expected = expected; self.level = level; self.sourcePaths = sourcePaths; self.minimumPassed = minimumPassed
    }
}
public struct SourceFileIdentity: Codable, Equatable {
    public var path: String
    public var sha256: String
    public init(path: String, sha256: String) { self.path = path; self.sha256 = sha256 }
}
public struct ExecutionCounts: Codable, Equatable {
    public var total: Int?
    public var passed: Int?
    public var failed: Int?
    public var skipped: Int?
    public init(total: Int? = nil, passed: Int? = nil, failed: Int? = nil, skipped: Int? = nil) { self.total = total; self.passed = passed; self.failed = failed; self.skipped = skipped }
}
public struct VerificationExecution: Codable, Equatable, Identifiable {
    public var id: String
    public var testCaseID: String
    public var occurredAt: String?
    public var command: String
    public var environment: String
    public var result: VerificationResult
    public var level: VerificationLevel
    public var counts: ExecutionCounts?
    public var sourceFiles: [SourceFileIdentity]
    public var log: SourceReference?
    public var recordIDs: [String]
    public var exitCode: Int?
    public var startedAt: String?
    public var finishedAt: String?
    public var candidateVersion: String?
    public var commit: String?
    public var contractDigest: String?
    public init(id: String, testCaseID: String, occurredAt: String?, command: String, environment: String, result: VerificationResult, level: VerificationLevel, counts: ExecutionCounts? = nil, sourceFiles: [SourceFileIdentity] = [], log: SourceReference? = nil, recordIDs: [String] = [], exitCode: Int? = nil, startedAt: String? = nil, finishedAt: String? = nil, candidateVersion: String? = nil, commit: String? = nil, contractDigest: String? = nil) {
        self.id = id; self.testCaseID = testCaseID; self.occurredAt = occurredAt; self.command = command; self.environment = environment; self.result = result; self.level = level; self.counts = counts; self.sourceFiles = sourceFiles; self.log = log; self.recordIDs = recordIDs
        self.exitCode = exitCode; self.startedAt = startedAt; self.finishedAt = finishedAt; self.candidateVersion = candidateVersion; self.commit = commit
        self.contractDigest = contractDigest
    }
}
public struct SupervisionIssue: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var criterionIDs: [String]
    public var testCaseIDs: [String]
    public var declaredClosed: Bool
    public var blocking: Bool
    public var rootCause: String?
    public var missedCheckCause: String?
    public var fixRecordIDs: [String]
    public var verificationExecutionIDs: [String]
    public init(id: String, title: String, criterionIDs: [String], testCaseIDs: [String] = [], declaredClosed: Bool = false, blocking: Bool = false, rootCause: String? = nil, missedCheckCause: String? = nil, fixRecordIDs: [String] = [], verificationExecutionIDs: [String] = []) {
        self.id = id; self.title = title; self.criterionIDs = criterionIDs; self.testCaseIDs = testCaseIDs; self.declaredClosed = declaredClosed; self.blocking = blocking; self.rootCause = rootCause; self.missedCheckCause = missedCheckCause; self.fixRecordIDs = fixRecordIDs; self.verificationExecutionIDs = verificationExecutionIDs
    }
}
public struct DeliveryArtifact: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var path: String
    public var sha256: String?
    public var executionIDs: [String]
    public var recordIDs: [String]
    public init(id: String, title: String, path: String, sha256: String? = nil, executionIDs: [String] = [], recordIDs: [String] = []) {
        self.id = id; self.title = title; self.path = path; self.sha256 = sha256; self.executionIDs = executionIDs; self.recordIDs = recordIDs
    }
}
public struct SupervisionPlan: Codable, Equatable {
    public var schemaVersion: Int
    public var title: String
    public var version: String
    public var originalRequest: String
    public var assumptions: [String]
    public var scope: [String]
    public var requirements: [SupervisionRequirement]
    public var criteria: [AcceptanceCriterion]
    public var tasks: [DevelopmentTask]
    public var testCases: [SupervisionTestCase]
    public var executions: [VerificationExecution]
    public var issues: [SupervisionIssue]
    public var artifacts: [DeliveryArtifact]
    public init(schemaVersion: Int = 1, title: String, version: String, originalRequest: String, assumptions: [String] = [], scope: [String] = [], requirements: [SupervisionRequirement] = [], criteria: [AcceptanceCriterion] = [], tasks: [DevelopmentTask] = [], testCases: [SupervisionTestCase] = [], executions: [VerificationExecution] = [], issues: [SupervisionIssue] = [], artifacts: [DeliveryArtifact] = []) {
        self.schemaVersion = schemaVersion; self.title = title; self.version = version; self.originalRequest = originalRequest; self.assumptions = assumptions; self.scope = scope; self.requirements = requirements; self.criteria = criteria; self.tasks = tasks; self.testCases = testCases; self.executions = executions; self.issues = issues; self.artifacts = artifacts
    }
    public func validate() throws { try SupervisionEvaluator.validate(self) }
}
public struct SupervisionItemAssessment: Equatable, Identifiable {
    public var id: String
    public var state: SupervisionState
    public var reasons: [String]
    public var evidenceIDs: [String]
}
public struct ExecutionAssessment: Equatable, Identifiable {
    public var id: String
    public var state: SupervisionState
    public var reasons: [String]
    public var isValidPass: Bool
}
public struct IssueAssessment: Equatable, Identifiable {
    public var id: String
    public var state: IssueClosureState
    public var reasons: [String]
    public var effectiveRetestIDs: [String]
}
public struct SupervisionIntervention: Equatable, Identifiable {
    public var id: String
    public var targetID: String
    public var title: String
    public var reason: String
}
public struct SupervisionAssessment: Equatable {
    public var requirements: [SupervisionItemAssessment]
    public var criteria: [SupervisionItemAssessment]
    public var executions: [ExecutionAssessment]
    public var issues: [IssueAssessment]
    public var artifacts: [SupervisionItemAssessment]
    public var interventions: [SupervisionIntervention]
    public var briefing: [String]
    public var validationErrors: [String]
}

public enum SupervisionEvaluator {
    /// Bind an execution to the declared input and expectation, independently of its result.
    public static func contractDigest(plan: SupervisionPlan, testCaseID: String) throws -> String {
        guard let test = plan.testCases.first(where: { $0.id == testCaseID }) else { throw DevFlowError.invalid("用例不存在，不能生成验收合同摘要。") }
        let criteria = plan.criteria.filter { test.criterionIDs.contains($0.id) }.sorted { $0.id < $1.id }
        let requirementIDs = Set(criteria.map(\.requirementID))
        let requirements = plan.requirements.filter { requirementIDs.contains($0.id) }.sorted { $0.id < $1.id }.map {
            ContractRequirement(id: $0.id, title: $0.title, originalText: $0.originalText, details: $0.details, assumptions: $0.assumptions, scope: $0.scope, outOfScope: $0.outOfScope)
        }
        let tasks = plan.tasks.filter { test.taskIDs.contains($0.id) }.sorted { $0.id < $1.id }.map { ContractTask(id: $0.id, title: $0.title, criterionIDs: $0.criterionIDs) }
        let snapshot = ContractSnapshot(version: plan.version, originalRequest: plan.originalRequest, assumptions: plan.assumptions, scope: plan.scope, requirements: requirements, criteria: criteria, tasks: tasks, testCase: test)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ProjectImporter.digest(try encoder.encode(snapshot))
    }
    private struct ContractRequirement: Codable {
        var id: String; var title: String; var originalText: String; var details: String; var assumptions: [String]; var scope: [String]; var outOfScope: [String]
    }
    private struct ContractTask: Codable { var id: String; var title: String; var criterionIDs: [String] }
    private struct ContractSnapshot: Codable {
        var version: String; var originalRequest: String; var assumptions: [String]; var scope: [String]
        var requirements: [ContractRequirement]; var criteria: [AcceptanceCriterion]; var tasks: [ContractTask]; var testCase: SupervisionTestCase
    }
    public static func validate(_ plan: SupervisionPlan) throws {
        guard plan.schemaVersion == 1 else { throw DevFlowError.invalid("监督计划 schemaVersion 不受支持。") }
        let groups = [plan.requirements.map(\.id), plan.criteria.map(\.id), plan.tasks.map(\.id), plan.testCases.map(\.id), plan.executions.map(\.id), plan.issues.map(\.id), plan.artifacts.map(\.id)]
        let ids = groups.flatMap { $0 }
        guard ids.count <= 20_000, groups.allSatisfy({ $0.count <= 5_000 }) else { throw DevFlowError.invalid("监督计划超过数量上限。") }
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 128 && $0.rangeOfCharacter(from: .controlCharacters) == nil }), Set(ids).count == ids.count else { throw DevFlowError.invalid("监督计划 ID 为空、过长或重复；各类型 ID 必须全局唯一。") }
        guard let encoded = try? JSONEncoder().encode(plan), encoded.count <= 8 * 1_024 * 1_024 else { throw DevFlowError.invalid("监督计划超过 8 MiB 上限。") }
        let requirements = Set(plan.requirements.map(\.id)), criteria = Set(plan.criteria.map(\.id)), tasks = Set(plan.tasks.map(\.id)), cases = Set(plan.testCases.map(\.id)), executions = Set(plan.executions.map(\.id))
        func references(_ refs: [String], in allowed: Set<String>, owner: String) throws {
            guard Set(refs).count == refs.count, refs.allSatisfy(allowed.contains) else { throw DevFlowError.invalid("\(owner) 含重复或不存在的图关联。") }
        }
        func recordReferences(_ refs: [String]) throws {
            guard refs.count <= 2_000, Set(refs).count == refs.count, refs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else { throw DevFlowError.invalid("动作记录关联格式不合法。") }
        }
        for requirement in plan.requirements { try recordReferences(requirement.recordIDs) }
        for criterion in plan.criteria {
            try references([criterion.requirementID], in: requirements, owner: criterion.id)
            try validatePaths(criterion.sourcePaths)
        }
        for task in plan.tasks { try references(task.criterionIDs, in: criteria, owner: task.id); try recordReferences(task.recordIDs) }
        for test in plan.testCases {
            try references(test.criterionIDs, in: criteria, owner: test.id); try references(test.taskIDs, in: tasks, owner: test.id)
            try validatePaths(test.sourcePaths)
            guard test.minimumPassed > 0, test.minimumPassed <= 1_000_000 else { throw DevFlowError.invalid("\(test.id) 的最少通过数必须是明确正数。") }
            for taskID in test.taskIDs {
                guard let task = plan.tasks.first(where: { $0.id == taskID }), !Set(task.criterionIDs).isDisjoint(with: test.criterionIDs) else { throw DevFlowError.invalid("\(test.id) 的任务关联不属于其验收标准。") }
            }
        }
        for execution in plan.executions {
            try references([execution.testCaseID], in: cases, owner: execution.id); try recordReferences(execution.recordIDs)
            if let digest = execution.contractDigest { try validateHash(digest) }
            try validatePaths(execution.sourceFiles.map(\.path))
            for file in execution.sourceFiles { try validateHash(file.sha256) }
            if let log = execution.log {
                try validatePath(log.path); if let digest = log.digest { try validateHash(digest) }
                if let line = log.line, line < 1 { throw DevFlowError.invalid("\(execution.id) 的日志行号不合法。") }
            }
            if let counts = execution.counts {
                let values = [counts.total, counts.passed, counts.failed, counts.skipped].compactMap { $0 }
                guard values.allSatisfy({ $0 >= 0 && $0 <= 1_000_000_000 }) else { throw DevFlowError.invalid("\(execution.id) 的执行计数超出范围。") }
            }
        }
        for issue in plan.issues {
            try references(issue.criterionIDs, in: criteria, owner: issue.id); try references(issue.testCaseIDs, in: cases, owner: issue.id)
            try references(issue.verificationExecutionIDs, in: executions, owner: issue.id); try recordReferences(issue.fixRecordIDs)
            for testID in issue.testCaseIDs {
                guard let test = plan.testCases.first(where: { $0.id == testID }), !Set(test.criterionIDs).isDisjoint(with: issue.criterionIDs) else { throw DevFlowError.invalid("\(issue.id) 的回归用例不属于问题标准。") }
            }
            for executionID in issue.verificationExecutionIDs {
                guard let execution = plan.executions.first(where: { $0.id == executionID }), let test = plan.testCases.first(where: { $0.id == execution.testCaseID }), !Set(test.criterionIDs).isDisjoint(with: issue.criterionIDs) else { throw DevFlowError.invalid("\(issue.id) 的复验与问题标准无对应关系。") }
            }
        }
        for artifact in plan.artifacts {
            try validatePath(artifact.path); if let sha = artifact.sha256 { try validateHash(sha) }
            try references(artifact.executionIDs, in: executions, owner: artifact.id); try recordReferences(artifact.recordIDs)
        }
    }
    public static func evaluate(plan: SupervisionPlan, root: String, records: [ActivityRecord]) -> SupervisionAssessment {
        var assessment = SupervisionAssessment(requirements: [], criteria: [], executions: [], issues: [], artifacts: [], interventions: [], briefing: [], validationErrors: [])
        do { try validate(plan) } catch {
            let reason = error.localizedDescription
            assessment.validationErrors = [reason]
            assessment.requirements = plan.requirements.map { .init(id: $0.id, state: .blocked, reasons: [reason], evidenceIDs: []) }
            assessment.criteria = plan.criteria.map { .init(id: $0.id, state: .blocked, reasons: [reason], evidenceIDs: []) }
            assessment.interventions = [.init(id: "invalid-plan", targetID: "plan", title: "修正监督计划", reason: reason)]
            assessment.briefing = ["计划校验失败；未读取来源文件，也未计算通过结论。"]
            return assessment
        }
        let reader = EvidenceReader(root: root)
        let recordGroups = Dictionary(grouping: records, by: \.id)
        let tests = Dictionary(uniqueKeysWithValues: plan.testCases.map { ($0.id, $0) })
        func missingRecords(_ ids: [String]) -> [String] {
            ids.filter { recordGroups[$0]?.count != 1 }.map { "关联动作 \($0) 未接入或 ID 不唯一，尚无可核对记录。" }
        }
        // Give each test's current candidates the finite I/O budget first.
        // Unknown dates and ties remain candidates; never select just a success.
        let groups = Dictionary(grouping: plan.executions, by: \.testCaseID)
        let currentIDs = Set(groups.values.flatMap { entries -> [String] in
            if entries.contains(where: { executionDate($0) == nil }) { return entries.map(\.id) }
            let newest = entries.compactMap(executionDate).max()
            return entries.filter { executionDate($0) == newest }.map(\.id)
        })
        let readOrder = plan.executions.filter { currentIDs.contains($0.id) } + plan.executions.filter { !currentIDs.contains($0.id) }
        for execution in readOrder {
            let test = tests[execution.testCaseID]!
            var reasons = missingRecords(execution.recordIDs)
            var stale = false
            var layerMismatch = false
            let explicitFailure = execution.result == .failed || (execution.exitCode.map { $0 != 0 } ?? false) || (execution.counts?.failed ?? 0) > 0
            if execution.result != .passed { reasons.append("本次结构化结果为 \(execution.result.rawValue)，没有声明有效通过。") }
            if let code = execution.exitCode, code != 0 { reasons.append("实际记录的退出码为 \(code)。") }
            if executionDate(execution) == nil { reasons.append("执行时间缺失或无效，不能推断先后顺序。") }
            if let startedAt = execution.startedAt, date(startedAt) == nil { reasons.append("执行开始时间格式无效。") }
            if let start = execution.startedAt, let finish = execution.finishedAt, let startDate = date(start), let finishDate = date(finish), startDate > finishDate { reasons.append("执行开始时间晚于结束时间。") }
            if execution.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || execution.environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append("执行命令或环境身份未记录。") }
            if let version = execution.candidateVersion, version != plan.version { stale = true; reasons.append("执行候选版本 \(version) 与当前计划版本 \(plan.version) 不一致。") }
            if let bound = execution.contractDigest, !bound.isEmpty {
                if let current = try? contractDigest(plan: plan, testCaseID: test.id), current.lowercased() != bound.lowercased() { stale = true; reasons.append("需求或验收合同已改变，旧执行的输入、预期与范围绑定不再适用。") }
            } else { reasons.append("执行未记录验收合同摘要，无法核对是否对应当前需求、输入和预期。") }
            if execution.level != test.level { layerMismatch = true; reasons.append("执行层级 \(execution.level.title) 与用例要求 \(test.level.title) 不一致。") }
            if test.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || test.expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append("用例输入或独立预期未固定。") }
            if test.criterionIDs.isEmpty || test.taskIDs.isEmpty { reasons.append("用例尚未关联验收标准或开发任务。") }
            if let counts = execution.counts, let total = counts.total, let passed = counts.passed, let failed = counts.failed, let skipped = counts.skipped {
                if total != passed + failed + skipped || total == 0 || passed < test.minimumPassed || failed != 0 || skipped != 0 { reasons.append("执行计数不满足全部通过且无失败、无跳过的要求；空跑不能通过。") }
            } else { reasons.append("执行计数不完整；缺失值是未知，不能当作零失败或零跳过。") }
            if let log = execution.log, let digest = log.digest, !digest.isEmpty {
                switch reader.digest(path: log.path) {
                case .success(let actual): if actual.lowercased() != digest.lowercased() { reasons.append("日志 SHA256 不一致；原执行凭据已改变。") }
                case .failure(let error): reasons.append("日志不可核验：\(error.localizedDescription)")
                }
            } else { reasons.append("日志路径或 SHA256 缺失。") }
            let linkedCriteria = plan.criteria.filter { test.criterionIDs.contains($0.id) }
            let requiredPaths = Set(test.sourcePaths + linkedCriteria.flatMap(\.sourcePaths))
            if execution.sourceFiles.isEmpty || requiredPaths.isEmpty || linkedCriteria.contains(where: { $0.sourcePaths.isEmpty }) { reasons.append("源码身份或验收涉及的源码范围未记录。") }
            let boundPaths = Set(execution.sourceFiles.map(\.path))
            if !requiredPaths.isSubset(of: boundPaths) { reasons.append("执行源码身份未覆盖用例与标准要求的全部文件。") }
            for file in execution.sourceFiles {
                if file.sha256.isEmpty { reasons.append("源码 \(file.path) 的 SHA256 缺失。"); continue }
                switch reader.digest(path: file.path) {
                case .success(let actual): if actual.lowercased() != file.sha256.lowercased() { stale = true; reasons.append("源码 \(file.path) 已变化，旧通过不再适用。") }
                case .failure(let error): reasons.append("源码 \(file.path) 不可核验：\(error.localizedDescription)")
                }
            }
            let valid = reasons.isEmpty && execution.result == .passed
            let state: SupervisionState = explicitFailure ? .failed : (execution.result == .blocked ? .blocked : (stale ? .stale : (valid ? .satisfied : (layerMismatch ? .partial : .unverified))))
            if valid { reasons = ["结构化通过、完整计数、日志与源码身份在本次读取时一致；只支持该用例的 \(test.level.title) 层级。", "摘要一致不证明业务预期充分、日志真实或具有防恶意能力；命令仅记录，未由本软件执行。"] }
            assessment.executions.append(.init(id: execution.id, state: state, reasons: reasons, isValidPass: valid))
        }
        let originalOrder = Dictionary(uniqueKeysWithValues: plan.executions.enumerated().map { ($0.element.id, $0.offset) })
        assessment.executions.sort { originalOrder[$0.id]! < originalOrder[$1.id]! }
        let executionAssessments = Dictionary(uniqueKeysWithValues: assessment.executions.map { ($0.id, $0) })
        func latest(_ testID: String) -> [VerificationExecution] {
            let entries = plan.executions.filter { $0.testCaseID == testID }
            // An undated entry cannot be silently ordered before an older success.
            if entries.contains(where: { executionDate($0) == nil }) { return entries }
            guard let lastDate = entries.compactMap(executionDate).max() else { return [] }
            return entries.filter { executionDate($0) == lastDate }
        }
        func testAssessment(_ test: SupervisionTestCase) -> SupervisionItemAssessment {
            let entries = latest(test.id)
            guard !entries.isEmpty else { return .init(id: test.id, state: .unverified, reasons: ["用例 \(test.id) 没有执行记录。"], evidenceIDs: []) }
            let items = entries.compactMap { executionAssessments[$0.id] }
            var state = combine(items.map(\.state))
            var reasons = items.flatMap(\.reasons)
            if entries.count != 1 {
                if state != .failed && state != .stale && state != .blocked { state = .unverified }
                reasons.append("用例 \(test.id) 的最新执行时间缺失或并列，不能从中挑选旧成功。")
            }
            return .init(id: test.id, state: state, reasons: reasons, evidenceIDs: entries.map(\.id))
        }
        let testAssessments = Dictionary(uniqueKeysWithValues: plan.testCases.map { ($0.id, testAssessment($0)) })
        for issue in plan.issues {
            var reasons = missingRecords(issue.fixRecordIDs)
            if issue.fixRecordIDs.isEmpty { reasons.append("未关联实际修复记录；关闭声明不能证明已修复。") }
            let fixes = issue.fixRecordIDs.compactMap { recordGroups[$0]?.count == 1 ? recordGroups[$0]?.first : nil }
            let fixDates = fixes.compactMap { date($0.occurredAt) }
            if fixes.contains(where: { $0.kind != .development }) { reasons.append("修复关联不是研发变更记录。") }
            if fixes.contains(where: { ![RecordStatus.recorded, .passed].contains($0.status) }) { reasons.append("修复动作记录为失败、受阻、未完成或状态未知，不能充当完成修复。") }
            if fixDates.count != fixes.count || fixDates.isEmpty { reasons.append("修复真实时间未记录，不能确认复验发生在修复之后。") }
            let latestFix = fixDates.max()
            var validRetests: [VerificationExecution] = []
            var rejectedRetests: [String] = []
            for id in issue.verificationExecutionIDs {
                guard let execution = plan.executions.first(where: { $0.id == id }), let test = tests[execution.testCaseID] else { continue }
                var rejected: [String] = []
                if executionAssessments[id]?.isValidPass != true { rejected.append("执行证据当前不满足有效通过，见该执行的核验原因") }
                if testAssessment(test).state != .satisfied || latest(test.id).count != 1 || latest(test.id).first?.id != id {
                    rejected.append("不是用例唯一、最新且有效的执行（含时间未知或并列）")
                }
                if let checkedAt = executionDate(execution), let latestFix {
                    if checkedAt <= latestFix { rejected.append("复验时间没有严格晚于最后修复时间") }
                } else { rejected.append("修复或复验时间缺失，无法核对先后") }
                for criterion in plan.criteria where issue.criterionIDs.contains(criterion.id) && test.criterionIDs.contains(criterion.id) && criterion.requiredLevel != execution.level {
                    rejected.append("标准 \(criterion.id) 要求 \(criterion.requiredLevel.title) 层级，执行为 \(execution.level.title)；层级必须精确匹配")
                }
                if rejected.isEmpty { validRetests.append(execution) }
                else { rejectedRetests.append("复验 \(id)（用例 \(test.id)）未纳入闭环：" + rejected.joined(separator: "；")) }
            }
            let coveredCases = Set(validRetests.map(\.testCaseID))
            let coveredCriteria = Set(validRetests.flatMap { tests[$0.testCaseID]?.criterionIDs ?? [] })
            if issue.verificationExecutionIDs.isEmpty || validRetests.isEmpty { reasons.append("缺少晚于修复且当前仍有效的对应复验。") }
            if issue.criterionIDs.isEmpty || !Set(issue.criterionIDs).isSubset(of: coveredCriteria) || !Set(issue.testCaseIDs).isSubset(of: coveredCases) { reasons.append("有效复验尚未覆盖问题涉及的全部标准和回归用例。") }
            if !reasons.isEmpty { reasons += rejectedRetests }
            let closed = reasons.isEmpty
            if closed { reasons = ["修复记录存在，且对应标准与回归用例的最新有效复验发生在修复之后。", "闭环只覆盖已声明问题范围；关闭声明本身不参与通过判定。"] }
            assessment.issues.append(.init(id: issue.id, state: closed ? .closed : (issue.declaredClosed ? .unverified : .open), reasons: reasons, effectiveRetestIDs: validRetests.map(\.id)))
        }
        for criterion in plan.criteria {
            let relevant = plan.testCases.filter { $0.criterionIDs.contains(criterion.id) }
            let tested = relevant.compactMap { testAssessments[$0.id] }
            var reasons = tested.flatMap(\.reasons)
            var state = combine(tested.map(\.state))
            let tasks = plan.tasks.filter { $0.criterionIDs.contains(criterion.id) }
            let missingTaskRecords = tasks.flatMap { missingRecords($0.recordIDs) }
            reasons += missingTaskRecords
            if relevant.isEmpty { reasons.append("标准尚未关联测试用例。") }
            if !relevant.contains(where: { $0.level == criterion.requiredLevel }) {
                reasons.append("仍需 \(criterion.requiredLevel.title) 的对应验收；其他层级不能替代。")
                if state == .satisfied { state = .partial }
            }
            if !missingTaskRecords.isEmpty && state == .satisfied { state = .partial }
            if criterion.expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || criterion.sourcePaths.isEmpty {
                reasons.append("标准的可观察预期或源码范围尚未固定。")
                if state == .satisfied { state = .unverified }
            }
            if tasks.isEmpty { reasons.append("没有关联开发任务，实施范围尚未接入。"); if state == .satisfied { state = .partial } }
            let blockedTasks = tasks.filter { $0.status == .blocked }
            let hasBlockingIssue = plan.issues.contains { issue in issue.blocking && issue.criterionIDs.contains(criterion.id) && assessment.issues.first(where: { $0.id == issue.id })?.state != .closed }
            if !blockedTasks.isEmpty || hasBlockingIssue {
                reasons.append("关联任务或未闭环问题明确受阻。")
                if state != .failed && state != .stale { state = .blocked }
            }
            assessment.criteria.append(.init(id: criterion.id, state: state, reasons: unique(reasons), evidenceIDs: unique(tested.flatMap(\.evidenceIDs))))
        }
        for requirement in plan.requirements {
            let criteria = plan.criteria.filter { $0.requirementID == requirement.id }.compactMap { item in assessment.criteria.first { $0.id == item.id } }
            var reasons = criteria.flatMap(\.reasons)
            var state = combine(criteria.map(\.state))
            if criteria.isEmpty { reasons.append("需求尚未拆解为可观察验收标准。") }
            let missing = missingRecords(requirement.recordIDs); reasons += missing
            if !missing.isEmpty && state == .satisfied { state = .partial }
            assessment.requirements.append(.init(id: requirement.id, state: state, reasons: unique(reasons), evidenceIDs: unique(criteria.flatMap(\.evidenceIDs))))
        }
        for artifact in plan.artifacts {
            var reasons = missingRecords(artifact.recordIDs)
            var state: SupervisionState = .satisfied
            if let expected = artifact.sha256, !expected.isEmpty {
                switch reader.digest(path: artifact.path) {
                case .success(let actual): if actual.lowercased() != expected.lowercased() { state = .stale; reasons.append("交付产物 SHA256 已变化。") }
                case .failure(let error): reasons.append("交付产物不可核验：\(error.localizedDescription)")
                }
            } else { reasons.append("交付产物 SHA256 未记录。") }
            if artifact.executionIDs.isEmpty || artifact.executionIDs.contains(where: { id in
                guard executionAssessments[id]?.isValidPass == true, let execution = plan.executions.first(where: { $0.id == id }), let test = tests[execution.testCaseID] else { return true }
                return testAssessment(test).state != .satisfied || latest(test.id).first?.id != id
            }) { reasons.append("交付产物没有完整且当前最新有效的验证关联。") }
            if state == .satisfied && !reasons.isEmpty { state = .unverified }
            if reasons.isEmpty { reasons = ["文件字节摘要一致且关联验证有效；不代表签名、公证、安装或业务验收已完成。"] }
            assessment.artifacts.append(.init(id: artifact.id, state: state, reasons: reasons, evidenceIDs: artifact.executionIDs))
        }
        for item in assessment.criteria + assessment.requirements + assessment.artifacts where item.state != .satisfied {
            assessment.interventions.append(.init(id: "review-" + item.id, targetID: item.id, title: "\(item.id) · \(item.state.title)", reason: item.reasons.joined(separator: "\n")))
        }
        for issue in assessment.issues where issue.state != .closed {
            assessment.interventions.append(.init(id: "issue-" + issue.id, targetID: issue.id, title: "\(issue.id) · 核对问题闭环", reason: issue.reasons.joined(separator: "\n")))
        }
        assessment.briefing = [
            "需求：\(plan.requirements.count) 项；已有 \(assessment.requirements.filter { $0.state == .satisfied }.count) 项在声明范围内满足证据要求。",
            "开发：\(plan.tasks.count) 项任务；完成状态来自声明，受阻 \(plan.tasks.filter { $0.status == .blocked }.count) 项。",
            "验证：保留 \(plan.executions.count) 次历史执行；\(assessment.executions.filter(\.isValidPass).count) 次证据当前适用，失败 \(assessment.executions.filter { $0.state == .failed }.count) 次。",
            "问题：\(assessment.issues.filter { $0.state == .closed }.count)/\(plan.issues.count) 项有修复与有效复验；产物 \(assessment.artifacts.filter { $0.state == .satisfied }.count)/\(plan.artifacts.count) 项字节与关联凭据可核对。",
            "仅只读核对所声明的文件和关系；未执行命令。SHA256 一致不能证明业务正确、原始声明真实或防止恶意篡改。"
        ]
        if reader.budgetExceeded {
            assessment.briefing.append("证据读取达到预算：优先核验各用例最新候选（含并列和时间未知），其余历史仍保留；未读取的文件明确标为不可核验，不表示历史全部核验或当前验收全部通过。")
        }
        return assessment
    }

    private static func combine(_ states: [SupervisionState]) -> SupervisionState {
        guard !states.isEmpty else { return .unverified }
        for state in [SupervisionState.failed, .stale, .blocked] where states.contains(state) { return state }
        if states.allSatisfy({ $0 == .satisfied }) { return .satisfied }
        if states.contains(.satisfied) || states.contains(.partial) { return .partial }
        return .unverified
    }
    private static func unique(_ items: [String]) -> [String] { var seen = Set<String>(); return items.filter { seen.insert($0).inserted } }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value)
    }
    private static func executionDate(_ execution: VerificationExecution) -> Date? { date(execution.finishedAt ?? execution.occurredAt) }
    private static func validateHash(_ value: String) throws {
        guard value.isEmpty || value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw DevFlowError.invalid("文件身份必须是原文件字节的 SHA256。") }
    }
    private static func validatePaths(_ paths: [String]) throws {
        guard paths.count <= 2_000, Set(paths).count == paths.count else { throw DevFlowError.invalid("源码文件路径重复或超过数量上限。") }
        for path in paths { try validatePath(path) }
    }
    private static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, path.utf8.count <= 2_048, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\"), !path.contains(":"), path.rangeOfCharacter(from: .controlCharacters) == nil,
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw DevFlowError.invalid("拒绝越界或非相对来源路径。") }
        let forbidden = Set([".git", ".ssh", ".aws", ".gnupg", ".codex", "credentials", "credentials.json", "secrets.json", "auth.json", "id_rsa", "id_ed25519"])
        guard !parts.contains(where: { part in let lower = part.lowercased(); return forbidden.contains(lower) || lower == ".env" || lower.hasPrefix(".env.") || ["pem", "key", "p12", "pfx", "keychain"].contains((lower as NSString).pathExtension) }) else { throw DevFlowError.invalid("拒绝秘密或凭据路径。") }
    }
    private final class EvidenceReader {
        let root: String
        var cache: [String: Result<String, DevFlowError>] = [:]
        var bytesRead = 0
        var budgetExceeded = false
        init(root: String) { self.root = root }
        func digest(path: String) -> Result<String, DevFlowError> {
            if let cached = cache[path] { return cached }
            let result: Result<String, DevFlowError>
            do {
                try validatePath(path)
                guard cache.count < 1_024 else { budgetExceeded = true; throw DevFlowError.invalid("本次最多核验 1024 个文件，后续未读取。") }
                let base = URL(fileURLWithPath: root).standardizedFileURL
                guard root.hasPrefix("/"), base.path == base.resolvingSymlinksInPath().path else { throw DevFlowError.invalid("来源根目录不是绝对真实路径或含符号链接。") }
                var current = base
                for part in path.split(separator: "/") {
                    current.appendPathComponent(String(part))
                    let info = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
                    guard info.isSymbolicLink != true else { throw DevFlowError.invalid("拒绝符号链接来源。") }
                }
                guard current.path.hasPrefix(base.path + "/"), current.resolvingSymlinksInPath().path == current.path else { throw DevFlowError.invalid("来源越界或包含符号链接。") }
                let info = try current.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard info.isRegularFile == true else { throw DevFlowError.invalid("来源必须是普通文件。") }
                let limit = 4 * 1_024 * 1_024
                guard (info.fileSize ?? limit + 1) <= limit, bytesRead + (info.fileSize ?? limit + 1) <= 32 * 1_024 * 1_024 else { budgetExceeded = true; throw DevFlowError.invalid("核验读取超过单文件 4 MiB 或累计 32 MiB 上限，未读取。") }
                let handle = try FileHandle(forReadingFrom: current); defer { try? handle.close() }
                var data = Data()
                while data.count <= limit, let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty { data.append(chunk) }
                guard data.count <= limit, bytesRead + data.count <= 32 * 1_024 * 1_024 else { budgetExceeded = true; throw DevFlowError.invalid("核验读取超过字节上限，未使用截断摘要。") }
                bytesRead += data.count
                result = .success(ProjectImporter.digest(data))
            } catch let error as DevFlowError { result = .failure(error) }
            catch { result = .failure(.invalid("文件缺失或无法只读访问。")) }
            cache[path] = result
            return result
        }
    }
}
