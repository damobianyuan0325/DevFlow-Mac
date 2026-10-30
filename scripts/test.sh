#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/swift-module-cache"
# The trusted local manifest has no package dependencies. Keep all caches local.
# Disabling SwiftPM's nested sandbox does not change the executor sandbox.
swift run --disable-sandbox --scratch-path "$TASK_ROOT/.build" --cache-path "$TASK_ROOT/.build/cache" DevFlowChecks "$@"
