# DevFlow 0.2.0 本地字段协议

本文件随技能分发。所有列出的非可选字段必须出现，空数组写 `[]`，不能依赖 Swift 初始化器默认值。字段使用下面的英文原值；不要添加未经支持的自定义顶层/动作字段。

## 包与动作记录

外层：`schemaVersion: 2`、`name: string`、`records: ActivityRecord[]`、`supervision: Plan`。旧 schema 1 无监督图，只作普通历史。

ActivityRecord 必填：

| 字段 | 取值 |
| --- | --- |
| id, title, summary | 非空稳定 ID、标题、真实摘要 |
| kind | requirement / development / test / bug / decision / delivery |
| status | recorded / inProgress / passed / failed / open / notRun / blocked / unknown / needsReview |
| origin | document / execution / retrospective |
| source | SourceReference，必填 path 与 excerpt |
| relatedIDs | 同包其他动作记录 ID 数组，不能自引用、重复或引用 R/A/T |
| limitations | 字符串数组，写明缺证和可见范围 |

可选：`occurredAt`（实际 ISO8601 时间，未知省略或 null）、`version`、`action`。action 必填 `kind`（request / progress / toolCall / toolResult / command / fileChange / agentReport / other），可选 `callID`。它是对实际动作的归类，不会自动产生工具动作。

SourceReference：必填 `path: string`、`excerpt: string`；可选 `line: int`（从 1 开始）、`digest: string`（完整文件字节的 SHA-256）。excerpt 是真实摘录；digest 缺失或原件缺失不能声明原件已核实。记录原件查看支持文档/图片；源码本身用下方 sourceFiles 核验，动作来源可指向真实变更摘要、差分或日志文本。

## 监督图

Plan 必填 `schemaVersion: 1`、`title`、`version`、`originalRequest`（字符串），`assumptions`、`scope`（字符串数组），以及下表七个数组，全部必填。

| 数组 | 每项必填字段 | 可选字段 |
| --- | --- | --- |
| requirements (R) | id, title, originalText, details, assumptions[], scope[], outOfScope[], recordIDs[] | 无 |
| criteria (A) | id, requirementID, title, expected, requiredLevel, sourcePaths[] | 无 |
| tasks (U) | id, title, criterionIDs[], status, recordIDs[] | 无 |
| testCases (T) | id, title, criterionIDs[], taskIDs[], input, expected, level, sourcePaths[], minimumPassed | 无 |
| executions (E) | id, testCaseID, command, environment, result, level, sourceFiles[], recordIDs[] | occurredAt, counts, log, exitCode, startedAt, finishedAt, candidateVersion, commit, contractDigest |
| issues | id, title, criterionIDs[], testCaseIDs[], declaredClosed, blocking, fixRecordIDs[], verificationExecutionIDs[] | rootCause, missedCheckCause |
| artifacts | id, title, path, executionIDs[], recordIDs[] | sha256 |

字符串字段除另外说明均为 string。`declaredClosed`、`blocking` 为 bool；`minimumPassed` 为 1…1000000 整数；`exitCode` 为实际整数。数组中的 ID 为 string；sourcePaths 为相对路径 string；assumptions/scope/outOfScope 为描述 string。`recordIDs`、`fixRecordIDs` 指向动作记录。

- U.status：planned / inProgress / completed / blocked。
- E.result：passed / failed / unknown / notRun / blocked。
- level/requiredLevel：unit / integration / native / runtime / release。
- E.sourceFiles 每项必填 `{path, sha256}`。
- E.log 为 SourceReference；证据有效通过需要可核对的日志 digest。
- E.counts 为 `{total?, passed?, failed?, skipped?}`，每个是整数或 null；未知不是 0。有效通过需要四项完整、total > 0、分项和等于总数、达到 minimumPassed、failed=0 且 skipped=0。
- E 的时间、候选版本、commit、contractDigest 是可选字符串。语法允许缺字段不代表证据充分；只填已取得的事实。

所有 R/A/U/T/E/issue/artifact ID 跨类型唯一、稳定、不含控制字符且 ≤128 UTF-8 字节。建议 `R-001/A-001/U-001/T-001/E-<时间及随机尾缀>`。动作 ID 属于独立命名空间，建议 `rec-...`。

类型化引用必须存在且无重复：A→R，U→A，T→A/U，E→T，问题→A/T/修复动作/E，产物→E/动作。T 关联的 U 要与该 T 共享 A；问题中的 T/E 也应覆盖相应 A。未接入的动作 ID 会留下缺证，不能伪造记录补齐。删除旧对象前必须考虑历史引用；通常保留旧对象并记录变更更合适。

## 路径、摘要与版本

建议包在项目根目录。所有 source.path、sourcePaths、sourceFiles.path、log.path、artifact.path 都是此根内的安全相对路径。不可用绝对路径、`..`、符号链接或秘密文件路径。CLI 根是 JSON 所在目录，没有 `--root`；GUI 的资料根绑定不会传给 CLI。

跨机器移交时连同引用的公开文件一起保留相对位置；私有来源可不移交，但须明确缺证。不要把真实会话的绝对路径写进可分享的包。

`contractDigest` 必须在该次执行之前用 **同版本 DevFlowEvidence contracts** 获得，绑定 Plan.version/原话/假设/范围和相关 R、A、U、T 语义。执行列表、动作记录关联和 U.status 不改变它；相关需求语义变化会改变它。普通 JSON 哈希不能替代规范合同摘要。

