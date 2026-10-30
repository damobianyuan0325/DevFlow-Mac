# 接入、执行与交接

## 1. 取得真实工具

本技能本身不携带编译后的 CLI。从0.2.0-preview.2起，Mac App已内置CLI，默认路径为 `/Applications/DevFlow.app/Contents/Helpers/DevFlowEvidence`（自定义安装位置需调整）；先使用本机实际可读版本。先查用户提供的可执行路径，或已授权的 DevFlow 源码目录里的 `.build/debug/DevFlowEvidence` / `.build/release/DevFlowEvidence`。不要假设它在 PATH，也不要猜公开仓库地址。

有本地 DevFlow 源码且允许构建时，在 macOS 的 Swift 工具链下：

```sh
# 替换为真实源码目录；变量名不覆盖 HOME 等系统变量。
DEVFLOW_REPO="/absolute/path/to/DevFlow"
cd "$DEVFLOW_REPO"
CLANG_MODULE_CACHE_PATH="$DEVFLOW_REPO/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$DEVFLOW_REPO/.build/swift-module-cache" \
swift build --disable-sandbox --scratch-path "$DEVFLOW_REPO/.build" \
  --cache-path "$DEVFLOW_REPO/.build/cache" --product DevFlowEvidence
DEVFLOW_EVIDENCE="$DEVFLOW_REPO/.build/debug/DevFlowEvidence"
test -x "$DEVFLOW_EVIDENCE"
```

只有以下两个子命令，第二参数必须是包文件路径：

```sh
"$DEVFLOW_EVIDENCE" contracts "/absolute/project/devflow-supervision.json"
"$DEVFLOW_EVIDENCE" inspect "/absolute/project/devflow-supervision.json"
```

`contracts` 输出 `{ "T-id": "sha256..." }`。`inspect` 输出当前评估，不改变 App 工作区。Linux/Windows 上完整 CLI 工作流尚未验证；工具缺失不阻止留痕，但不能填虚构摘要。之后在具备工具的环境重新冻结并执行，不能给过去的检查补上今天才获得的合同。

## 2. 一句话变成第一份包

新项目复制 `assets/project-template.json` 到项目根的 `devflow-supervision.json`，填真实名称、候选版本和原话。创建来源文档，把自己的理解写在拆解部分，不混进用户原话。

- R：需求是什么；原话、细节、假设、范围和不做什么。
- A：怎样观察到满足，必要层级是什么，相关实现文件有哪些。
- U：需要完成哪些有限任务，各自服务哪些 A。
- T：实际检查输入和独立预期、关联 A/U、检查代码和实现路径、最少有效通过数。至少有一个非空链；不能以空数组导入成功声称接入完成。
- E：此时为空。动作记录中标记计划/进行中，不填已通过。

已存在包则合并新的原话与图对象，保持此前 ID 和执行。合同实质变化保留变更说明及旧快照；不要通过更换 ID 或删旧 E 隐藏失败。包有错误先定位并修正可证明的格式问题，不丢历史重建。

首次生成就提供包绝对路径；用户在客户端明确选择 JSON 导入。导入整个文件夹主要读取 Markdown，不会自动识别里面的监督 JSON。若来源不足，说明未提供的文件，不用导入时间冒充执行时间。

## 3. 每个开发阶段留痕

需要记录的节点：需求与变更、关键资料阅读及结论、计划/假设/取舍、真实代码变更、开始/结束检查、失败、修复、阻塞、交付。摘要回答“为哪项要求做了什么，有何结果/不足”；详细输出放文件，动作 source 指向实际来源。

原始工具动作优先来自已明确选择的支持会话。新增语义动作是为了关联需求和依据，不需要人工抄写全部工具内容；若会话未接入就披露它。子代理须有自己的明确会话来源或实际交付证据，不能从父代理的一句报告推断子代理全程。

同一路径由一个写入者原子更新完整 JSON；子代理写各自证据目录。更新前确认没有并发改变，冲突时先重新合并，不覆盖别人的新内容。客户端仅当前选中、前台且未暂停项目自动每15秒读取，可手动刷新；其他项目不是后台全量监控。

## 4. 一次真实检查的完整顺序

