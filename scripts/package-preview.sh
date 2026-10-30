#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$TASK_ROOT/dist/DevFlow.app"
OUTPUT_ROOT="$TASK_ROOT/dist"
PACKAGE_NAME=""

usage() {
    cat <<'USAGE'
用法：bash scripts/package-preview.sh [--output-dir 目录] [--name 文件名前缀]

将已经构建的 dist/DevFlow.app 打成本地 arm64 预览包。
默认读取应用 Info.plist 的实际版本，生成：
  dist/DevFlow-<应用版本>-preview-macOS-arm64/
  dist/DevFlow-<应用版本>-preview-macOS-arm64.zip
  dist/DevFlow-<应用版本>-preview-macOS-arm64.zip.sha256

--output-dir  指定输出的父目录；相对路径以调用时的目录为准。
--name        指定包目录和 zip 的文件名前缀，仅允许英文字母、数字、点、短横线和下划线。
--help        显示本说明。

同名产物已存在时直接退出，不覆盖、不清理旧产物。
本脚本只核验已有 ad-hoc 签名，不重新构建、不使用签名身份、不公证、不上传。
USAGE
}

fail() { printf '打包未完成：%s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -ge 2 && -n "$2" ]] || fail "--output-dir 需要目录。"
            OUTPUT_ROOT="$2"; shift 2 ;;
        --name)
            [[ $# -ge 2 && -n "$2" ]] || fail "--name 需要文件名前缀。"
            PACKAGE_NAME="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "未知参数：$1；使用 --help 查看用法。" ;;
    esac
done

[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || fail "缺少实际 dist/DevFlow.app，请先完成本地构建。"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" || fail "无法读取应用版本。"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "应用版本必须是三段数字版本号。"
if [[ -z "$PACKAGE_NAME" ]]; then PACKAGE_NAME="DevFlow-${APP_VERSION}-preview-macOS-arm64"; fi
[[ "$PACKAGE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "文件名前缀无效。"
[[ ${#PACKAGE_NAME} -le 120 ]] || fail "文件名前缀不得超过 120 个字符。"
[[ "$OUTPUT_ROOT" != -* ]] || fail "以短横线开头的输出目录请写成绝对路径或 ./相对路径。"

/bin/mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"
PACKAGE_DIR="$OUTPUT_ROOT/$PACKAGE_NAME"
ZIP_PATH="$OUTPUT_ROOT/$PACKAGE_NAME.zip"
HASH_PATH="$ZIP_PATH.sha256"
for destination in "$PACKAGE_DIR" "$ZIP_PATH" "$HASH_PATH"; do
    [[ ! -e "$destination" && ! -L "$destination" ]] || fail "输出已存在：$destination；请改用 --name 或 --output-dir。"
done

EXECUTABLE="$APP_PATH/Contents/MacOS/DevFlow"
[[ -f "$EXECUTABLE" && ! -L "$EXECUTABLE" ]] || fail "应用主程序不存在或不是普通文件。"
[[ "$(/usr/bin/lipo -archs "$EXECUTABLE")" == "arm64" ]] || fail "只接受 arm64 构建；本脚本不会生成 Universal 包。"

for document in PRIVACY.md CHANGELOG.md; do
    [[ -f "$TASK_ROOT/docs/$document" && ! -L "$TASK_ROOT/docs/$document" ]] || fail "缺少交付文档：docs/$document"
done

# Only the explicitly named current app, license and two public-facing documents enter the package.
# A local workspace, raw repository, evidence directory or another app is never a package input.
DISALLOWED="$(/usr/bin/find "$APP_PATH" \( -type l -o -name .git -o -name evidence -o -name workspace.json -o -name workspace.json.backup -o \( -name '*.app' ! -path "$APP_PATH" \) \) -print -quit)"
[[ -z "$DISALLOWED" ]] || fail "应用内发现不应打包的项目：$DISALLOWED"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1)"
case "$SIGNATURE_INFO" in
    *Signature=adhoc*) ;;
    *) fail "此脚本仅用于现有 ad-hoc 本地预览包；请单独安排发行签名流程。" ;;
esac

# mkdir is also an exclusive reservation of this package name for concurrent invocations.
/bin/mkdir "$PACKAGE_DIR" || fail "无法创建新的包目录；未覆盖已有内容。"
trap 'status=$?; if [[ $status -ne 0 ]]; then printf "预览包未完成；本次目录保留供检查：%s\n请使用新的输出名称重试。\n" "$PACKAGE_DIR" >&2; fi' EXIT
/usr/bin/ditto "$APP_PATH" "$PACKAGE_DIR/DevFlow.app"
/bin/mkdir "$PACKAGE_DIR/docs"
/bin/cp "$TASK_ROOT/docs/PRIVACY.md" "$PACKAGE_DIR/docs/PRIVACY.md"
/bin/cp "$TASK_ROOT/docs/CHANGELOG.md" "$PACKAGE_DIR/docs/CHANGELOG.md"
/bin/cp "$TASK_ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"
cat > "$PACKAGE_DIR/试用说明.txt" <<README
DevFlow ${APP_VERSION}-preview — 本地 macOS arm64 预览版

适用：Apple Silicon Mac；构建最低目标 macOS 14。
本包不是 Universal 构建，不支持 Intel Mac。系统兼容性仍以实际验证结果为准。

开始试用
1. 解压后打开 DevFlow.app；也可自行将应用复制到“应用程序”目录。
2. 首次可打开内置合成教学复盘样本，查看历史记录、原文、关联与未验证限制。
3. 导入自己的 Markdown 资料目录或 DevFlow JSON。schemaVersion=2 的监督包提供需求、任务、测试、执行、验收与问题工作台。
4. 用“关联开发会话”把明确选择的 Codex JSONL 归入当前项目（最多8个）；也可单独接入会话。分类、搜索、历史日期及来源核对保留，读取不执行资料里的命令。
5. 编辑反馈后保存或复制，由你带回原 AI 开发聊天。复制不等于已发送或已解决。

签名与分发状态
应用使用 ad-hoc 本地构建签名，打包脚本已核验包内签名完整性。
本包没有完成 Developer ID 发行签名或 Apple 公证；本地核验不代表已满足对外发行条件。
经过下载或传输后，macOS 可能阻止启动。请勿关闭系统安全保护；公开试用应等待正式签名与公证包。
此包不提供自动升级，也不自动上传、公开或发布任何资料。

数据
默认工作区：~/Library/Application Support/DevFlow/workspace.json
前一版备份：同目录 workspace.json.backup
导出的 JSON 包含原文摘录，分享前请检查内容。移除项目不会删除原始资料。
详细数据处理和版本边界见 docs/PRIVACY.md 与 docs/CHANGELOG.md。

包内容
DevFlow.app、此说明、LICENSE 及上述两份文档。
不包含用户工作区、原始项目仓库、验收 evidence 目录或旧应用备份。
随包内置复盘样本为合成教学材料，不是真实项目记录或执行验收。
会话导入只覆盖所选文件已记录且当前格式支持的公开事件；未接入代理、加密内容与未记录步骤均不能还原。
README

/usr/bin/codesign --verify --deep --strict --verbose=2 "$PACKAGE_DIR/DevFlow.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PACKAGE_DIR/DevFlow.app/Contents/Info.plist")" == "$APP_VERSION" ]] || fail "复制后的应用版本发生变化；本次包未完成。"
for destination in "$ZIP_PATH" "$HASH_PATH"; do
    [[ ! -e "$destination" && ! -L "$destination" ]] || fail "输出在打包期间已存在：$destination"
done
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
(cd "$OUTPUT_ROOT" && /usr/bin/shasum -a 256 "$PACKAGE_NAME.zip") > "$HASH_PATH"
printf '本地预览目录：%s\n压缩包：%s\nSHA-256：%s\n' "$PACKAGE_DIR" "$ZIP_PATH" "$HASH_PATH"
printf '签名：已有 ad-hoc 签名核验通过；未做 Developer ID 签名、Apple 公证或公开发布。\n'
