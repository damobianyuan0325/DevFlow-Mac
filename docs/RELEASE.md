# 构建、打包与发布指南

当前 GitHub 预发布标识为 **`v0.2.0-preview.8`**，App 数字版本为 **`0.2.0`**。仓库以 MIT 许可证公开，源码、技能和安装包可直接访问，无需申请仓库权限。应用采用 ad-hoc 本地签名，尚无 Developer ID 发行签名或 Apple 公证；GitHub pre-release 不等于稳定版或已公证分发。

只需安装应用的使用者先读 [用户指南](USER_GUIDE.md)。本文件补充下载核验、源码构建、打包内容及维护者的发布检查；实际资产是否已上传以 [固定 Release 页](https://github.com/damobianyuan0325/DevFlow-Mac/releases/tag/v0.2.0-preview.8) 为准。

## 下载内容

| 资产 | 内容与用途 |
| --- | --- |
| `DevFlow-0.2.0-preview.8-macOS-arm64.dmg` | `DevFlow.app`、试用说明、完整双技能目录及公开使用文档；运行应用无需 Swift |
| `DevFlow-agent-skills-0.2.0-preview.8.zip` | 完整双技能、`SKILLS_README.md` 及公开配套说明，便于单独交给 AI 代理 |
| `SHA256SUMS.txt` | 本次DMG与技能ZIP 的 SHA-256 摘要 |
| GitHub 自动提供的 Source code archives | tag 对应源码；用于阅读或自行构建，不是应用安装包 |

App内部包含完整技能、离线说明及 `DevFlowEvidence` CLI；独立技能ZIP不含CLI。两种资产均不包含用户工作区、原始项目、私人会话或开发证据目录。技能包保留原相对目录结构，不能拆成只有 SKILL.md 的单文件。

## 检查下载文件

在同一目录保存DMG与技能ZIP 和 `SHA256SUMS.txt` 后，可在终端进入该目录运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

若只下载一个资产，可计算该文件的摘要，并与清单中同名文件那一行逐字比较：

```sh
shasum -a 256 DevFlow-0.2.0-preview.8-macOS-arm64.dmg
```

清单引用了未下载文件时，整体校验会提示缺少文件，并不单独证明已下载的另一个文件损坏。摘要不一致时不要继续使用该文件，重新核对目标版本及下载。SHA-256 说明字节是否匹配该清单，不能替代发行者身份、Developer ID 签名、公证或业务正确性验证。

下载后的安装与首次启动见 [用户指南](USER_GUIDE.md#下载与安装)。本版可能被 macOS 的未公证应用限制阻止；首次打开方式见用户指南；不要求购买开发者会员，不提供关闭全局系统保护的命令。

## 从源码构建

需要 macOS 14+ 与 Swift 5.9+ 工具链，无第三方运行依赖。开发阶段实际使用过 macOS 15.1、Swift 6.0.2、Apple Silicon；其他环境需单独验证。当前预览打包仅接受 arm64，不生成 Intel 或 Universal 产物。

取得目标 tag 的仓库源码或 GitHub Source code archive，在**源码根目录**执行以下命令；应用包 中的说明和技能不构成完整源码树：

```sh
bash scripts/test.sh
python3 -B -m unittest discover -s Tests/AgentSkills -v
bash scripts/build-app.sh
open dist/DevFlow.app
```

测试入口执行实际 Swift 断言和 Python 技能检查。构建脚本生成 `dist/DevFlow.app`，读取 `VERSION` 的数字版本及 `REL_VERSION` 的发布标识，并核验本地 ad-hoc 签名；构建与模块缓存留在仓库 `.build` 中。应用构建成功不替代原生 UI 或独立下载环境验收。

可在源码目录隔离试用工作区：

```sh
mkdir -p .build/local-preview
open -n dist/DevFlow.app --args --workspace "$PWD/.build/local-preview/workspace.json"
```

默认工作区和升级备份方法见 [用户指南](USER_GUIDE.md#备份导出与升级)。

## 单独构建证据 CLI

`DevFlowEvidence` 已内置于App的 `Contents/Helpers/DevFlowEvidence`，可直接运行。若需要自行构建，按 [代理接入指南](agent-quickstart.md#获取实际可用的证据工具) 构建并取得实际路径。

`contracts` 输出每个测试设计的规范合同摘要，供实际执行前冻结；`inspect` 只读评估指定包及本地证据，不执行测试或资料中的命令。退出 0 表示报告生成成功，应继续查看 `state`、`validPass`、`warnings`、`validationErrors` 和原因。App 另行关联的会话不自动包含在 CLI 的输入范围中。

## 本地打包

先确认根目录版本文件：`VERSION` 为 `0.2.0`，当前源码 `REL_VERSION` 为 `0.2.0-preview.8`。本节从源码打包的产物为 preview.8。应用构建完成后，在已跟踪发布文件的仓库中执行：

```sh
LC_ALL=C bash scripts/package-dmg.sh
python3 -B scripts/package-agent-skills.py --output-dir "$PWD/dist"
```

脚本读取 REL_VERSION，分别生成DMG和技能ZIP；已有同名产物拒绝覆盖。DMG脚本仅接受一个可选输出目录参数，技能脚本使用 --output-dir。DMG内部含App、Applications入口及安装说明；App内资料不会因弹出安装卷丢失。

App 打包只核验现有 arm64 应用及 ad-hoc 签名，不重新构建。两个包使用明确白名单收录已跟踪的公开文档与完整技能，避免把本地证据、工作区或其他目录整份带入。包内链接和支持文件应完整可读；以最终脚本检查和实际解包内容为准。

将DMG与技能ZIP 放在同一输出目录后，为 GitHub Release 生成合并清单：

```sh
cd dist
shasum -a 256 \
  DevFlow-0.2.0-preview.8-macOS-arm64.dmg \
  DevFlow-agent-skills-0.2.0-preview.8.zip > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

这是对本次真实产物生成摘要，不应复制另一轮包的旧摘要。脚本不会替使用者上传 Release、调用发行签名身份或提交公证。

## 版本与发布对应

`main` 用于集成，`codex/release/0.2` 维护 0.2 系列，固定 tag `v0.2.0-preview.8` 对应精确发布提交。当前版本继续标记 pre-release，仓库为 Public；开源不改变预览版的签名与验收边界。规则见 [版本管理](VERSIONING.md)，内容说明见 [本版发布说明](releases/v0.2.0-preview.8.md)。

维护者在上传前需要分别核对：

| 层级 | 要保存或检查的实际结果 |
| --- | --- |
| 源码与版本 | 精确提交、两个版本文件、App 元数据与不可移动 tag 对应 |
| 自动化检查 | 当前源码的 Swift 与技能检查输出、退出码、真实失败或跳过情况 |
| 原生应用 | 主要导入、来源查看、历史、监督、反馈、刷新与重启路径；没有执行就注明 |
| 包内容 | DMG 内 App 与技能 ZIP 的明确白名单、链接、完整技能、无私人数据，解包后文件与输入相符 |
| 签名与架构 | 当前 arm64 App 的 ad-hoc 完整性；不能写成 Developer ID 或公证通过 |
| 上传与下载 | 远端 Public 且无需认证即可读取/下载，Release 是 pre-release，tag/资产名和摘要匹配；上传成功单独记录 |

发布说明中的检查范围不是通过证明。应在实际运行后填写结果，保留失败和限制；不能以旧版本通过、检查条数或上传成功替代当前验收。Tag 一旦交付不移动，不以同名资产覆盖修复问题；需要改动时发布新预览序号。

发布后，分别核对仓库 Code 首页、无需凭据的 Git 拉取和 Release 附件下载。仓库可见性、Git 可用性与附件可下载性分别验证；任一检查失败时，记录具体入口、错误及影响。

## 正式分发前仍缺少什么

Developer ID 发行签名、Apple 公证、对应系统评估，以及独立下载/安装环境中的首次启动和兼容性验证仍需完成。自动升级和正式数据迁移策略尚未提供。当前下载包仅作受授权范围内的预览试用，保留 [隐私](PRIVACY.md)、[安全](../SECURITY.md) 和 [贡献](../CONTRIBUTING.md) 约定。


## 核对消费者实际使用的 CLI

`swift run DevFlowChecks` 不会自动重链接兄弟可执行目标 `DevFlowEvidence`；release App 构建也不更新 `.build/debug/DevFlowEvidence`。App 已更新不能作为开发脚本入口已经更新的证据。

`bash scripts/test.sh` 现在显式构建 debug CLI，并用同一合成 JSON 的小文件/10 MiB 文件核对实际二进制的合同输出一致性。独立检查已安装 App 或消费者配置路径时运行：

```sh
python3 scripts/test-cli-entrypoint.py /absolute/path/to/DevFlowEvidence
```

此检查输出实际解析路径和 SHA-256，仅证明该入口的容量与合同一致性；不代表项目验收通过。交付时分别记录消费者配置路径、解析路径、二进制摘要、构建源码提交与实际命令结果。不得仅凭 App 版本、构建目录或源码状态推断另一入口已更新。正在执行合同冻结/核验的消费者需要固定工具身份，不能在执行中途替换其 helper。
