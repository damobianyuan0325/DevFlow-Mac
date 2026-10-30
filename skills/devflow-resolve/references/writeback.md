# 保留历史的回写约定

本页使没有 devflow-record 的代理也能处理**已有、合法的** DevFlow 0.2.0 包。已有记录技能可用时可复用它的更完整协议；不要把它作为安装前置条件。没有包或准确协议时先写结果文档，标记结构化回写尚未完成，不创造未经支持的字段。

## 更新前

读取并保留原包，确认资料根是包所在目录（CLI没有另设root参数）。先核对用户修改与并发写入。单一写入者在完整对象校验后原子替换；变化期间出现他人更新，重新合并，不覆盖。保留其他R/A/U/T/E、历史失败、时间、摘要和未知字段事实；当前schema不支持的自造字段不要写入。

包外层为schemaVersion=2，内层supervision.schemaVersion=1。语义图ID跨类型全局唯一；relatedIDs仅引用records中的其他动作ID。新图引用必须存在，数组即使为空也不能省略。必要的R/A/T语义变化写原因并保存旧快照，旧E合同保持原值。

## 真实动作

新增记录必填 id、kind、title、summary、status、origin、source、relatedIDs[]、limitations[]。kind 为 requirement/development/test/bug/decision/delivery；status 为 recorded/inProgress/passed/failed/open/notRun/blocked/unknown/needsReview；origin 为 document/execution/retrospective。可选 occurredAt、version、action。

source 必填 path 和 excerpt，可选 line（1开始）与 digest（完整文件字节SHA-256）。所有路径相对资料根，不使用绝对路径、`..`、符号链接或秘密文件。source可指实际日志或修复摘要；时间与摘录真实，未知省略。新修复记录 kind=development，status=recorded/passed，occurredAt 是实际修复/记录所指事件的时间，不倒推。

## 新增实际执行 E

在执行**之前**固定当前T、相关实现和检查文件；用真实 DevFlowEvidence `contracts <包路径>` 保存每T合同摘要。没有这个工具时仍可运行授权检查并记录事实，但contractDigest留缺失，不编造规范算法。已有历史E缺合同不能事后补。

执行后新增 supervision.executions 项，不能复用旧E ID：

```json
{
  "id": "E-唯一实际执行ID",
  "testCaseID": "已有T的ID",
  "command": "本次实际命令",
  "environment": "本次真实环境",
  "result": "unknown",
  "level": "unit",
  "sourceFiles": [],
  "recordIDs": [],
  "counts": null,
  "exitCode": null,
  "occurredAt": null,
  "startedAt": null,
  "finishedAt": null,
  "candidateVersion": null,
  "contractDigest": null,
  "log": null
}
```

这是字段形状示意，不是可声明通过的记录。用真实数据填充：

- result 只取 passed/failed/unknown/notRun/blocked；level 只取 unit/integration/native/runtime/release，并符合真实执行和T定义。
- sourceFiles 每项 `{path,sha256}` 是执行前冻结的相关源码与检查代码，覆盖A/T声明范围；执行后再核对变化，不能用新字节替换旧身份。
- log 为真实 SourceReference，digest是保存日志完整字节摘要；recordIDs指新建test动作。
- counts 为 total/passed/failed/skipped 实际整数，未知null。有效通过需要完整非零、分项相符、达到T.minimumPassed、无失败或跳过。只编译成功不能填1/1。
- startedAt/finishedAt/occurredAt 使用实际取得的ISO8601时刻；缺失不造。明确非零退出码不能记passed。
- candidateVersion与本次候选一致；contractDigest使用本次执行前保存值。日志、源码、合同、产物与其他工具的计划摘要不能互换。

需要新增测试时：T必填 id/title/criterionIDs[]/taskIDs[]/input/expected/level/sourcePaths[]/minimumPassed；T关联U须共享相应A，预期要独立明确。新任务U必填 id/title/criterionIDs[]/status/recordIDs[]，status=planned/inProgress/completed/blocked。任务completed不使A自动满足。

补需求时：R必填 id/title/originalText/details/assumptions[]/scope[]/outOfScope[]/recordIDs[]；A必填 id/requirementID/title/expected/requiredLevel/sourcePaths[]。保留原话，将代理判断放在details/assumptions，不替用户改写原话。

## 问题与结果

issue必填 id/title/criterionIDs[]/testCaseIDs[]/declaredClosed/blocking/fixRecordIDs[]/verificationExecutionIDs[]；可选rootCause/missedCheckCause。依据事实填写修复和漏检原因。修复记录与复验ID真实存在且覆盖对应目标；复验时间必须严格晚于修复，同时间也不算。

当前客户端关闭评估核对修复记录类型、状态、时间及最新有效复验，不独立审阅修复原件内容；不能把closed当作源码正确性保证。业务正确、检查通过、机器评估和用户验收分别记录。

回写后调用真实CLI `inspect` 并读取具体state、validPass、warnings、validationErrors；退出0仅是生成报告成功。App可能还有额外关联会话，因此须说明本次读回范围。无CLI时交付实际测试结果和“未机器读回”，不能伪造satisfied/closed。

最后用结果文档说明每个目标：未修改而核实已覆盖 / 已补真实资料 / 已修复并验证 / 仍缺证或受阻。包含新ID及原始依据；仅写“已修复”不能完成闭环。