同次执行的 sourceFiles 冻结相关实现与检查代码，不要绑定会随执行追加的整个台账来制造自我过期。执行前后核对源码；变化就报告适用性不足并重验。执行完成后给真实日志完整字节摘要。只换摘要不能修复旧证据。

artifact.path 指向单个文件，例如 ZIP；`.app` 目录不能冒充一个文件摘要。摘要匹配只证明当前可读字节相符，不证明测试充分、内容真实不可伪造或安全认证。

## 当前状态与问题闭环

`inspect` 计算 satisfied / partial / failed / unverified / stale / blocked；不要把这个状态写成 E.result。

有效通过同时看合同、候选版本、源文件、日志、计数、层级和已知结果。非零 exitCode 表示核验未通过（机读 state=failed），不改写 E.result，也不能单凭此断定产品运行失败；缺少退出码不能补 0。T.level 与 E.level 对应，A 必须有 requiredLevel 对应的证据。新的失败优先于旧成功；缺失或并列时间不能凭数组顺序挑一个成功。

问题显示 open / closed / unverified，与 declaredClosed 不同。当前关闭评估核对 development 修复记录的 ID、status（recorded/passed）与时间，以及**严格晚于修复**的最新有效复验，覆盖绑定 A/T。只填 declaredClosed=true、旧成功或相等时间都不够。当前关闭评估不读取修复记录原件或校验其 digest，因此 closed 不能证明修复内容已被独立核验；代理仍应保存真实修复来源，供用户回查。再次发现相似问题时，记录 rootCause 与 missedCheckCause；未查明就保留未知。

问题有效复验另有**精确层级守卫**：对 issue.criterionIDs 与该 E 所属 T.criterionIDs 的交集，每个 A.requiredLevel 都须严格等于 E.level；任一相交标准不等，该 E 整体不计入该问题的有效复验。不是层级大小或“更高即可”，`inspect` 中的 executions.validPass、同 T 的当前评估 satisfied 或 T.level == E.level 都不足以单独证明问题可关闭；只有通过完整守卫的 E 才参与问题全部 A/T 的覆盖。

混合组件、集成、原生和运行层级的要求应在执行前分清 A 子标准、T 以及问题的实际范围，不把组件 T 的通过当作 runtime A 的问题复验。不得为求 closed 改写旧 E 层级、降低 requiredLevel 或删掉必需回归覆盖。先对照官方完整过滤条件，再以同一次 `inspect` 的 issues.state 及具体原因作结论；“缺少晚于修复的有效复验”是合并提示，不能仅据文字断定时间错误。

`inspect` 的退出码 0 仅表示成功读取并输出 JSON。必须读 `validationErrors`、`warnings`、`criteria/requirements.state`、`executions.validPass`、`issues.state` 的具体原因；不可用退出码单独验收。

## 读取上限与实际可见范围

DevFlow 0.2.0-preview.5 起 JSON 与编码后的监督计划各 ≤64 MiB（更早版本 ≤8 MiB），records ≤5000；监督图每类 ≤5000、总计 ≤20000。动作 id ≤200 字符、title ≤500、summary/excerpt 各 ≤100000 UTF-8 字节；relatedIDs ≤100，limitations ≤100（每项 ≤10000 字节）。包 name ≤200 字符。

动作来源核验：最多400文件、单个2 MiB、合计24 MiB。监督证据核验：最多1024文件、单个4 MiB、合计32 MiB。不要将大日志塞入 JSON；保留独立日志，超过预算就明确本次无法全量核验。

明确关联的 JSONL 会话最多8个；单来源读取前200 MiB（preview.8 起；preview.7 为32 MiB）、20000事件，单事件文本64000字节。截断、未知结构、隐藏推理、系统配置、密文与未接入会话均不属于完整可见内容。不要因此宣称“所有智能体所有动作已覆盖”。

### 大账本与历史单独核验（preview.5 起）

完整账本超过旧8 MiB时可原路径读取，不需删除失败、重算旧哈希或制作删历史的投影。64 MiB仍是有限上限；字节、记录和图数量边界分别生效。超过边界整包拒绝，客户端保留上次资料；本版本不自动分片或无限归档。

历史执行因全局1024文件/32 MiB核验预算未读到时，在客户端「测试与验收 → 执行证据 → 单独核验」，或用同版本CLI：

```sh
"/Applications/DevFlow.app/Contents/Helpers/DevFlowEvidence" inspect-execution /path/to/devflow-supervision.json E-ID
```

输出scope=singleExecution，只核验指定执行相对所选计划及当前文件的适用性，不输出项目验收或问题关闭结论。仍受单文件4 MiB、累计32 MiB、1024文件预算约束。退出0只是报告成功；找不到ID则报错。合同或源码已变化仍应显示过期，不重新绑定旧E。保存不可变完整包时同时保留它对应的资料根和证据；归档副本可单独选择导入及核验，不自动合并为当前通过。没有原件只能保持未知。

### 执行显示语义（preview.6 起）

客户端分别显示记录结果、退出码与核验状态。unknown与非零退出并存时，显示「核验未通过 · 非零退出」并保留未知结果；明确failed或失败计数>0仍展示失败记录。passed与非零退出并存提示冲突。机器state、validPass与问题闭环守卫不变，exit3不特殊放行。请保留真实结果、未知计数和命令约定，不能为消除颜色而改写历史E或伪造通过。
