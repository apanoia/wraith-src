#!/usr/bin/env bash
# Cross-compiles BusyBox for Android with the NDK, staged as libbusybox.so
# (a PIE executable packaged as a jniLib so it can be exec'd from
# nativeLibraryDir). TerminalSession installs applet symlinks into a
# PATH dir on first run so `vi`, `less`, `awk`, `tar`, `wget`, ... work.
#
# Built from defconfig with the applets that don't compile/link against
# bionic disabled (no shadow/utmp/crypt logins, no libresolv, kernel
# headers bionic lacks, struct clashes). Verified in-tree.
#
# Requires ANDROID_NDK_ROOT, or ANDROID_HOME + NDK_VERSION.
set -euo pipefail

cd "$(dirname "$0")/.."

NDK="${ANDROID_NDK_ROOT:-${ANDROID_HOME:?set ANDROID_NDK_ROOT or ANDROID_HOME}/ndk/${NDK_VERSION:?set NDK_VERSION}}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=29
SRC="$PWD/vendor/busybox"
JOBS="$(nproc 2>/dev/null || echo 4)"

declare -A TRIPLES=(
    [arm64-v8a]=aarch64-linux-android
    [x86_64]=x86_64-linux-android
)

# Applets/features that don't build or link against bionic.
DISABLE=(
    # console-tools: need <sys/kd.h>/<sys/vt.h>
    LOADFONT SETFONT LOADKMAP DUMPKMAP KBD_MODE SETCONSOLE SETKEYCODES
    CHVT DEALLOCVT OPENVT RESIZE SHOWKEY FGCONSOLE CONSPY
    # utmp/wtmp + users of it (bionic has no utmp)
    FEATURE_UTMP FEATURE_WTMP MESG WHO W USERS LAST
    # gethostid() is not in bionic
    HOSTID
    # loginutils: shadow/crypt/pw databases bionic lacks
    LOGIN PASSWD SU SULOGIN GETTY ADDUSER DELUSER ADDGROUP DELGROUP
    ADD_SHELL REMOVE_SHELL VLOCK CHPASSWD CRYPTPW MKPASSWD PAM SELINUX
    # util-linux: mount/fs/rtc/ipc bits (missing headers or struct clashes)
    MOUNT UMOUNT SWITCH_ROOT PIVOT_ROOT LOSETUP MKSWAP SWAPON SWAPOFF
    FDISK BLKID FINDFS HWCLOCK RTCWAKE SETARCH SCRIPT SCRIPTREPLAY
    FDFORMAT FSFREEZE IPCRM IPCS
    MKE2FS TUNE2FS E2FSCK FSCK FSCK_MINIX MKFS_EXT2 MKFS_MINIX MKFS_VFAT
    # networking: struct in6_ifreq clashes, kernel CBQ headers, resolver
    IFCONFIG ROUTE NETSTAT ARP SLATTACH NAMEIF IFENSLAVE TC ETHER_WAKE
    FEATURE_NSLOOKUP_BIG NSLOOKUP
    # runit (uses utmp), and hush (uses sigisemptyset); we ship bash+ash
    RUNSV RUNSVDIR SV SVLOGD CHPST HUSH
)

for abi in "${!TRIPLES[@]}"; do
    triple="${TRIPLES[$abi]}"
    build="build/busybox/$abi"
    out="app/src/main/jniLibs/$abi"
    echo "==> busybox for $abi ($triple$API)"

    rm -rf "$build" && mkdir -p "$(dirname "$build")" "$out"
    cp -a "$SRC" "$build"
    (
        cd "$build"
        make defconfig >/dev/null 2>&1
        for o in "${DISABLE[@]}"; do
            sed -i "s|^CONFIG_$o=y|# CONFIG_$o is not set|" .config
        done
        # PIE executable, and downgrade the unavoidable implicit-decl
        # warnings from bionic-thin applets to keep the build going.
        sed -i 's|^# CONFIG_PIE is not set|CONFIG_PIE=y|' .config
        sed -i 's|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS="-Wno-implicit-function-declaration -Wno-int-conversion"|' .config
        make oldconfig </dev/null >/dev/null 2>&1 || true

        make -j"$JOBS" \
            CC="$TOOLCHAIN/${triple}${API}-clang" \
            HOSTCC=gcc \
            AR="$TOOLCHAIN/llvm-ar" \
            STRIP="$TOOLCHAIN/llvm-strip" \
            >make.log 2>&1 || { tail -30 make.log; exit 1; }
    )

    "$TOOLCHAIN/llvm-strip" "$build/busybox"
    cp "$build/busybox" "$out/libbusybox.so"
done

echo "done: $(find app/src/main/jniLibs -name 'libbusybox.so' | sort)"
