# 让新的 AI 代理接入 DevFlow

DevFlow 通过**本地 JSON 文件**接收项目资料，不提供 HTTP 接口或云 API。开发代理负责留下需求拆解、任务、测试和修复证据；Mac 客户端只读展示、关联并核对这些资料。

## 给代理的一句话

把下面这段提示词与技能目录一起交给新的代理，将方括号替换为你的需求：

> 请使用我提供的 devflow-record 技能，先阅读 SKILL.md 及其引用资料，为当前项目接入 DevFlow；我的需求是“[一句话需求]”。由你保留原话并拆解需求、假设、验收、任务和测试，维护项目根目录的 devflow-supervision.json；开发中记录真实变化，测试前冻结合同与源码身份，执行后追加独立证据，保留失败和未知，最后告诉我应导入哪个文件、资料根在哪里、哪些结果仍缺证。反馈由我手动带回原开发聊天。

技能入口是 [skills/devflow-record/SKILL.md](../skills/devflow-record/SKILL.md)，字段和证据规则见 [监督协议](supervision-protocol.md)。

- **宿主支持 SKILL.md 技能**：复制整个 `skills/devflow-record/` 目录到该宿主支持的位置，保留相对目录结构，再按宿主方式选择 `devflow-record`。只复制 `SKILL.md` 会漏掉模板、引用资料和示例脚本。
- **宿主不支持技能机制**：把完整目录交给代理，要求它直接阅读 `SKILL.md` 及其相对引用。无需假装已安装技能；文件内容仍可作为工作说明使用。

不同宿主的技能位置和加载方式不同。本仓库不提供统一的全局安装命令，也不会自动把技能安装到其他代理。

## 从首次接入到客户端读回

1. **代理生成资料**：保留用户原话，由代理完成 R（需求）、A（验收）、U（任务）、T（测试设计）拆解，写入项目根目录的 `devflow-supervision.json`。首次尚未运行的测试不预填 E（实际执行），缺失字段保持未知。已有项目沿用稳定 ID，保留需求变化与失败记录。
2. **用户首次导入**：在 DevFlow 选择“导入项目资料”，选择该 JSON。包位于项目根时，相对来源路径默认从这里解析；移动过包或来源不可用时，使用“关联原始资料”选择真实资料根。客户端不会替代理运行包中的命令。
3. **开发中持续留痕**：代理在需求变化、任务完成、失败与修复等节点更新资料。实际动作可由用户通过“关联开发会话到此项目”手选本地 Codex JSONL 补充；这不是全部代理与工具的自动接入。
4. **测试前冻结，执行后追加**：代理先固定输入、预期、层级和必要源码范围，保存本次合同摘要及被测文件身份；再执行已授权的检查，追加新的 E，记录实际命令、环境、时间、结果、计数和日志。旧执行不覆盖，未知时间与计数不补造，旧合同摘要不能事后重算冒充执行前冻结。
5. **回到客户端核查**：当前项目被选中且应用位于前台时，每 15 秒读取一次资料，也可手动“刷新记录”。查看需求→任务→测试→执行，以及问题的修复声明和有效复验是否一致；从具体缺证或问题生成草稿，编辑、保存、复制，再由你粘贴回原开发聊天。

“暂停资料刷新”只暂停自动读取，手动刷新仍可使用，不会暂停 Agent。复制草稿不等于发送或解决问题。没有新记录也不能据此判断 Agent 是否运行或卡住。

## 获取实际可用的证据工具

当前 `DevFlowEvidence` 是**仓库源码中的 macOS 辅助工具**，提供 `contracts` 和 `inspect` 两个命令。需要 macOS 14+、Swift 5.9+ 工具链；已验证环境为 Apple Silicon。本指南不声称它是已发布的跨平台 CLI。

当前预览 ZIP **不包含这个辅助 CLI**。已持有源码仓库的用户可在本机构建；下面的仓库路径应替换为真实绝对路径：

```sh
cd "/你的绝对路径/DevFlow"
DEVFLOW_REPO="$(pwd -P)"
export CLANG_MODULE_CACHE_PATH="$DEVFLOW_REPO/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$DEVFLOW_REPO/.build/swift-module-cache"

swift build --disable-sandbox -c release --product DevFlowEvidence \
  --scratch-path "$DEVFLOW_REPO/.build" \
  --cache-path "$DEVFLOW_REPO/.build/cache"

DEVFLOW_BIN_DIR="$(swift build --disable-sandbox -c release \
  --scratch-path "$DEVFLOW_REPO/.build" \
  --cache-path "$DEVFLOW_REPO/.build/cache" --show-bin-path)"
DEVFLOW_EVIDENCE="$DEVFLOW_BIN_DIR/DevFlowEvidence"
```

`DEVFLOW_EVIDENCE` 此时是实际构建出的绝对路径；不要假设系统已经有名为 `devflow` 的命令。换一个终端或代理环境时，重新提供这个真实路径。

使用绝对路径读取你的项目包：

```sh
"$DEVFLOW_EVIDENCE" contracts "/你的绝对路径/项目/devflow-supervision.json"
"$DEVFLOW_EVIDENCE" inspect "/你的绝对路径/项目/devflow-supervision.json"
```

- `contracts` 输出各 T 对应的合同摘要。代理应在本次测试前保存这份输出，并把相应摘要写入之后新增 E 的 `contractDigest`；不是对整个 JSON 随便计算一个 SHA256。不要用今天的摘要补写历史执行。
- `inspect` 输出当前证据评估，不执行测试或资料中的命令。**退出码为 0 只表示成功生成报告，不代表需求通过**；仍须查看 `validationErrors`、各项 `state`、`validPass` 和原因。
- 合同摘要只绑定声明的要求；源码和日志摘要只核对字节身份，都不能单独证明业务预期充分或记录真实。

如果暂时没有可用 CLI，代理仍可记录需求、任务、真实执行和原始日志；没有执行前合同绑定就保持缺失，不能手编摘要或宣称已经满足证据要求。DevFlow 会按实际缺口展示未验证。该流程没有提供远端服务地址。

## 先用干净示例走一遍

技能自带 [干净示例目录](../skills/devflow-record/assets/example) 和 [示例运行器](../skills/devflow-record/scripts/run_example.py)。**示例原件只读使用**：先复制到独立目录，再运行，不能直接在技能目录生成证据。以下命令沿用上面已设置的仓库与 CLI 绝对路径：

```sh
DEVFLOW_EXAMPLE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devflow-example.XXXXXX")"
cp -R "$DEVFLOW_REPO/skills/devflow-record/assets/example/." "$DEVFLOW_EXAMPLE_DIR/"

python3 "$DEVFLOW_REPO/skills/devflow-record/scripts/run_example.py" \
  --project "$DEVFLOW_EXAMPLE_DIR" \
  --evidence-cli "$DEVFLOW_EVIDENCE"
```

按运行器输出找到副本中的监督包，再在客户端导入并查看证据链。示例结果只验证示例自己的范围，不是你的项目或整个 DevFlow 已验收；技能目录和原示例不应产生运行证据。

## 接入范围

当前客户端没有内置模型自动理解需求，也没有云同步、自动反馈发送或主动 Agent 控制。它只能展示已提供的语义台账与明确接入的公开记录；其他会话、未接入子代理内部动作、隐藏推理，以及批量脚本未独立记录的步骤都不能宣称完整可见。分享资料包前检查其中的真实摘录；接入技能本身不授权公开上传项目或会话。
