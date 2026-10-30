# 可选配合 gated-delivery

仅在用户明确选择配合 gated-delivery 时读取本页。独立处理路径见 [主技能](../SKILL.md)；本适配不是主技能的前置依赖。

本页接口依据已核对的 **gated-delivery 2.3.0 仓库候选**，不表示该版本已全局安装或公开发布。每次首次使用仍须读取用户提供的真实 `SKILL.md`、相关细则、`assets/delivery-plan.example.json` 和两个脚本的 `--help`；版本或接口不一致时先记录差异，不猜参数。

## 选择与降级

项目可提供以下配置，并由调用方**显式传给 `prepare_review.py`**。配置路径参数以该脚本当前 `--help` 为准：

```json
{
  "schemaVersion": 1,
  "enabled": true,
  "development": {
    "adapter": "gated-delivery",
    "skillPath": "/absolute/path/to/gated-delivery/SKILL.md"
  }
}
```

`skillPath` 必须替换为实际文件。只有 `prepare_review.py` 读取这份显式传入的配置；配置不会安装技能、注册宿主 hook、自动触发研发或增加权限。

- **启用**：用户选择此适配后，传入启用配置，核对实际技能版本，再按下文协作。
- **停用**：不再传入此配置，或显式设置 `enabled: false`，后续不由该配置选择适配器。已有记录和执行证据保留，不改写过去采用的方法。
- **缺失或不可用**：报告技能、运行器或检查能力的具体缺口，回到当前授权的独立处理流程；能诊断、修改和留痕的部分继续。项目原本要求的门禁仍须满足，缺失时保持未运行或受阻，不能因回退而解除。

不自动安装其他版本、修改 gated-delivery 本体，或向项目/全局 `AGENTS.md` 强制加入新约定。若项目既有约定要求 gated-delivery，停用本适配配置不等于取消该约定。

## 一个研发主方法，一份需求解释

1. **本技能诊断问题**：读取反馈、当前版本及原始证据，区分实际缺陷、缺证、过期、环境阻断和需求变化。保留问题 ID、影响的 A/T、待验证假设、原失败与当前授权范围。
2. **选择研发方法**：启用时按 gated-delivery 推进有限修改、检查和必要复盘；未启用时按当前项目的方法推进。一次修复只选一种研发主方法，不重复建立两套任务队列。小而可逆的修改使用其轻量路径，不强迫创建完整机器计划。
3. **共同留痕**：复用项目已有的需求与研发台账，明确唯一写入者。DevFlow 资料呈现同一原话、解释和边界；gated 机器 JSON 只写其支持字段。2.3.0 示例机器计划有 `criteria/checks`，没有 R/U 语义字段，不能把 DevFlow 包直接交给它。
4. **显式关联**：在项目已有记录中列出 DevFlow A/T 与 gated criterion/check 的对应 ID，一对多关系逐项写明；R/U仍保留在语义台账。禁止靠相似标题、顺序或时间接近猜关系。需求变化先更新共同解释和映射，再为受影响检查重新冻结。

原日志、回执与执行历史只追加。子代理提交自己的证据，由唯一写入者合并；不让两个代理同时覆盖 `devflow-supervision.json`。同一个 gated check 不并发运行以争用最新回执指针。

## 需要机器凭据时：双冻结，一次运行，分别核对

只有在真实源码、可用运行器及必要 CLI 已就绪时才走完整绑定；缺少这些条件仍可保留真实资料，但不能伪造当前通过。

1. 保存实际 gated 机器计划及 DevFlow 包快照、明确的 A/T 映射和源码范围。**检查前**调用真实 `DevFlowEvidence contracts <包绝对路径>` 保存对应 T 的合同摘要；保留 gated 计划原字节。两套绑定各自生成，不能互相代填。
2. 由调用方明确给出本次已授权的命令和每个参数，交给 `run_check.py` 执行一次。2.3.0 运行器会要求 argv 与计划完全一致，并保存执行前后源码、输出和回执；该运行器当前要求 POSIX。计划中的命令不是额外授权。
3. 根据这次实际输出定位并核验新的不可变回执与日志，追加对应 DevFlow E及动作记录。不要臆造固定的运行目录或只信任旧 `latest` 指针。未产生执行回执、运行被拒绝或中断时如实记录，不补一个成功 E。
4. 分别运行 `check_delivery.py` 与 `DevFlowEvidence inspect`。前者核对 gated 计划及凭据，后者核对 DevFlow 当前合同与范围；保存各自结果及原因。不能为适配两种格式把同一次检查重跑两遍后当成同一次执行。

