#!/usr/bin/env bash
# Cross-compiles Dropbear's client tools (dbclient, dropbearkey, scp)
# for Android using the NDK toolchain, and stages them as jniLibs.
#
# The binaries are named lib*.so on purpose: executables packaged as
# native libraries are extracted to the app's nativeLibraryDir
# (useLegacyPackaging), the only app-owned location Android permits
# exec() from on API 29+. The shell reaches them via aliases set up in
# the rc file TerminalSession generates.
#
# Requires ANDROID_NDK_ROOT, or ANDROID_HOME + NDK_VERSION to locate it.
set -euo pipefail

cd "$(dirname "$0")/.."

NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION:?set NDK_VERSION}}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=29
SRC="$PWD/vendor/dropbear"
JOBS="$(nproc 2>/dev/null || echo 4)"

declare -A TRIPLES=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

for abi in "${!TRIPLES[@]}"; do
    triple="${TRIPLES[$abi]}"
    build="build/dropbear/$abi"
    out="app/src/main/jniLibs/$abi"
    echo "==> dropbear for $abi ($triple$API)"

    rm -rf "$build" && mkdir -p "$build" "$out"
    cp scripts/dropbear/localoptions.h "$build/localoptions.h"
    (
        cd "$build"
        CC="$TOOLCHAIN/${triple}${API}-clang" \
        AR="$TOOLCHAIN/llvm-ar" \
        RANLIB="$TOOLCHAIN/llvm-ranlib" \
        STRIP="$TOOLCHAIN/llvm-strip" \
        "$SRC/configure" \
            --host="$triple" \
            --disable-zlib \
            --disable-syslog \
            --disable-lastlog \
            --disable-utmp --disable-utmpx \
            --disable-wtmp --disable-wtmpx \
            >configure.log 2>&1 || { tail -30 configure.log; exit 1; }
        make -j"$JOBS" PROGRAMS="dbclient dropbearkey scp" \
            >make.log 2>&1 || {
            # Parallel output buries the error; re-run serially so the
            # failure is the last thing in the log.
            echo "== parallel build failed; re-running serially =="
            make PROGRAMS="dbclient dropbearkey scp" >>make.log 2>&1 || true
            grep -n -B2 -A6 -i "error" make.log | tail -80
            exit 1
        }
    )

    "$TOOLCHAIN/llvm-strip" "$build/dbclient" "$build/dropbearkey" "$build/scp"
    cp "$build/dbclient" "$out/libdbclient.so"
    cp "$build/dropbearkey" "$out/libdropbearkey.so"
    cp "$build/scp" "$out/libscp.so"
done

echo "done: $(find app/src/main/jniLibs -name 'lib*.so' | sort)"
