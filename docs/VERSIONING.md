# 版本、分支与发布标识

当前源码构建标识为 **0.2.0-preview.6**，App数字版本保持0.2.0。本次源码版本与已发布下载版本分开：preview.6安装包尚未上传GitHub，下文的preview.3是仍可下载的固定版本。

当前 GitHub Release 采用 **`v0.2.0-preview.3`**，标记为 pre-release。应用数字版本为 **`0.2.0`**，仓库以 MIT 许可证公开，发布资产可公开下载。开源及公开下载不等于应用已完成正式签名、公证或稳定性验证。

## 版本来源

| 标识 | 本版值 | 用途 |
| --- | --- | --- |
| `VERSION` | `0.2.0` | App 的数字版本和构建版本 |
| `REL_VERSION` | `0.2.0-preview.6` | 预览发布版本、文件名和发布说明 |
| Git tag | `v0.2.0-preview.3` | 精确定位发布源码的不可移动标签 |
| GitHub Release | `v0.2.0-preview.3` | 对应同名 tag，必须标记 pre-release |
| 应用 DMG | `DevFlow-0.2.0-preview.3-macOS-arm64.dmg` | Apple Silicon 预览应用及随包资料 |
| 技能 ZIP | `DevFlow-agent-skills-0.2.0-preview.3.zip` | 两技能及配套文档，便于独立交给代理 |
| 下载摘要清单 | `SHA256SUMS.txt` | 对应本次上传的DMG与技能ZIP |

版本文件位于仓库根目录：[VERSION](../VERSION)、[REL_VERSION](../REL_VERSION)。`REL_VERSION` 的基础数字部分必须与 `VERSION` 一致；构建和打包时不能靠手工重命名掩盖不一致。

App 数字版本用于 macOS 元数据；预览序号区分同一数字版本下的不同发布候选。构建后的 `DevFlowReleaseVersion` 保存发布标识，“关于 DevFlow”显示该预览版本。应用的发布标识与包名应共同保留，不能只凭 `0.2.0` 就认定DMG与技能ZIP 字节相同。

## 分支规则

- **`main`**：集成分支，接受后续开发，不代表某个历史 Release 的固定状态。
- **`codex/release/0.2`**：0.2 系列维护分支，承载该系列预览修复与发布准备。分支可向前推进；查看具体版本时仍应使用 tag。
- **`v0.2.0-preview.3`**：固定 tag，指向这次 Release 的精确提交。发布说明、源码归档和构建资产应与该提交对应。

发布 tag 一旦创建并用于交付，不能移动、覆盖或删除后重建来替换同名版本。需要修复源码、资源或产物时，创建新的预览版本，例如后续 `0.2.0-preview.7`，保留旧版本及其已知问题。发布说明可以补充已知限制，但不能用修改文字掩盖资产替换。

预览序号递增不代表自动变为稳定版。转为正式版前应明确验证范围、兼容性、签名、公证与升级条件，见 [发布指南](RELEASE.md)。

## 版本历史

| 版本 | 定位 | GitHub tag/Release |
| --- | --- | --- |
| `0.1.0` | 初始本地研发预览，历史行为见更新记录 | 不补造 tag 或 Release |
| `0.1.1` | 单会话接入与导入语义修复的本地研发版本 | 不补造 tag 或 Release |
| `0.2.0-preview.1` | GitHub 预览，ZIP 分发 | 固定v0.2.0-preview.1 |
| `0.2.0-preview.2` | DMG 分发，App 内置双技能与 CLI | 固定 `v0.2.0-preview.2` |
| `0.2.0-preview.6` | 执行结果与核验状态展示修正，当前源码版本 | 尚未发布下载资产 |
| `0.2.0-preview.5` | 完整账本容量与单独历史核验 | 尚未发布下载资产 |
| `0.2.0-preview.4` | 分页与交互优化源码版本，安装包尚未上传GitHub | 源码标签 `v0.2.0-preview.4`，不等于已有Release资产 |
| `0.2.0-preview.3` | 当前 GitHub 预发布，App 数字版本 `0.2.0` | 固定标识 `v0.2.0-preview.3`；实际发布状态见对应页面 |

[更新记录](CHANGELOG.md) 保留早期本地研发历史。版本文本出现在历史文档中不证明曾存在 Git tag、远端 Release 或可下载的同名资产。

## 对应与核验

使用者从 [固定 Release 页](https://github.com/damobianyuan0325/DevFlow-Mac/releases/tag/v0.2.0-preview.3) 取得资产及摘要。GitHub 自动提供的 Source code archives 对应 tag 源码，与应用 DMG、技能 ZIP 分开；它们不会自动成为已构建应用。

从源码复现时，应先取得目标 tag 的源码，再检查 `VERSION`、`REL_VERSION` 与发布说明。用自己的工具链构建仍可能得到不同二进制字节；不能把自行构建文件的摘要冒充已下载 Release 资产摘要。

维护者在创建 Release 前，应固定提交、验证版本一致性、完成相关真实检查、记录产物摘要，再将精确 tag 与该批资产关联。自动化测试、原生 UI、签名完整性、独立安装及发布上传是不同验证层，缺一层就如实注明；上传成功不会补齐未执行的检查。