以下是 2.3.0 示例的调用形状。先把路径换为真实路径并阅读帮助；仅当项目计划实际声明 T1 的命令为所示 unittest argv，且该命令已获本次任务授权时，才使用执行行：

```sh
DEVFLOW_GATED_ROOT="/absolute/path/to/gated-delivery"
DEVFLOW_PROJECT_ROOT="/absolute/path/to/project"

python3 "$DEVFLOW_GATED_ROOT/scripts/run_check.py" --help
python3 "$DEVFLOW_GATED_ROOT/scripts/check_delivery.py" --help

python3 "$DEVFLOW_GATED_ROOT/scripts/run_check.py" \
  --root "$DEVFLOW_PROJECT_ROOT" --plan "delivery-plan.json" --check T1 \
  -- python3 -m unittest discover -s tests -v

python3 "$DEVFLOW_GATED_ROOT/scripts/check_delivery.py" \
  --root "$DEVFLOW_PROJECT_ROOT" --plan "delivery-plan.json"
```

`--root` 是实际项目根；`--plan` 是该根内的相对计划路径。调用前读取相应示例，不能只替换 ID 而遗漏真实命令、环境、报告格式或路径约定。`check_delivery.py` 只读证据、不执行计划命令；2.3.0 中结果 `PASSED` 才退出 0。DevFlow 的 `inspect` 退出 0 仅表示生成了评估报告，两者退出码语义不同。

如果 gated 运行器可用但 DevFlow CLI 不可用，可以继续授权检查并保留回执，DevFlow 的合同绑定保持缺失。之后取得 CLI 时需要重新冻结并产生新执行，不能给历史 E 补写今天的合同。

## 不可直接转换的字段

| 项目 | 处理规则 |
| --- | --- |
| `plan_sha256` / `contractDigest` | 前者是 gated 整份计划的原始字节摘要；后者是 DevFlow 每个 T 的语义合同摘要。绝不能互填或用普通 JSON 哈希替代。 |
| 源码、oracle、输出、回执摘要 | `source_before/source_after`、`oracle_snapshot`、stdout/stderr 和 receipt 各自绑定不同字节与范围。仅在同一路径、同一原始文件及范围确定时复用相应文件 SHA；不能用回执 SHA 冒充源码或合同 SHA，也不能事后重算旧源码身份。 |
| 验证层级 | gated 为 `unit/integration/ui/production`，DevFlow 为 `unit/integration/native/runtime/release`。`unit/integration` 也须核范围；`ui` 不自动等于原生 Mac 验收，`production` 不自动等于运行观察，gated 没有直接对应 `release` 的值。不能为适配而降低 A 的要求。 |
| 计数 | gated 为 `tests/failures/errors/skipped/xfail`，DevFlow 为 `total/passed/failed/skipped`。必须依据真实报告说明计数单位；不能丢掉 errors/xfail，不能在类别可能重叠时盲目相减。无法无损说明时保留原计数并让目标字段未知。`kind=command` 没有测试计数，退出 0 不能变成 1/1 测试。 |
| 时间 | 2.3.0 回执提供 `started_at` 与 `duration_seconds`，没有实际结束时间字段。不能把二者相加冒称原始结束时刻；未知结束时间留空。问题复验的先后关系仍须由真实时间证明。 |
| 总体结果 | gated `PASSED` 不直接变成 DevFlow 全部 A 满足或 issue 关闭；任务状态、工具返回、测试结果、原生验收分别记录。缺少修复时间或对应复验仍不能关闭问题。 |

逐目标归因可写成下面的形式，**仅为说明格式，不是实际执行结果**：

- `DF-A01 ↔ gated A1/T1`：本次回执 `state=passed`、`returncode=0`，`counts.tests=3` 且 failures/errors/skipped/xfail 均为 0；两份绑定及源码核查成立时，只支持该目标声明的组件层结论。
- `DF-A02`：要求原生交互，但当前只有 T1 的组件证据；保持未验证，下一步补对应原生检查，不能沿用上项的三条通过数。
- `问题 B01`：来源报告已修复，但实际修复时间或之后的对应复验缺失；保留报告和缺口，不写有效关闭。

无论采用哪种研发方法，本适配都不增加部署、破坏性操作、消息发送或公开发布权限，也不会自动修改外部技能和宿主约定。
