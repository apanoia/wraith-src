#!/usr/bin/env bash
# Cross-compiles the Ghostty core (Zig) for Android ABIs.
#
# Output: core/prebuilt/<abi>/libghostty-android-core.a, which
# app/src/main/cpp/CMakeLists.txt links into the JNI library.
#
# Requires Zig 0.15.2 — either `zig` on PATH or `pip install ziglang==0.15.2`.
# Needs the Android NDK: Kitty graphics pulls in the wuffs C sources, which
# must compile against bionic headers (Zig bundles only the libc bindings).
set -euo pipefail

cd "$(dirname "$0")/.."

NDK_VERSION="${NDK_VERSION:-27.2.12479018}"
NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION}}"
[ -d "$NDK" ] || { echo "error: NDK not found at $NDK" >&2; exit 1; }

REQUIRED_ZIG="0.15.2"

# Prefer a `zig` on PATH, but only if it's the exact version the project
# builds with — a mismatched compiler (e.g. an older system zig) fails
# in confusing ways. Otherwise use the pinned ziglang wheel.
if command -v zig >/dev/null 2>&1 && \
   [ "$(zig version 2>/dev/null)" = "$REQUIRED_ZIG" ]; then
    ZIG=(zig)
elif python3 -c 'import ziglang' >/dev/null 2>&1 && \
     [ "$(python3 -m ziglang version 2>/dev/null)" = "$REQUIRED_ZIG" ]; then
    ZIG=(python3 -m ziglang)
else
    echo "error: Zig $REQUIRED_ZIG not found. Install it or run 'pip install ziglang==$REQUIRED_ZIG'." >&2
    exit 1
fi

OPTIMIZE="${OPTIMIZE:-ReleaseFast}"

declare -A TARGETS=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

for abi in "${!TARGETS[@]}"; do
    target="${TARGETS[$abi]}"
    echo "==> $abi ($target, $OPTIMIZE)"
    "${ZIG[@]}" build -Dtarget="$target" -Doptimize="$OPTIMIZE" -Dandroid-ndk="$NDK"
    mkdir -p "core/prebuilt/$abi"
    cp zig-out/lib/libghostty-android-core.a "core/prebuilt/$abi/"
done

echo "done: $(find core/prebuilt -name '*.a' | sort)"
