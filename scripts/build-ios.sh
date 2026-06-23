#!/bin/bash
set -euo pipefail

# Build libwimg for iOS targets, create XCFramework, copy to wimg-ios
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBWIMG="$ROOT/libwimg"
BUILD_DIR="$LIBWIMG/build-ios"
INCLUDE_DIR="$LIBWIMG/include"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{ios,sim}

# Zig 0.16's archiver writes .a members that aren't 8-byte aligned, which
# Xcode 26's linker (ld-prime) rejects ("not 8-byte aligned ... libwimg_zcu.o").
# Re-pack with Apple's libtool, which lays members out aligned.
realign_archive() {
  local a="$1"
  local tmp
  tmp="$(mktemp -d)"
  (cd "$tmp" && ar x "$a")
  # Zig stores members with mode 0000; make them readable for libtool.
  chmod u+rw "$tmp"/*.o
  libtool -static -o "$a.aligned" "$tmp"/*.o
  mv "$a.aligned" "$a"
  rm -rf "$tmp"
}

echo "=== Building for aarch64-ios ==="
cd "$LIBWIMG"
zig build -Dtarget=aarch64-ios --release=small
cp zig-out/lib/libwimg.a "$BUILD_DIR/ios/libwimg.a"
realign_archive "$BUILD_DIR/ios/libwimg.a"

echo "=== Building for aarch64-ios-simulator ==="
zig build -Dtarget=aarch64-ios-simulator --release=small
cp zig-out/lib/libwimg.a "$BUILD_DIR/sim/libwimg.a"
realign_archive "$BUILD_DIR/sim/libwimg.a"

echo "=== Creating XCFramework ==="
rm -rf "$BUILD_DIR/libwimg.xcframework"
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/ios/libwimg.a" -headers "$INCLUDE_DIR" \
  -library "$BUILD_DIR/sim/libwimg.a" -headers "$INCLUDE_DIR" \
  -output "$BUILD_DIR/libwimg.xcframework"

# Copy to wimg-ios
IOS_FRAMEWORKS="$ROOT/wimg-ios/Frameworks"
mkdir -p "$IOS_FRAMEWORKS"
rm -rf "$IOS_FRAMEWORKS/libwimg.xcframework"
cp -R "$BUILD_DIR/libwimg.xcframework" "$IOS_FRAMEWORKS/"
echo "=== Copied to $IOS_FRAMEWORKS/libwimg.xcframework ==="

# Generate i18n runtime + catalog files (skip in CI — files are committed)
if command -v bun &>/dev/null; then
  echo "=== Generating i18n runtime files ==="
  cd "$ROOT"
  bun scripts/i18n-codegen.ts
fi
