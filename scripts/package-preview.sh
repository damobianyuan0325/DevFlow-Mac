#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$TASK_ROOT/dist/DevFlow.app"
OUTPUT_ROOT="$TASK_ROOT/dist"
PACKAGE_NAME=""
RELEASE_VERSION=""

usage() {
    cat <<'USAGE'
用法：bash scripts/package-preview.sh [--output-dir 目录] [--version 发布版本] [--name 文件名前缀]

打包已经构建的 dist/DevFlow.app，不构建、不启动应用、不上传。
默认读取 REL_VERSION，例如 0.2.0-preview.1，生成：
  dist/DevFlow-0.2.0-preview.1-macOS-arm64/
  dist/DevFlow-0.2.0-preview.1-macOS-arm64.zip
  dist/DevFlow-0.2.0-preview.1-macOS-arm64.zip.sha256

发布版本的 X.Y.Z 必须等于 VERSION 及 App 的两个版本字段。
App 的 DevFlowReleaseVersion 也必须与本次发布版本完全一致。
--version    可显式指定；必须与 REL_VERSION 完全一致。
--output-dir 输出父目录；相对路径以调用目录为准，不接受符号链接路径。
--name       可覆盖默认文件名前缀，仅允许字母、数字、点、短横线和下划线。
--help       显示本说明。

仅打包已有 ad-hoc App、已跟踪公开文档白名单、双技能和许可证。
拒绝同名产物、符号链接、额外技能文件及断开的离线 Markdown 链接。
需要 Python 3 标准库和本地 Git；不会执行教学例子，不提供 CLI 二进制。
USAGE
}

fail() { printf '打包未完成：%s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -ge 2 && -n "$2" ]] || fail "--output-dir 需要目录。"
            OUTPUT_ROOT="$2"; shift 2 ;;
        --version)
            [[ $# -ge 2 && -n "$2" ]] || fail "--version 需要发布版本。"
            RELEASE_VERSION="$2"; shift 2 ;;
        --name)
            [[ $# -ge 2 && -n "$2" ]] || fail "--name 需要文件名前缀。"
            PACKAGE_NAME="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "未知参数：$1；使用 --help 查看用法。" ;;
    esac
done

# Shared code reads only the explicit tracked whitelist; it never runs the examples.
PACKAGE_METADATA="$(python3 -B - "$TASK_ROOT" "$RELEASE_VERSION" "$OUTPUT_ROOT" "$PACKAGE_NAME" <<'PY'
import importlib.util
from pathlib import Path
import sys
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("devflow_packaging", root / "scripts/package-agent-skills.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    release, app_version = module.versions(root, sys.argv[2] or None)
    module.output_paths(Path(sys.argv[3]), sys.argv[4] or f"DevFlow-{release}-macOS-arm64")
    print(release)
    print(app_version)
except (OSError, ValueError, UnicodeError) as exc:
    print(f"Version/output validation refused: {exc}", file=sys.stderr)
    sys.exit(1)
PY
)" || fail "发布版本或输出路径校验失败。"
RELEASE_VERSION="${PACKAGE_METADATA%%$'\n'*}"
EXPECTED_APP_VERSION="${PACKAGE_METADATA#*$'\n'}"
EXPECTED_SOURCE_REVISION="$(git -C "$TASK_ROOT" rev-parse --verify HEAD)" || fail "无法读取本次源码提交。"
[[ -n "$PACKAGE_NAME" ]] || PACKAGE_NAME="DevFlow-${RELEASE_VERSION}-macOS-arm64"

[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "缺少实际 dist/DevFlow.app，请先完成本地构建。"
DISALLOWED="$(/usr/bin/find "$APP_PATH" \( -type l -o -name .git -o -name evidence -o -name local-only -o -name .env -o -name '.env.*' -o -name '*.jsonl' -o -name __pycache__ -o -name workspace.json -o -name workspace.json.backup -o \( -name '*.app' ! -path "$APP_PATH" \) \) -print -quit)"
[[ -z "$DISALLOWED" ]] || fail "应用内发现不应打包的项目：$DISALLOWED"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" || fail "无法读取应用版本。"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")" || fail "无法读取应用构建版本。"
APP_RELEASE="$(/usr/libexec/PlistBuddy -c 'Print :DevFlowReleaseVersion' "$APP_PATH/Contents/Info.plist")" || fail "App 未绑定发布版本，请按当前 REL_VERSION 重新构建。"
APP_SOURCE_REVISION="$(/usr/libexec/PlistBuddy -c 'Print :DevFlowSourceRevision' "$APP_PATH/Contents/Info.plist")" || fail "App 未绑定源码提交，请从冻结提交重新构建。"
[[ "$APP_VERSION" == "$EXPECTED_APP_VERSION" && "$APP_BUILD" == "$EXPECTED_APP_VERSION" ]] || fail "App 的版本与 VERSION/REL_VERSION 不匹配。"
[[ "$APP_RELEASE" == "$RELEASE_VERSION" ]] || fail "App 的 DevFlowReleaseVersion 与本次发布不匹配。"
[[ "$APP_SOURCE_REVISION" == "$EXPECTED_SOURCE_REVISION" ]] || fail "App 的 DevFlowSourceRevision 与本次源码提交不匹配。"

EXECUTABLE="$APP_PATH/Contents/MacOS/DevFlow"
[[ -f "$EXECUTABLE" && ! -L "$EXECUTABLE" ]] || fail "应用主程序不存在或不是普通文件。"
[[ "$(/usr/bin/lipo -archs "$EXECUTABLE")" == "arm64" ]] || fail "只接受 arm64 构建；本脚本不会生成 Universal 包。"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1)"
case "$SIGNATURE_INFO" in
    *Signature=adhoc*) ;;
    *) fail "仅接受现有 ad-hoc 本地预览包；发行签名需单独安排。" ;;
