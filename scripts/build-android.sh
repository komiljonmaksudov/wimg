#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBWIMG="$ROOT/libwimg"
BUILD_DIR="$LIBWIMG/build-android"
JNILIBS="$ROOT/wimg-android/app/src/main/jniLibs"

# Detect NDK
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  NDK="$ANDROID_NDK_HOME"
elif [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
  NDK="$(ls -d "$ANDROID_HOME/ndk/"* 2>/dev/null | sort -V | tail -1)"
elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
  NDK="$(ls -d "$HOME/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)"
else
  echo "Error: Android NDK not found. Set ANDROID_NDK_HOME or install via Android Studio."
  echo "  brew install --cask android-studio"
  echo "  Then: Android Studio → Settings → SDK Manager → SDK Tools → NDK"
  exit 1
fi

echo "Using NDK: $NDK"

# NDK sysroot for Zig cross-compilation
# NDK prebuilt dir uses darwin-x86_64 even on Apple Silicon
PREBUILT_DIR="$(ls -d "$NDK/toolchains/llvm/prebuilt/"* 2>/dev/null | head -1)"
if [ -z "$PREBUILT_DIR" ]; then
  echo "Error: NDK prebuilt toolchain not found in $NDK/toolchains/llvm/prebuilt/"
  exit 1
fi
SYSROOT="$PREBUILT_DIR/sysroot"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/arm64-v8a"

echo "=== Building libwimg.so for aarch64-linux-android ==="
cd "$LIBWIMG"

# Create a libc configuration file for Zig pointing to NDK sysroot
cat > "$BUILD_DIR/android-libc.txt" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/aarch64-linux-android
crt_dir=$SYSROOT/usr/lib/aarch64-linux-android/29
msvc_lib_dir=
kernel32_lib_dir=
cc_dir=$SYSROOT/usr/lib/aarch64-linux-android/29
darwin_sdk_dir=
EOF

zig build \
  -Dtarget=aarch64-linux-android \
  -Dshared=true \
  --release=small \
  -Dlibc="$BUILD_DIR/android-libc.txt"

cp zig-out/lib/libwimg.so "$BUILD_DIR/arm64-v8a/libwimg.so"

echo "=== Build complete ==="
ls -lh "$BUILD_DIR/arm64-v8a/libwimg.so"
file "$BUILD_DIR/arm64-v8a/libwimg.so"

# Copy to Android project jniLibs if it exists
if [ -d "$ROOT/wimg-android/app/src/main" ]; then
  mkdir -p "$JNILIBS/arm64-v8a"
  cp "$BUILD_DIR/arm64-v8a/libwimg.so" "$JNILIBS/arm64-v8a/libwimg.so"
  echo "=== Copied to wimg-android/app/src/main/jniLibs/arm64-v8a/ ==="
fi