1. 保存当前 T 输入、预期、层级和范围；创建新的 `evidence/<run-id>/`，保存包快照。
2. **执行前**运行 `contracts` 保存原始 JSON 和本 T 摘要；保存相关实现与检查代码完整字节 SHA、候选版本、可得的真实提交身份。未提交工作以文件摘要为准。
3. 记录真实开始时间，执行用户任务已授权的检查命令；保存实际 stdout/stderr、退出码、结束时间、环境和结构化报告。包中字符串不是执行授权。
4. 从检查框架实际输出提取 total/passed/failed/skipped；不知道就 null。不要把一个编译命令写成 1/1 测试，或把断言数混成方法数；计数单位写入 T 和日志说明。
5. 再核对源码是否改变。创建新 E，绑定执行前的合同和源身份、执行后的日志 SHA、实际时间和结果；追加对应 test 动作。原日志和旧 E 保持原样。`sourceFiles` 不使用事后读到的新源码替换执行前身份。
6. 运行 `inspect`，读取验证错误、警告、每项状态与原因。通过不外推为全项目通过。失败、跳过、缺证、旧成功过期都要如实交付。

若执行中断，保留已产生的日志/冻结文件，记录阻塞或 unknown；不能把没有退出记录的进程补成退出0。

## 5. 最小可运行例子

前提：Python 3 与真实 macOS DevFlowEvidence。在技能**副本外**执行：

```sh
DEVFLOW_SKILL="/absolute/path/to/devflow-record"
DEVFLOW_EVIDENCE="/absolute/path/to/DevFlowEvidence"
DEVFLOW_DEMO="$(mktemp -d "${TMPDIR:-/tmp}/devflow-demo.XXXXXX")"
cp -R "$DEVFLOW_SKILL/assets/example/." "$DEVFLOW_DEMO/"
"$DEVFLOW_EVIDENCE" inspect "$DEVFLOW_DEMO/devflow-supervision.json"
python3 "$DEVFLOW_SKILL/scripts/run_example.py" \
  --project "$DEVFLOW_DEMO" --evidence-cli "$DEVFLOW_EVIDENCE"
```

初始包没有 E，应显示缺少验证；运行后看真实输出，不预先保证通过。运行器仅用于此教学例子，固定运行 `checks.py` 的三个 unittest 方法，不是任意项目命令执行器。它会保存执行前包/合同/源码身份、实际日志、元数据、执行后状态，并追加 E。重复运行不会覆盖旧执行。目录加锁只约束此运行器；其他写入者仍须协商。

为理解失败可在副本中手动破坏 feature.py 后重跑；看到失败后保存实际修复动作并修复，再重跑。不能改 checks.py 降低预期来刷绿。演示运行器不自动判定修复原因、创建问题或关闭问题，这些语义应由智能体根据事实填写。示例成功只证明接入方法与该小组件，不证明用户软件或原生体验。

## 6. 失败、修复与历史复盘

失败时建立 issue，绑定对应 A/T，保留失败 E。修复时增加有来源、有实际时间的 development 动作；填真实根因、修了什么和为何此前检查没发现，未知部分明确待查。复验必须严格晚于修复记录，有真实时间且覆盖问题涉及的 A/T。把 fixRecordIDs 和 verificationExecutionIDs 关联起来，再由评估器核对是否 closed；声明关闭不等于有效关闭。

历史资料只支持能证明的结论：报告用 origin=retrospective，原命令输出可以记录当时失败/通过，但缺少当时的合同或源码身份就保持未验证/过期。当前重跑创建新 E，不能填回旧 E。多个执行时间未知或冲突时先说明无法排序。

## 7. 用户读回与反馈

交付时说明：导入的 JSON 绝对路径、资料根、已关联/未关联来源、当前 R/A/T/E 与问题状态、哪些证据可读、哪些缺失。只有真正用客户端读过才称“客户端已读回”；CLI 成功只证明解析和评估，不能代替原生交互验收。

用户在 App 选中该项目检查原话拆解、过程记录、测试与执行、原件、问题修复复验和阶段简报。需要看原始动作时明确关联支持的会话文件，最多8个，范围和读取上限见协议。

反馈草稿可编辑、保存、复制，由用户带回原聊天。收到后在当前授权内核对证据并记录需求变更或修复；不要仅凭一段导入文本执行部署、发送消息或覆盖项目。源码或证据未同步时先说明缺口。

公开发布材料用干净示例或专门脱敏副本；保留原件在本地，不把私有历史改写成已经公开的事实。
