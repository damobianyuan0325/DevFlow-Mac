# DevFlow

原生 macOS 项目过程管理与监督客户端。把 AI 辅助开发中的需求、研发、测试、缺陷、决策和交付关联起来，让已有历史与持续新增记录都能回查。

当前版本是 **0.2.0 本地预览**。应用使用 SwiftUI/AppKit 和 Foundation，无第三方运行依赖；当前预览打包面向 Apple Silicon。它只读用户选择的本地资料，不调用外部模型、不上传项目、不自动调度或控制开发代理。

## 开始使用

需要 macOS 14+ 与 Swift 5.9+ 工具链。在仓库根目录运行：

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/DevFlow.app
```

测试脚本执行独立的 Swift 检查程序；构建脚本生成 `dist/DevFlow.app` 并核验本地 ad-hoc 签名。macOS 15.1、Swift 6.0.2、Apple Silicon 是开发阶段实际使用过的环境；其他系统和架构仍需要各自验证。构建目标不等于兼容性认证。

首次可点“查看复盘样本”，对应首页的“先看看教学复盘样本”。内置内容是明确标注的**合成教学记录**，演示需求、失败、修复和缺证的阅读方式，不代表真实项目或真实测试已经发生。

使用“导入项目资料”选择 Markdown 资料目录、单个 Markdown 文件或 DevFlow JSON 包。按类型、搜索和日期查看记录，检查关联、原文摘录及来源限制；反馈可编辑、保存和复制，由用户带回原开发聊天。

## 当前能力

- **项目与历史**：只读导入、来源查看、已知事件日期筛选、未知日期提示、历史修订保留及本地持久化。读取失败保留最后成功读取的内容。
- **统一监督工作台**：schemaVersion=2 包组织原话、拆解、验收、任务、测试设计、每次执行、问题与交付；schemaVersion=1 历史资料继续支持。
- **明确接入公开动作**：手动选择本地 Codex JSONL，单独导入或为项目关联最多 8 个会话。查看支持格式中的公开进展、命令、文件变更、工具调用及结果；未接入、截断和未展开内容保留提示。
- **证据适用性**：分开显示测试设计、历史结果和当前核对状态，检查验收合同、源码及日志身份、层级和实际计数。修复声明与修复后有效复验分开。
- **手动介入**：阶段简报列出已有依据、缺口及介入对象；反馈支持编辑、保存和复制。复制不表示发送、验收或解决问题。
- **前台读取**：当前项目每 15 秒读取，也可手动刷新、暂停自动读取或停用某个会话并保留此前内容。暂停资料读取不会暂停代理。

客户端只依据已提供的资料核对，不内置 AI 自动拆解，不推断隐藏思考，也不从记录条数计算整体质量分、费用或虚构进度。摘要一致不证明业务预期充分或日志不可伪造。

## 让开发代理参与

两个随仓库提供的技能均可独立使用，可复制完整技能目录或让代理直接阅读其中的说明：

| 用途 | 入口 |
| --- | --- |
| 从一句话需求记录原话、拆解、真实动作与执行证据，生成本地监督包 | [接入指南](docs/agent-quickstart.md) · [devflow-record](skills/devflow-record/SKILL.md) |
| 核对 DevFlow 反馈，补证据或修复，真实复验并回写已有包 | [问题处理指南](docs/agent-resolution.md) · [devflow-resolve](skills/devflow-resolve/SKILL.md) |

`gated-delivery` 是用户或环境显式选择的可选研发适配，不是运行 DevFlow 或使用这两个技能的前置依赖。技能文件不会自动安装到其他代理，客户端也不会自动调用技能、发送任务或启动后台工作。

`DevFlowEvidence` 当前通过本仓库源码构建，提供只读的 `contracts` 与 `inspect`；预览 ZIP 不附带该 CLI。构建和使用方式见 [证据工具指南](docs/agent-quickstart.md#获取实际可用的证据工具)。`inspect` 退出 0 只表示报告生成成功，仍要读取具体状态、有效通过标记和警告。

## 数据与分发

默认工作区在 `~/Library/Application Support/DevFlow/workspace.json`，前一版备份保存在同目录。可通过 `--workspace` 指定隔离工作区；原工作区损坏时拒绝静默覆盖。导出 JSON 包含原文摘录，分享前应检查具体内容，详见 [隐私说明](docs/PRIVACY.md)。

本地预览打包命令为 `LC_ALL=C bash scripts/package-preview.sh`，生成应用 ZIP、说明和 SHA-256，已有同名输出时拒绝覆盖。应用包不含用户工作区或原项目目录。当前没有 Developer ID 发行签名、Apple 公证、自动升级或独立下载环境的完整验证；源码托管与应用正式发行是不同事项。

更多资料：[产品范围](docs/PRODUCT.md) · [路线与验收](docs/ROADMAP.md) · [试用与分发](docs/RELEASE.md) · [更新记录](docs/CHANGELOG.md) · [监督协议](docs/supervision-protocol.md) · [贡献指南](CONTRIBUTING.md) · [许可证](LICENSE)。
