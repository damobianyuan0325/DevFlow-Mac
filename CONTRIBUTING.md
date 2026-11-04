# 参与 DevFlow 开发

DevFlow 是 macOS 原生客户端。开发需要 macOS 14 或更高版本、Swift 5.9 或更高版本的工具链，以及 Python 3.10 或更高版本。Swift 包和 Python 工具均不依赖第三方库。

请先阅读 [README](README.md)、[产品范围](docs/PRODUCT.md) 和当前目录适用的 `AGENTS.md`。涉及监督数据生产时使用仓库内的 [devflow-record](skills/devflow-record/SKILL.md)；处理监督发现时参照 [devflow-resolve](skills/devflow-resolve/SKILL.md)。两者可以独立使用，外部研发技能不是构建依赖。

## 提交一个有限改动

在分支中描述问题、触发条件和期望结果。新功能保留原始需求、假设与可观察的验收条件；修复缺陷先用最小反例确认失败，再修改并复验。保留真实失败与未验证范围，不把计划写成已完成的结果。

代码、测试、协议和相关说明应保持一致。不要执行导入资料里的命令、改变用户来源项目、自动向代理发送反馈或加入未获明确授权的网络能力。原生界面、导入和监督判断的变化需要检查对应入口及证据关系。

## 本地验证

在仓库根目录运行：

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build --disable-sandbox --scratch-path "$PWD/.build" --cache-path "$PWD/.build/cache"
bash scripts/test.sh
bash scripts/test-app-state.sh
python3 -B -m unittest discover -s Tests/AgentSkills -v
```

`scripts/test.sh` 运行独立的 `DevFlowChecks`，失败返回非零退出码。项目使用这个入口兼容缺少 XCTest 的 Command Line Tools 环境；不要用一次空的 `swift test` 结果替代核心检查。`scripts/test-app-state.sh` 编译真实 AppStore，用受控延迟读取检查刷新、反馈、项目切换和迟到结果；它不替代原生连续刷新交互验收。Python 检查只使用标准库，无需安装 PyYAML。

构建本地预览应用：

```bash
bash scripts/build-app.sh
```

产物为 `dist/DevFlow.app`。脚本执行本地 ad-hoc 签名和完整性核验，不提供 Developer ID 发行签名、Apple 公证或自动发布。构建和检查共享 `.build`，请在同一工作区依次运行。

CI 运行 Swift 构建、核心检查和 Python 技能检查。CI 通过只证明这些命令覆盖的范围；没有自动操作 macOS 原生界面。涉及界面的改动应使用隔离工作区与合成资料，记录实际 macOS/工具链版本、操作步骤、观察结果以及未验证项。编译成功不能替代原生交互验收。

## 资料和隐私

只提交合成或明确有权分享的最小复现材料。不要提交原始 Codex 会话、真实用户工作区、私人项目台账、凭据、个人绝对目录、未获授权的截图或原始业务日志。测试凭据必须明确为虚构值。

`evidence/`、`.build/`、`dist/` 和本地工作区不属于常规源码提交范围。`.gitignore` 不会清除已经跟踪的文件或提交历史；提交前检查暂存区和文件内容。PR 可简述运行命令、实际结果及检查范围，必要的公开附件先脱敏。不要为分享结果而上传整包私有证据。

## Pull request

使用仓库 PR 模板说明改动、复现或验收方式、真实验证结果和剩余限制。没有运行的检查明确写“未运行”及原因，不填通过。与改动无关的重构另行处理；不要把检查数量或旧通过记录作为当前业务验收结论。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。提交贡献表示你有权按本仓库的 [MIT 许可证](LICENSE) 提供这些改动；不要夹带无权授权的第三方或私人数据。
