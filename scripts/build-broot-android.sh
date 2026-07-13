#!/usr/bin/env bash
# Cross-compiles the broot file browser (Rust) for Android and stages it as
# jniLibs. broot uses fancy-regex (no Oniguruma); its only C dependency is
# libgit2 (via git2, network features off), built vendored by the NDK. The
# result is a bionic-native binary, shipped as lib*.so and reached via the
# `broot`/`br` aliases set up in TerminalSession's rc.
#
# Requires the Rust toolchain (cargo/rustup) and the Android NDK.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="$ROOT/vendor/broot"
NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION:-27.2.12479018}}"
TOOLS="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=29

declare -A TARGETS=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

# -C link-arg: 16 KB page-size alignment (Android 15 / Play requirement).
export RUSTFLAGS="-C strip=symbols -C link-arg=-Wl,-z,max-page-size=16384"

cd "$SRC"
for abi in "${!TARGETS[@]}"; do
    target="${TARGETS[$abi]}"
    rustup target add "$target" >/dev/null 2>&1 || true

    cc="$TOOLS/${target}${API}-clang"
    us="${target//-/_}"
    uc="$(echo "$us" | tr 'a-z' 'A-Z')"
    export "CARGO_TARGET_${uc}_LINKER=$cc"
    export "CC_${us}=$cc"          # libgit2-sys (cc crate) uses the NDK clang
    export "AR_${us}=$TOOLS/llvm-ar"
    export "CFLAGS_${us}=--target=${target}${API}"

    echo "==> $abi ($target)"
    cargo build --release --target "$target"
    out="$ROOT/app/src/main/jniLibs/$abi/libbroot.so"
    cp "target/$target/release/broot" "$out"
    echo "done: $out ($(du -h "$out" | cut -f1))"
done
