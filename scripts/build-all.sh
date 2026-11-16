#!/bin/bash
set -euo pipefail

# Full rebuild: iOS XCFramework + Android .so + regenerate Xcode project
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==============================="
echo "  Step 1: Build iOS XCFramework"
echo "==============================="
"$ROOT/scripts/build-ios.sh"

echo ""
echo "==============================="
echo "  Step 2: Build Android .so"
echo "==============================="
if command -v zig &>/dev/null && [ -d "${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk}" ]; then
    "$ROOT/scripts/build-android.sh"
else
    echo "  Skipped (Android NDK not found)"
fi

echo ""
echo "==============================="
echo "  Step 3: Regenerate Xcode project"
echo "==============================="
"$ROOT/scripts/gen-xcodeproj.sh"

echo ""
echo "=== All done ==="
