#!/usr/bin/env bash
# Cross-compiles the micro editor (Go) for Android and stages it as jniLibs.
#
# micro is pure Go with CGO disabled, so it links fully static and needs no
# NDK — it runs on bionic via raw syscalls. Like the other bundled tools it is
# named lib*.so so Android extracts it to nativeLibraryDir, the only app-owned
# location exec() is allowed from on API 29+. The shell reaches it via a
# symlink on PATH (see Micro.kt) so `micro` and $EDITOR both work.
#
# Requires the Go toolchain on PATH.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="$ROOT/vendor/micro"

declare -A GOARCHES=(
    [arm64-v8a]=arm64
    [x86_64]=amd64
)

cd "$SRC"
VERSION="$(git describe --tags 2>/dev/null || echo dev)"
# micro's tags are v-prefixed (v2.0.14) but its util.Version is parsed as
# semver, which rejects the leading 'v' ("Invalid character(s) found in major
# number"). Strip it so the version parses cleanly.
VERSION="${VERSION#v}"
HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GOVARS="-X github.com/zyedidia/micro/v2/internal/util.Version=$VERSION"
GOVARS="$GOVARS -X github.com/zyedidia/micro/v2/internal/util.CommitHash=$HASH"

# Embed the runtime (syntax files, help, colorschemes) — host arch.
echo "==> generating runtime"
GOFLAGS=-mod=mod go generate ./runtime

for abi in "${!GOARCHES[@]}"; do
    out="$ROOT/app/src/main/jniLibs/$abi/libmicro.so"
    echo "==> $abi (GOARCH=${GOARCHES[$abi]})"
    GOOS=linux GOARCH="${GOARCHES[$abi]}" CGO_ENABLED=0 GOFLAGS=-mod=mod \
        go build -trimpath -ldflags "-s -w $GOVARS" -o "$out" ./cmd/micro
    echo "done: $out ($(du -h "$out" | cut -f1))"
done