esac

PACKAGE_DIR="$(python3 -B - "$TASK_ROOT" "$OUTPUT_ROOT" "$PACKAGE_NAME" "$RELEASE_VERSION" "$EXPECTED_SOURCE_REVISION" <<'PY'
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("devflow_packaging", root / "scripts/package-agent-skills.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.public_payload(root, sys.argv[4])
    folder = module.reserve_output(Path(sys.argv[2]), sys.argv[3])
    module.stage_public_files(root, folder, sys.argv[4])
    if json.loads((folder / "BUILD-INFO.json").read_text())["sourceCommit"] != sys.argv[5]:
        raise ValueError("Source commit changed while preparing the package")
    print(folder)
except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError) as exc:
    print(f"Public package preparation refused: {exc}", file=sys.stderr)
    sys.exit(1)
PY
)" || fail "公开资料或输出目录校验失败；已有内容未覆盖，可能保留本次未完成目录。"
trap 'status=$?; if [[ $status -ne 0 ]]; then printf "预览包未完成；本次目录保留供检查：%s\n请使用新的输出目录重试。\n" "$PACKAGE_DIR" >&2; fi' EXIT
/usr/bin/ditto "$APP_PATH" "$PACKAGE_DIR/DevFlow.app"
cat > "$PACKAGE_DIR/试用说明.txt" <<README
DevFlow ${RELEASE_VERSION} — App ${APP_VERSION}，macOS arm64 本地预览版

适用于 Apple Silicon Mac，构建最低目标 macOS 14，不是 Universal 包。
从 docs/USER_GUIDE.md 开始，查看首次启动、导入合成样例和手动反馈流程。
两技能的离线入口见 SKILLS_README.md；需要时将完整技能目录交给开发代理。

应用仅有 ad-hoc 本地签名，没有 Developer ID 发行签名或 Apple 公证。
下载后 macOS 可能阻止启动；不要关闭系统安全保护，限制见 docs/RELEASE.md。
本包不提供自动升级，也不会自动上传资料、调用技能或发送反馈。

默认工作区：~/Library/Application Support/DevFlow/workspace.json
同目录保留 workspace.json.backup。导出与剪贴板可能含原文，分享前自行检查。
详细边界见 docs/PRIVACY.md；版本规则见 docs/VERSIONING.md。

包内含 App、LICENSE、公开文档白名单及两个完整技能目录。
不含私人台账、原始会话、工作区、原始仓库或验收 evidence。
DevFlowEvidence CLI 未随包提供，须按 docs/agent-quickstart.md 从源码构建。
教学示例未在打包期间运行；其内容不代表真实项目或业务验收结果。
README

/usr/bin/codesign --verify --deep --strict --verbose=2 "$PACKAGE_DIR/DevFlow.app"
for field in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$field" "$PACKAGE_DIR/DevFlow.app/Contents/Info.plist")" == "$EXPECTED_APP_VERSION" ]] || fail "复制后的 App 版本发生变化。"
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :DevFlowReleaseVersion' "$PACKAGE_DIR/DevFlow.app/Contents/Info.plist")" == "$RELEASE_VERSION" ]] || fail "复制后的发布版本发生变化。"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :DevFlowSourceRevision' "$PACKAGE_DIR/DevFlow.app/Contents/Info.plist")" == "$EXPECTED_SOURCE_REVISION" ]] || fail "复制后的源码提交发生变化。"
python3 -B - "$TASK_ROOT" "$PACKAGE_DIR" <<'PY'
import importlib.util
from pathlib import Path
import sys
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("devflow_packaging", root / "scripts/package-agent-skills.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
archive, checksum = module.write_archive(Path(sys.argv[2]))
print(f"本地预览目录：{sys.argv[2]}\n压缩包：{archive}\nSHA-256：{checksum}")
PY
printf '签名：已有 ad-hoc 签名核验通过；未做 Developer ID 签名、Apple 公证或上传。\n'
