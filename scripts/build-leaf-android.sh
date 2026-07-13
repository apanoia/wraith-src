#!/usr/bin/env bash
# Cross-compiles the leaf markdown viewer (Rust) for Android and stages it as
# jniLibs. leaf is a ratatui/crossterm TUI; its only C dependency is Oniguruma
# (via syntect), which the NDK compiles. TLS is rustls (no OpenSSL). The result
# is a bionic-native binary, shipped as lib*.so (exec-allowed on API 29+) and
# reached via a shell alias set up in TerminalSession's rc.
#
# Requires the Rust toolchain (cargo/rustup) and the Android NDK.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="$ROOT/vendor/leaf"
NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION:-27.2.12479018}}"
TOOLS="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=29

declare -A TARGETS=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

# Strip symbols at link to keep the binary small; -C link-arg adds 16 KB
# page-size alignment (Android 15 / Play requirement).
export RUSTFLAGS="-C strip=symbols -C link-arg=-Wl,-z,max-page-size=16384"

cd "$SRC"
for abi in "${!TARGETS[@]}"; do
    target="${TARGETS[$abi]}"
    rustup target add "$target" >/dev/null 2>&1 || true

    cc="$TOOLS/${target}${API}-clang"
    us="${target//-/_}"                 # aarch64_linux_android
    uc="$(echo "$us" | tr 'a-z' 'A-Z')" # AARCH64_LINUX_ANDROID
    export "CARGO_TARGET_${uc}_LINKER=$cc"
    export "CC_${us}=$cc"          # onig_sys (cc crate) uses the NDK clang
    export "AR_${us}=$TOOLS/llvm-ar"
    export "CFLAGS_${us}=--target=${target}${API}"

    echo "==> $abi ($target)"
    cargo build --release --target "$target"
    out="$ROOT/app/src/main/jniLibs/$abi/libleaf.so"
    cp "target/$target/release/leaf" "$out"
    echo "done: $out ($(du -h "$out" | cut -f1))"
done
