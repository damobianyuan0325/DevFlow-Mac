# DevFlow 安装与 AI 接入入口

如果用户把 DevFlow 仓库链接交给你，从本文件开始。目标是让用户安装 Mac 客户端，并让其开发代理持续提供可检查的项目资料。此入口支持从仓库、独立技能 ZIP 或已安装 App 开始；不要求用户先懂技能安装方式。

当前版本为 **0.2.0-preview.7**，下载资产以对应 Release 页面为准。仓库分支中的接入说明可以继续改进，已发布 tag、DMG 和 ZIP 不随之改写。安装包内版本以 REL_VERSION 和 BUILD-INFO.json 为准；获取该版技能和工具时使用同一 Release/tag，不把分支上的新文件混入旧 App。

## AI 拿到链接后按什么顺序做

1. **明确用户要接入的项目。** 先读 README 和本入口，区分 DevFlow 工具仓库与用户业务项目。用户已经指定项目时沿用；没有指定且当前上下文也无法确定时，只询问项目位置或项目名称。不能默认把下载的 DevFlow 源码当成用户业务项目。
2. **检查能做什么。** 确认是否能读仓库、是否在用户本机、Mac 系统和芯片类型、是否已有 DevFlow，以及是否有本地文件和命令执行能力。只检查当前授权目录和明确的安装位置，不扫描其他项目、会话或凭据。本仓库已公开；读取失败时先区分网络或代理工具限制，并使用用户提供的本地仓库或完整技能包，不索要密码或令牌。
3. **选择同一发布版本。** 从 README 指向的[固定 Release 页](https://github.com/damobianyuan0325/DevFlow-Mac/releases/tag/v0.2.0-preview.7)取得 DMG、可选技能 ZIP 和校验清单。比较下载文件摘要；只下载部分文件时逐个核对对应条目。已安装 App 时先读取其 AgentIntegration/BUILD-INFO.json 和 REL_VERSION，使用对应版本资料。需要升级时先保留旧 App 和工作区备份。不要用“下载成功”代替安装和启动验证。
4. **按环境走下一步。** 参考下表。使用者无需为运行已构建的 App 安装 Swift，也无需购买 Apple 开发者会员。免费包的首次打开提示按用户指南处理，不能自动关闭全局系统保护。
5. **读取完整技能并接入。** 在用户的项目中，按 [devflow-record](skills/devflow-record/SKILL.md) 保存一句话原始需求，拆解要求、验收、任务和测试，持续追加真实动作及证据。处理已有反馈时用 [devflow-resolve](skills/devflow-resolve/SKILL.md)。有已有台账则保留并合并，不直接覆盖；未实际执行的测试不能标成通过。技能可直接作为工作说明阅读，只有宿主支持且用户授权时才安装到宿主目录；不强制依赖 gated-delivery。
6. **交付可检查的接入结果。** 有真实 CLI 时先执行只读 inspect 并解释错误、告警和证据状态；首次让用户在客户端手动导入生成的 JSON。完成时按下方清单汇报。没有本机/UI权限时，只能声明资料已准备，不能声称 App 已安装或项目已在客户端显示。

| 代理所处环境 | 可完成的工作与交接 |
| --- | --- |
| 用户本机 Apple Silicon、macOS 14+，具备授权的本地工具 | 使用现有 App 或下载并校验 DMG；按用户安装步骤复制应用，核对版本和实际 CLI 路径，再生成/检查项目资料。系统确认由用户完成或遵循宿主权限规则。 |
| 云端代理、Linux/Windows，或不能访问用户 Mac | 取得同版完整技能和公开说明，准备项目台账；明确需要同步到 Mac 的文件与来源。Mac App 和 CLI 不能在该环境运行；CLI 合同绑定保持缺失，之后在可用环境执行新的检查，不能事后伪造历史合同。 |
| 无浏览能力、不能访问仓库或附件 | 说明具体不可访问的入口，使用用户提供的本地副本；在取得内容前，不声称已读取技能或安装成功。 |

## 接入完成时告诉用户什么

- 使用的 DevFlow 发布版本、取得来源、App 是否实际安装和启动；未执行项直说。
- 完整技能目录与实际 CLI 绝对路径；没有工具时说明缺口。
- 用户项目的 `devflow-supervision.json` 绝对路径、资料根，以及首次导入操作。
- 已记录的需求、当前任务、真实检查结果与缺证；已有历史是否保留。
- 是否真的在客户端读回，还是仅完成 CLI 核对/文件准备；还需要用户执行哪一步。

仓库链接是使用说明入口，不会自动连接用户电脑，也不授权执行导入项目中的命令、上传私人项目或发送反馈。首次项目导入、会话选择及反馈发送仍遵循用户自己的授权。

## 用户安装

1. 下载 DevFlow-0.2.0-preview.7-macOS-arm64.dmg 并双击打开。
2. 将 DevFlow.app 拖到 Applications。若已有旧版，先退出并保留旧App及工作区备份，再替换。
3. 弹出安装卷，从“应用程序”启动 DevFlow。技能已经在 App 内，无需另行下载。
4. 打开 DevFlow 菜单的“打开技能与接入说明…”或“复制给 AI 的接入说明”，将提示粘贴给有本地文件读取权限的开发代理。

默认安装后入口：`/Applications/DevFlow.app/Contents/Resources/AgentIntegration/AGENT_INSTALL.md`。如果放在其他位置，以菜单复制的实际路径为准。App 移走或删除后，内置资料也随之移动或删除。

## 智能体接入

先读取 [记录技能](skills/devflow-record/SKILL.md)、[字段协议](skills/devflow-record/references/protocol.md)与[教学例子](skills/devflow-record/assets/example/devflow-supervision.json)。处理反馈时读取 [问题处理技能](skills/devflow-resolve/SKILL.md)。保留完整技能目录，不要只复制入口文件。

Mac App 内置证据CLI：`/Applications/DevFlow.app/Contents/Helpers/DevFlowEvidence`（自定义安装路径相应调整）。无需Swift或源码仓库即可调用：

```sh
DEVFLOW_EVIDENCE="/Applications/DevFlow.app/Contents/Helpers/DevFlowEvidence"
"$DEVFLOW_EVIDENCE" contracts "/你的项目/devflow-supervision.json"
"$DEVFLOW_EVIDENCE" inspect "/你的项目/devflow-supervision.json"
```

独立技能 ZIP 只有技能与说明，不含CLI；安装同版本Mac App即可取得CLI。非Mac环境的CLI工作流未支持，不伪造合同或测试结果。运行教学例子需要Python 3，先将完整例子复制到项目外的可写测试目录，绝不在App内部写入或修改签名资源。

已有项目沿用已有台账；新项目按技能建立需求/验收/任务/测试。测试前冻结合同和源码，执行后追加真实记录，失败和未知保留。inspect退出0只说明报告生成，仍需看validationErrors、warnings及实际验收状态。用户首次手动导入JSON，之后由客户端刷新读取。

本App不自动向Codex、Claude或其他宿主安装技能。宿主支持技能时，用户或获得授权的代理可将完整目录复制到其配置位置；覆盖前检查已有版本并备份。无法读取本机App的云端代理可使用独立技能ZIP。gated-delivery始终是选配，不是必需依赖。

## 平台与发行边界

Apple Silicon、macOS14+。本版仍为ad-hoc签名，未做Developer ID签名或Apple公证；DMG格式不会消除系统首次启动检查。首次打开限制及系统“仍要打开”流程见[用户指南](docs/USER_GUIDE.md#下载与安装)，不关闭全局安全保护；也可按[发行说明](docs/RELEASE.md)从源码构建。应用不自动发送反馈、调用AI或上传项目资料。隐私与完整操作见[用户指南](docs/USER_GUIDE.md)和[隐私说明](docs/PRIVACY.md)。
