#!/usr/bin/env bash
# Cross-compiles ghostty-icat (Go) for Android and stages it as jniLibs.
#
# ghostty-icat displays images inline via the Kitty graphics protocol. Like
# micro it's pure Go with CGO disabled, so it links fully static and needs no
# NDK. Shipped as lib*.so (exec-allowed on API 29+) and reached via a shell
# alias set up in TerminalSession's rc.
#
# Requires the Go toolchain on PATH.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="$ROOT/tools/ghostty-icat"

declare -A GOARCHES=(
    [arm64-v8a]=arm64
    [x86_64]=amd64
)

cd "$SRC"
for abi in "${!GOARCHES[@]}"; do
    out="$ROOT/app/src/main/jniLibs/$abi/libghosttyicat.so"
    echo "==> $abi (GOARCH=${GOARCHES[$abi]})"
    GOOS=linux GOARCH="${GOARCHES[$abi]}" CGO_ENABLED=0 GOFLAGS=-mod=mod \
        go build -trimpath -ldflags "-s -w" -o "$out" .
    echo "done: $out ($(du -h "$out" | cut -f1))"
done
