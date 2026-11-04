#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/swift-module-cache"
swift build --disable-sandbox --scratch-path "$TASK_ROOT/.build" --cache-path "$TASK_ROOT/.build/cache" --target DevFlowCore
BIN_DIR="$(swift build --disable-sandbox --scratch-path "$TASK_ROOT/.build" --cache-path "$TASK_ROOT/.build/cache" --show-bin-path)"
swiftc -parse-as-library -I "$BIN_DIR/Modules" Sources/DevFlowApp/AppStore.swift Tests/DevFlowAppTests/RefreshChecks.swift "$BIN_DIR"/DevFlowCore.build/*.swift.o -o "$BIN_DIR/DevFlowAppStateChecks"
"$BIN_DIR/DevFlowAppStateChecks"
