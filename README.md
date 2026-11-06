# DevFlow

原生 macOS 项目过程管理与监督客户端。把 AI 辅助开发中的需求、研发、测试、缺陷、决策和交付关联起来，让已有历史与持续新增记录都能回查。

**当前源码版本：`0.2.0-preview.8`（Codex 会话读取上限提升）；GitHub 可下载预发布版本：`v0.2.0-preview.8`；App 数字版本：`0.2.0`。** 当前面向 Apple Silicon、macOS 14+，仍是 ad-hoc 本地签名预览，没有 Developer ID 发行签名或 Apple 公证。本项目采用 **[MIT 许可证](LICENSE) 开源**，源码、技能和 Release 安装包均可公开获取，无需申请仓库访问权限。

## 把仓库链接交给 AI

可以把下面这句话直接发给你的开发智能体：

> 请阅读 https://github.com/damobianyuan0325/DevFlow-Mac 的 README 和 AGENT_INSTALL.md，帮我安装 DevFlow，并把我指定的项目接入研发过程监督。先检查你能访问的环境和现有安装，按文档选择同一发布版本，保留已有项目记录；需要我在 Mac 上操作的步骤请明确告诉我。

AI 的统一入口是 [AGENT_INSTALL.md](AGENT_INSTALL.md)：先判断运行环境，再选择安装包或完整技能，生成项目资料并核对结果。已经安装 App 的用户，也可以从 DevFlow 菜单复制实际的本机接入路径。云端 AI 可以准备接入资料，但不能仅凭链接操作你的 Mac。

可直接把仓库链接交给支持浏览或读取 GitHub 的 AI。若代理受网络或工具限制无法读取，可提供完整技能 ZIP 或本地仓库；不需要为本项目提供 GitHub 密码或访问令牌。

## 开始使用

无需 Swift 的使用者可从 [固定版本下载页](https://github.com/damobianyuan0325/DevFlow-Mac/releases/tag/v0.2.0-preview.8) 取得 `DevFlow-0.2.0-preview.8-macOS-arm64.dmg`，按 [用户指南](docs/USER_GUIDE.md) 打开 DMG 并将 `DevFlow.app` 复制到“应用程序”。下载无需申请权限；文件名与摘要以对应 Release 页为准。

首次启动可能受到 macOS 对未公证应用的限制，不能保证下载后直接打开。免费预览版无需购买 Apple 开发者会员。确认来源及摘要后，可按用户指南使用系统“仍要打开”对单个应用放行；无需关闭全局系统安全保护。

源码构建需要 macOS 14+ 与 Swift 5.9+ 工具链。在仓库根目录运行：

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/DevFlow.app
```

首次点击“先看看教学复盘样本”，或从侧栏“打开复盘样本”开始。样本是明确标注的合成教学内容，不是实际项目执行证明。导入自己的资料后，可查看原文、历史与关联，编辑反馈并手动带回开发聊天。

## 当前能力

- 只读导入 Markdown 目录、单文件和 DevFlow JSON，支持搜索、类型与事件日期筛选、历史修订和本地持久化。
- schemaVersion=2 监督包组织原话、需求拆解、验收、任务、测试设计、每次执行、问题与交付；schemaVersion=1 继续支持。
- 手选本地 Codex JSONL，单独导入或为项目关联最多 8 个会话，查看支持格式中的公开动作及来源缺口。
- 区分测试设计、历史结果和当前适用性，核对合同、源码、日志、层级与实际计数；修复声明和有效复验分开。
- 提供阶段简报、可编辑并保存的手动反馈；前台当前项目每 15 秒读取，可手动刷新、暂停或停用单个会话。

应用无第三方运行依赖，不联网调用模型、不上传项目、不自动调度或控制代理。复制反馈不表示发送，暂停读取不暂停代理；摘要一致和记录条数也不能证明业务质量。

## AI 代理技能

[devflow-record](skills/devflow-record/SKILL.md) 用于保留一句话需求、拆解、真实动作与执行证据，生成本地监督包；[devflow-resolve](skills/devflow-resolve/SKILL.md) 用于核对反馈、补证或修复、复验和回写。两者均可独立使用，`gated-delivery` 是显式选择的可选研发适配。

也可直接下载 [Mac 安装 DMG](https://github.com/damobianyuan0325/DevFlow-Mac/releases/download/v0.2.0-preview.8/DevFlow-0.2.0-preview.8-macOS-arm64.dmg) 或 [完整技能 ZIP](https://github.com/damobianyuan0325/DevFlow-Mac/releases/download/v0.2.0-preview.8/DevFlow-agent-skills-0.2.0-preview.8.zip)。

Release 的技能包文件名为 `DevFlow-agent-skills-0.2.0-preview.8.zip`，保留完整技能目录及配套资料；宿主安装方式见 [接入指南](docs/agent-quickstart.md) 与 [问题处理指南](docs/agent-resolution.md)。客户端不会自动安装或调用技能。

Mac App 内置完整双技能、离线说明和 `DevFlowEvidence` CLI；拖拽安装后全部保留。菜单可打开资料或复制给AI的接入提示，见[安装与代理接入](AGENT_INSTALL.md)。独立技能ZIP不含CLI。它提供只读 `contracts` 和 `inspect`，具体步骤见 [证据工具指南](docs/agent-quickstart.md#获取实际可用的证据工具)。

## 版本对应

| 用途 | 版本或分支 | 说明 |
| --- | --- | --- |
| 集成开发 | `main` | 持续变化，不等同于某个已发布包 |
| 0.2 系列维护 | `codex/release/0.2` | 维护该系列的预览修复 |
| 当前 GitHub Release/tag | `v0.2.0-preview.8` | Pre-release，固定 tag 对应精确源码提交 |
| 当前源码构建版本 | [REL_VERSION](REL_VERSION)：`0.2.0-preview.8` | 用于预览资产命名和 tag |
| App 数字版本 | [VERSION](VERSION)：`0.2.0` | macOS 应用内显示的数字版本 |
| 早期本地研发 | `0.1.0`、`0.1.1` | 保留更新历史，不补造 GitHub Release/tag |

Tag 创建后不移动；新产物或修复使用新预览版本。分支、tag、资产和核验方式见 [版本规则](docs/VERSIONING.md)。

## 文档地图

| 需要什么 | 文档 |
| --- | --- |
| 下载、安装、首次使用、备份、升级、卸载及常见问题 | [用户指南](docs/USER_GUIDE.md) |
| 当前版本的内容、资产和限制 | [v0.2.0-preview.8 发布说明](docs/releases/v0.2.0-preview.8.md) |
| 构建、打包、检查与分发条件 | [发布指南](docs/RELEASE.md) |
| 版本、分支、tag 与更新历史 | [版本规则](docs/VERSIONING.md) · [更新记录](docs/CHANGELOG.md) |
| 功能与后续范围 | [产品](docs/PRODUCT.md) · [路线与验收](docs/ROADMAP.md) |
| AI 技能与数据协议 | [接入指南](docs/agent-quickstart.md) · [问题处理](docs/agent-resolution.md) · [监督协议](docs/supervision-protocol.md) |
| 数据、安全、贡献与许可 | [隐私](docs/PRIVACY.md) · [安全](SECURITY.md) · [贡献](CONTRIBUTING.md) · [许可证](LICENSE) |

源码 preview.8 的内容及验证边界见 [版本说明](docs/releases/v0.2.0-preview.8.md)。资产与发布状态以对应 Release 页为准。
