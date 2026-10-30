# 安装后给 AI 读取的入口

本文件与完整双技能随 DevFlow App 一起安装，版本以同目录 REL_VERSION 和 BUILD-INFO.json 为准。本版为 0.2.0-preview.2；技能、说明、CLI 与 App 来自同一提交。不要把不同版本的文件混用。

## 用户安装

1. 下载 DevFlow-0.2.0-preview.2-macOS-arm64.dmg 并双击打开。
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
