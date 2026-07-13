#!/usr/bin/env bash
# Cross-compiles GNU bash for Android using the NDK toolchain, staged as
# a jniLib (libbash.so) so it can be exec()'d from nativeLibraryDir on
# API 29+ — the same trick used for the Dropbear tools. TerminalSession
# uses it as the interactive shell when present, falling back to
# /system/bin/sh otherwise.
#
# We build IN-TREE in a per-ABI copy of vendor/bash (not a VPATH build):
# bash's git tree ships an *empty* builtins/builtext.h stub that, on the
# include path of an out-of-tree build, shadows the real header that
# mkbuiltins generates — producing "undeclared identifier *_builtin"
# errors. An in-tree build regenerates that stub in place. Copying also
# keeps the vendored submodule pristine.
#
# Requires ANDROID_NDK_ROOT, or ANDROID_HOME + NDK_VERSION to locate it.
set -euo pipefail

cd "$(dirname "$0")/.."

NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION:?set NDK_VERSION}}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=29
SRC="$PWD/vendor/bash"
CACHE="$PWD/scripts/bash/config-android.cache"
JOBS="$(nproc 2>/dev/null || echo 4)"

declare -A TRIPLES=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

# bash ships generated files in-tree; a git checkout gives them arbitrary
# mtimes, so make may try to regenerate them. We only want to *suppress*
# regeneration of files needing tools we don't ship (autoconf -> configure,
# bison -> the parser). Everything else must regenerate normally — notably
# builtins/builtext.h + builtins.c, empty stubs the in-tree mkbuiltins
# rebuilds from the .def files. Partition into two mtime tiers accordingly.
# Run inside the build copy (operates on the current directory).
normalize_timestamps() {
    local f
    # Older tier: prerequisites of the suppressed rules, plus the builtins
    # stubs that must be regenerated from the .def files.
    for f in configure.ac aclocal.m4 configure.in config.h.in parse.y \
             builtins/builtext.h builtins/builtins.c; do
        [ -e "$f" ] && touch "$f"
    done
    sleep 1
    # Newer tier: artifacts to keep as-is (no autoconf/bison), and the
    # .def files that drive builtins regeneration.
    for f in configure y.tab.c y.tab.h parser-built builtins/*.def; do
        [ -e "$f" ] && touch "$f"
    done
}

for abi in "${!TRIPLES[@]}"; do
    triple="${TRIPLES[$abi]}"
    build="build/bash/$abi"
    out="app/src/main/jniLibs/$abi"
    echo "==> bash for $abi ($triple$API)"

    rm -rf "$build" && mkdir -p "$(dirname "$build")" "$out"
    cp -a "$SRC" "$build"
    (
        cd "$build"
        normalize_timestamps
        cp "$CACHE" config.cache
        CC="$TOOLCHAIN/${triple}${API}-clang" \
        AR="$TOOLCHAIN/llvm-ar" \
        RANLIB="$TOOLCHAIN/llvm-ranlib" \
        STRIP="$TOOLCHAIN/llvm-strip" \
        CFLAGS="-Os -fPIC \
-Wno-implicit-function-declaration -Wno-implicit-int \
-DDEFAULT_PATH_VALUE='\"/system/bin:/system/xbin:/vendor/bin\"'" \
        ./configure \
            --host="$triple" \
            --cache-file=config.cache \
            --without-bash-malloc \
            --disable-nls \
            --enable-static-link=no \
            >configure.log 2>&1 || { tail -40 configure.log; exit 1; }

        # Stop make's makefile auto-remaking: if config.status/Makefiles
        # look older than ./configure it runs `config.status --recheck`,
        # which re-runs configure and hits a hardcoded `autoconf` recipe
        # (and wants bison) we don't have. Making config.status and every
        # Makefile the newest files defeats that chain deterministically.
        touch config.status
        sleep 1
        find . -name Makefile -exec touch {} +

        make -j"$JOBS" >make.log 2>&1 || {
            echo "== parallel build failed; re-running serially =="
            make >>make.log 2>&1 || true
            grep -n -B2 -A6 -iE "error:|\*\*\*" make.log | tail -80
            exit 1
        }
    )

    "$TOOLCHAIN/llvm-strip" "$build/bash"
    cp "$build/bash" "$out/libbash.so"
done

echo "done: $(find app/src/main/jniLibs -name 'libbash.so' | sort)"
