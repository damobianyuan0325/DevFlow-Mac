# 本地项目监督协议 v1

本协议描述 DevFlow 0.2.0 使用的本地 JSON 资料形状。它是资料生产者、开发代理与只读客户端之间的数据约定，不要求外部研发技能，也不表示客户端会执行计划中的命令。可选研发流程的机器计划与本协议不是同一种合同。

技能或开发Agent负责记录原话、拆解、预期、任务、关系、执行身份、修复原因及阶段结论；客户端负责显示、关联、核对本地证据和整理手动反馈。缺失语义不能靠客户端猜测补全。公开动作流与语义台账互补：原始动作说明发生了什么，台账说明它试图满足哪项要求。

## 包与身份

外层为`{schemaVersion: 2, name, records, supervision}`；`records`仍使用ActivityRecord，`supervision`为`SupervisionPlan`，内部`schemaVersion`为1。原schemaVersion=1资料继续作为普通历史资料读取。精确字段及枚举见 [Supervision.swift](https://github.com/damobianyuan0325/DevFlow-Mac/blob/v0.2.0-preview.1/Sources/DevFlowCore/Supervision.swift) 和 [Models.swift](https://github.com/damobianyuan0325/DevFlow-Mac/blob/v0.2.0-preview.1/Sources/DevFlowCore/Models.swift)。

监督计划包括`title`、`version`、`originalRequest`、`assumptions`、`scope`和以下数组。所有监督对象ID全局唯一且稳定，版本更新追加真实执行，不更换ID掩盖原失败；动作记录使用自己的稳定ID。语义台账使用 R/A/U/T/E 分别表示需求、验收、研发任务、检查设计、实际执行。数组即使为空也应保留；可选字段未知时使用 null 或省略，不写猜测值。

| 数组 | 关键字段 | 含义与关系 |
| --- | --- | --- |
| requirements | id/title/originalText/details/assumptions/scope/outOfScope/recordIDs | R保留原话、AI拆解与边界，recordIDs指向来源动作 |
| criteria | id/requirementID/title/expected/requiredLevel/sourcePaths | A属于一个R，固定可观察预期、必要验证层级和源码范围 |
| tasks | id/title/criterionIDs/status/recordIDs | U落实A，状态planned/inProgress/completed/blocked；完成任务不自动满足A |
| testCases | id/title/criterionIDs/taskIDs/input/expected/level/sourcePaths/minimumPassed | T固定输入、独立预期及最低有效通过数；设计存在不表示运行过 |
| executions | id/testCaseID/occurredAt/command/environment/result/level/counts/sourceFiles/log/recordIDs | E属于一个T，每次执行独立保留；可选exitCode/startedAt/finishedAt/candidateVersion/commit/contractDigest记录实际执行身份与合同身份 |
| issues | id/title/criterionIDs/testCaseIDs/declaredClosed/blocking/rootCause/missedCheckCause/fixRecordIDs/verificationExecutionIDs | 问题绑定标准、回归设计、真实修复及复验；声明关闭与证据闭环分开 |
| artifacts | id/title/path/sha256/executionIDs/recordIDs | 交付文件的身份及有关执行；`.app`目录不能冒充可计算的单文件摘要 |

`SourceReference` 必填 `path` 和 `excerpt`，可选 `line` 和 `digest`：path 相对用户绑定的资料根；line 为从 1 开始的行号；excerpt 为真实简短摘录；digest 为该来源文件完整字节的 SHA-256。`sourceFiles`每项为`path/sha256`，必须来自执行时冻结的源码身份，不能用导入时源码重算来替换旧身份。每个A/T需要明确相关源码范围，不能只绑定一个无关文件来制造通过。

ID关联有类型：A→R、U→A、T→A/U、E→T、问题→A/T/修复记录/E、产物→E/记录。没有任意关系名的自由推理。非法图引用、重复ID和不安全路径拒绝导入；未接入的recordIDs保留缺证原因。关系说明范围，不自动证明因果。

## 实际结果与当前适用性

E的`result`只允许passed/failed/unknown/notRun/blocked，表示记录的那次结果；`level`为unit/integration/native/runtime/release。`counts`的total/passed/failed/skipped必须来自真实执行，未知填null或省略，不能把记录数、日志行数、断言数或命令成功混成用例数。负控的预期失败要在用例预期中说明，不冒称产品缺陷。

当前有效通过要求结果、完整非零计数、日志摘要、相关源码摘要、测试层级、版本及可核对来源共同适用。总数须与通过/失败/跳过相符，达到T的minimumPassed，无失败或跳过；有明确非零退出码则判为核验未通过（机读state=failed），缺退出码不补零。这不改写E.result，也不能仅凭非零退出码断定产品运行失败。无有效时间不能据此证明执行顺序。摘要一致仅表示本机读取时字节一致，不证明业务预期充分或日志不可伪造。

新E还须在实际执行前冻结`contractDigest`，由`SupervisionEvaluator.contractDigest(plan:testCaseID:)`产生。它绑定计划版本、原话、假设与范围，相关 R 的原话及拆解，A/T 的输入、预期、层级和范围，以及关联 U 的身份、标题和标准引用；同 ID 的合同后来改变，旧成功也会过期。执行列表、任务状态及任务 recordIDs 不进入该摘要。旧E没有执行时合同绑定就保持null或省略，不能用今天的合同补写成当时已绑定。

客户端另算satisfied/partial/failed/unverified/stale/blocked。旧E的passed保留；候选版本或源码身份已变时当前状态为stale，缺源/缺日志/缺计数保持缺证。多个执行时间缺失或并列时不能挑旧成功充当最新。前一层检查不能替代原生或交付验收。任务completed、问题declaredClosed、构建退出0和整体需求满足是不同事实。

问题的关闭评估需要研发修复记录的ID、类型、状态与时间，以及严格晚于修复、覆盖对应标准/回归且当前仍有效的最新复验。当前评估不读取修复记录原件或校验其digest，closed不能证明修复内容已被独立核验；代理仍应保存真实来源供用户回查。首失败保留；缺时间、旧成功过期或仅有“已修复”报告时，仍显示尚不能验证关闭。不能为了减少红项把旧失败删掉或回填不存在的时间。

## 来源与持续读取边界

导入和关联都是用户主动选择。项目根、资料包和单个会话可在本机聚合；绝对私有会话路径只属于本机绑定，不写入可移交包。本协议不授权扫描所有私有对话、隐藏推理、system/developer内容、未接入子Agent或密文。实际结构化子动作可以显示，批量脚本没有独立记录的步骤不能静态解析后冒称已执行。

前台项目15秒读取当前已接入来源；刷新失败保留上次内容并显示错误。历史归档时间、导入时间、文档日期与事件时间不同；无法核实事件时刻就保持未知。合成教学样本必须明确标注，不能作为真实执行或完整动作全集。持续会话也只代表其明确披露的接入范围。耗时与费用无可信来源时显示未接入，不能由条数估算。

所有来源路径限制在授权资料根内，拒绝绝对路径、向上越界及符号链接逃逸。客户端有读取数量和大小上限，超限明确未验证；原始大日志不需要复制进包。可分享包应只有经过检查的摘录、相对路径和摘要。摘录本身仍可能含私人路径、身份或业务资料，格式合法不等于已经脱敏；公开示例使用合成数据，真实历史在授权范围内单独保留。

## 动作记录

每个 `records` 项必填 `id/kind/title/summary/status/origin/source/relatedIDs/limitations`，可选 `occurredAt/version/action`。`relatedIDs` 引用其他动作记录，不替代监督图中的类型关系。未知事件时间保持缺失，不把导入时间补作发生时间。

- `kind`：requirement/development/test/bug/decision/delivery。
- `status`：recorded/inProgress/passed/failed/open/notRun/blocked/unknown/needsReview。
- `origin`：document/execution/retrospective，分别表示文档记载、执行凭据和复盘归纳。
- `action` 如提供，包含必填 `kind` 和可选 `callID`；动作类型为 request/progress/toolCall/toolResult/command/fileChange/agentReport/other。调用与返回的关联不表示业务验收已经通过。

正文报告、工具返回、真实检查与验收是不同事实。资料生产者应记录实际读取、编辑、命令、失败、修复和交付的来源；不可得到的内部步骤保持缺口。

## 工具与维护

随仓库的 [devflow-record](../skills/devflow-record/SKILL.md) 提供模板、字段参考和干净教学例子；[devflow-resolve](../skills/devflow-resolve/SKILL.md) 提供核对反馈与保留历史的回写流程。两者均可独立使用，客户端不会自动调用它们或调度开发代理。

`DevFlowEvidence` 目前由 macOS 源码构建，获取方式见 [代理接入指南](agent-quickstart.md#获取实际可用的证据工具)。

- `contracts <包路径>` 输出每个 T 的规范合同摘要；应在实际检查前保存，再写入新 E 的 `contractDigest`，不能自创算法或事后回填历史。
- `inspect <包路径>` 读取指定 JSON 的 records 和 supervision，以包所在目录为资料根核对本地来源；没有另设 root 参数。App 可另外绑定资料根与会话，两者接入范围可能不同。
- `inspect` 输出 requirements/criteria/artifacts 的 state、reasons、evidenceIDs，executions 的 state、validPass、reasons，issues 的 state、reasons，以及 briefing、warnings、validationErrors。退出 0 仅代表报告成功生成。

没有 CLI 时仍能记录真实开发事实，但不能编造合同或声称已机器读回。更新已有包时保留旧 R/A/T 合同快照、失败 E 和未知字段事实；在授权项目内由单一写入者校验完整对象后原子替换，发现并发更新先合并。新的语义变化应说明原因，每次执行必须追加独立 E。

阶段简报应让用户读懂目标、有效依据、失败或缺证、介入点和接入范围；反馈可以编辑、保存、复制。复制不等于发送，客户端不主动控制代理。JSON 能解码、文档完成、当前证据满足与用户独立验收分别报告。

## 长期历史与核验预算

从 0.2.0-preview.5 起，JSON 导入和编码后的监督计划分别限制为 64 MiB（之前为 8 MiB），达到 90% 时提示容量；超限提示实际字节数并保留已有资料。生产者可紧凑序列化、原子替换，但这不能保证无限增长的账本长期可装入。不要删除旧失败换取导入成功。

核验在相同的 1024 文件、单文件 4 MiB、累计 32 MiB 预算内，优先读取各测试用例最新执行候选。并列时间全部保留；同一用例存在未知时间时不能擅自挑选成功。随后核验其他历史，展示顺序保持原顺序；超预算的来源明确不可核验。当前候选自身过大或用例过多时仍可能耗尽预算，这不是完整归档或无限容量支持。

客户端不自动生成或裁剪当前投影。单独提供投影时应保留完整账本，明确范围与遗漏原因，并保证需求、任务、用例、问题、产物和执行引用闭合。特别是产物关联被省略时必须保留未验说明；投影可解析或局部通过不代表完整历史已核验。完整分片归档及公共投影格式仍需单独设计，不能以临时项目脚本当作产品已支持。

问题闭环对关联 T 与问题的 A 交集逐一要求 `A.requiredLevel == E.level`，同时要求唯一最新有效执行严格晚于修复。E 有效通过本身不足以证明问题闭环。界面会区分层级不符、先后时间、非最新或证据无效等拒绝原因；任务「记录为已完成」仍只是声明。

### 按执行单独核验

preview.5 提供 `DevFlowEvidence inspect-execution <包路径> <执行ID>`，原生入口为「测试与验收 → 执行证据 → 单独核验」。使用同样的证据判定规则和独立的有限读取预算，不受其他历史执行已耗预算影响。结果仅针对所选计划和本次读取的文件，不产生项目验收或问题关闭结论；未知ID报错。历史合同、源码或日志变化仍显示过期或缺证，不能重写旧摘要消除问题。

原生单独核验固定打开时的计划快照，刷新不会改变这份报告的范围；重新打开会再次读取。普通全量监督仍优先各用例最新候选，分页和单独核验不删除历史。可以保留完整、不可变的包及对应证据根作为归档，按普通JSON单独导入/核验；目前没有自动分片、跨归档合并或无限容量承诺。

### 执行结果、命令退出与核验状态的显示

从preview.6起，客户端分别显示记录结果、实际退出码和证据核验状态。`unknown + 非零退出 + 未知计数` 显示橙色「核验未通过 · 非零退出」，保留「记录结果：未知」并提示核对命令约定与原始日志。记录明确failed或失败计数大于0时显示红色失败记录/计数；passed与非零退出并存时提示冲突。执行卡片与单独核验弹窗使用相同展示逻辑。

这只是显示语义修正：机器state=failed、validPass=false、最新候选选择和问题闭环规则不变。exitCode=3没有特殊含义或放行规则；不根据日志中的自定义文字自动推断通过。未知计数不当零。聚合failed的中文标签为「核验未通过」，不表示整个产品已证实运行失败。
