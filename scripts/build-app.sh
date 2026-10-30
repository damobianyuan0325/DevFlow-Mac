#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
VERSION_PATH="$TASK_ROOT/VERSION"
if [[ ! -f "$VERSION_PATH" ]]; then
    printf '构建未完成：缺少 VERSION 文件。\n' >&2
    exit 1
fi
BUILD_VERSION="$(cat "$VERSION_PATH")"
if [[ ! "$BUILD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '构建未完成：VERSION 必须是三段数字版本号，例如 0.1.1。\n' >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/swift-module-cache"
cp "$TASK_ROOT/assets/DevFlow.png" "$TASK_ROOT/Sources/DevFlowApp/Resources/DevFlowLogo.png"
swift build --disable-sandbox -c release --scratch-path "$TASK_ROOT/.build" --cache-path "$TASK_ROOT/.build/cache"
BIN_DIR="$(swift build --disable-sandbox -c release --scratch-path "$TASK_ROOT/.build" --cache-path "$TASK_ROOT/.build/cache" --show-bin-path)"
STAGE="$TASK_ROOT/dist/.DevFlow-stage-$(date -u +%Y%m%dT%H%M%SZ)-$$.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/DevFlow" "$STAGE/Contents/MacOS/DevFlow"
cp "$TASK_ROOT/assets/DevFlow.icns" "$STAGE/Contents/Resources/DevFlow.icns"
cp "$TASK_ROOT/LICENSE" "$STAGE/Contents/Resources/LICENSE"
for resource in "$BIN_DIR"/*.bundle; do
    if [ -d "$resource" ]; then cp -R "$resource" "$STAGE/Contents/Resources/"; fi
done
cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DevFlow</string>
<key>CFBundleIdentifier</key><string>app.devflow.local</string>
<key>CFBundleName</key><string>DevFlow</string>
<key>CFBundleDisplayName</key><string>DevFlow</string>
<key>CFBundleIconFile</key><string>DevFlow.icns</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$BUILD_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$STAGE"
codesign --verify --deep --strict "$STAGE"
if [ -e "$TASK_ROOT/dist/DevFlow.app" ]; then mv "$TASK_ROOT/dist/DevFlow.app" "$TASK_ROOT/dist/DevFlow-previous-$(date -u +%Y%m%dT%H%M%SZ)-$$.app"; fi
mv "$STAGE" "$TASK_ROOT/dist/DevFlow.app"
printf 'Built %s\n' "$TASK_ROOT/dist/DevFlow.app"
