# Wraith — build sources for bundled tools

**Wraith** is a terminal for Android (powered by the Ghostty engine). It bundles
several open-source command-line tools, built from **unmodified upstream
sources** with the cross-compile scripts in this repository.

This repo exists to satisfy the **GPL** source requirements for the GPL-licensed
tools Wraith ships — **bash** (GPL-3.0-or-later) and **BusyBox** (GPL-2.0) — by
providing the "scripts used to control compilation," together with pointers to
the exact upstream source. Nothing in the tools' own source is modified by
Wraith; the corresponding source is *upstream at the pinned commit* + the build
script here.

Contact for source requests: **wraith.term4android@gmail.com**

## Bundled tools — exact upstream + commit

| Tool | License | Upstream | Pinned commit / tag |
| --- | --- | --- | --- |
| **bash** 5.2 | GPL-3.0-or-later | https://git.savannah.gnu.org/git/bash.git (also https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz) | `74091dd` (tag `bash-5.2`) |
| **BusyBox** | GPL-2.0 | https://git.busybox.net/busybox | `1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4` |
| Dropbear | MIT-style | https://github.com/mkj/dropbear | `d27a296` (DROPBEAR_2025.88) |
| broot | MIT | https://github.com/Canop/broot | `v1.57.0` |
| micro | MIT | https://github.com/zyedidia/micro | `v2.0.14` |
| leaf | MIT | https://github.com/rivo-link/leaf | `1.26.0` |
| Ghostty | MIT | https://github.com/ghostty-org/ghostty | `v1.3.1` |

## How the tools are built

Each `scripts/build-<tool>-android.sh` checks out the tool's upstream source at
the commit above (as a git submodule in the full Wraith tree), then
cross-compiles it for Android (`arm64-v8a`, `x86_64`) with the NDK.

- **bash** (`build-bash-android.sh`) — configured with `scripts/bash/config-android.cache`
  (Android/bionic `configure` answers) and NDK clang. No source changes.
- **BusyBox** (`build-busybox-android.sh`) — `make defconfig`, then the `.config`
  is adjusted by the `sed` edits in the script (disabling applets that don't
  link against bionic, enabling PIE). No source changes.

Toolchain: Android NDK r27 (27.2.12479018), minSdk 29. To reproduce: clone the
tool upstream at the pinned commit, set `ANDROID_NDK_ROOT`, and run the matching
script.

## License texts

- GPL-2.0 / GPL-3.0: https://www.gnu.org/licenses/
- The MIT-licensed tools carry their own `LICENSE` files upstream.

The full attribution list is shown inside the app: gear menu →
**Open-source licenses**, or the `licenses` command.
