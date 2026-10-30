#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
REL="$(cat "$ROOT/REL_VERSION")"
TARGET="$OUT/DevFlow-$REL-macOS-arm64.dmg"
[[ ! -e "$TARGET" && ! -L "$TARGET" && ! -e "$TARGET.sha256" && ! -L "$TARGET.sha256" ]] || { echo 'Refusing to overwrite an existing DMG' >&2; exit 1; }
# Reuse strict frozen-source, version, signature and whitelist validation.
mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"
LC_ALL=C bash "$ROOT/scripts/package-preview.sh" --output-dir "$STAGING/payload"
VOL="$STAGING/volume"
mkdir "$VOL"
ditto "$STAGING/payload/DevFlow-$REL-macOS-arm64/DevFlow.app" "$VOL/DevFlow.app"
ln -s /Applications "$VOL/Applications"
ln -s DevFlow.app/Contents/Resources/AgentIntegration "$VOL/技能与接入说明"
cat > "$VOL/先读我.txt" <<TXT
DevFlow $REL — Apple Silicon / macOS 14+
将 DevFlow.app 拖到 Applications。App 内包含双技能、安装说明和证据CLI。
弹出安装卷后，从应用程序启动；菜单可打开技能或复制给AI的接入提示。
升级前退出旧App并备份工作区，保留旧App以便恢复。
本包为 ad-hoc 预览，未 Developer ID 签名或 Apple 公证。
系统阻止时不要关闭安全保护；详细说明见“技能与接入说明/AGENT_INSTALL.md”。
TXT
hdiutil create -volname "DevFlow $REL" -srcfolder "$VOL" -format UDZO -fs HFS+ "$TARGET"
hdiutil verify "$TARGET"
LC_ALL=C shasum -a 256 "$TARGET" > "$TARGET.sha256"
echo "Created $TARGET"
