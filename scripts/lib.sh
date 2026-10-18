# shellcheck shell=bash
# Shared configuration for the debian-aarch64 build system.
#
# The build is device-agnostic:
#   * a device lives in devices/<codename>/ and is described by a pmaports-style
#     `deviceinfo` (plus kernel-cmdline.conf and modules-initfs);
#   * the kernel to use is named by devices/<codename>/kernel and lives in
#     kernels/<flavor>/ (version, config, patches/series).
#
# Select a device with the DEVICE environment variable. When only one device is
# present it is picked automatically.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve the *invoking* user's home even when running under sudo, so large
# artifacts stay on the real filesystem and are not written to /root.
if [ -n "${SUDO_USER:-}" ]; then
	_invoking_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
	_invoking_home="$HOME"
fi
# /tmp is a small tmpfs on the target device; keep large artifacts on disk.
BUILD_ROOT="${BUILD_ROOT:-${_invoking_home:-/root}/.cache/debian-aarch64}"
WORK_DIR="${WORK_DIR:-$BUILD_ROOT/work}"
SRC_DIR="${SRC_DIR:-$BUILD_ROOT/src}"
mkdir -p "$WORK_DIR" "$SRC_DIR"

DEVICES_DIR="$REPO_DIR/devices"
KERNELS_DIR="$REPO_DIR/kernels"
PACKAGES_DIR="$REPO_DIR/packages"
# A UI (graphical shell) is a package list plus a file tree:
#   uis/<name>/packages.list   packages to install
#   uis/<name>/files/          tree overlaid onto the rootfs (etc/ as root,
#                              home/ into /home/$USERNAME)
UIS_DIR="$REPO_DIR/uis"
UI="${UI:-sway}"
UI_DIR="$UIS_DIR/$UI"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "this command must run as root (use sudo)"; }

# ---------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------
if [ -z "${DEVICE:-}" ]; then
	DEVICE="$(cd "$DEVICES_DIR" && ls -1 | head -n1)"
fi
DEVICE_DIR="$DEVICES_DIR/$DEVICE"
[ -d "$DEVICE_DIR" ] || die "unknown device '$DEVICE' (see $DEVICES_DIR)"

# deviceinfo is a sourceable shell file in pmaports format.
# shellcheck disable=SC1091
. "$DEVICE_DIR/deviceinfo"

DEVICE_ARCH="${deviceinfo_arch:-arm64}"
# Kernel command line base (kernel-cmdline.conf) joined into one line.
# KERNEL_CMDLINE_OVERRIDE replaces it entirely; useful for a verbose debug boot
# (e.g. KERNEL_CMDLINE_OVERRIDE="console=tty0 ignore_loglevel loglevel=7").
KERNEL_CMDLINE="${KERNEL_CMDLINE_OVERRIDE:-$(tr '\n' ' ' <"$DEVICE_DIR/kernel-cmdline.conf" 2>/dev/null || true)}"
# Modules to force into the initramfs.
INITFS_MODULES="$(tr '\n' ' ' <"$DEVICE_DIR/modules-initfs" 2>/dev/null || true)"
# DTBs to embed (relative to /boot/dtbs; may contain a glob).
DTB_GLOB="${deviceinfo_dtb:-}"

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------
KERNEL_FLAVOR="$(cat "$DEVICE_DIR/kernel")"
KERNEL_DIR="$KERNELS_DIR/$KERNEL_FLAVOR"
[ -d "$KERNEL_DIR" ] || die "kernel flavor '$KERNEL_FLAVOR' (device '$DEVICE') not found in $KERNELS_DIR"

KERNEL_VERSION="$(cat "$KERNEL_DIR/version")"
KERNEL_CONFIG="$KERNEL_DIR/config.aarch64"
KERNEL_PATCH_DIR="$KERNEL_DIR/patches"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/${KERNEL_TARBALL}"
# Kernel ARCH name (deviceinfo uses distro-style names).
case "$DEVICE_ARCH" in
	aarch64 | arm64) KERNEL_ARCH=arm64 ;;
	armv7 | arm) KERNEL_ARCH=arm ;;
	x86_64 | amd64) KERNEL_ARCH=x86 ;;
	*) KERNEL_ARCH="$DEVICE_ARCH" ;;
esac
KERNEL_SRC="$SRC_DIR/linux-$KERNEL_VERSION"
# Derive the release string from the kernel config (no duplication).
KERNEL_LOCALVERSION="$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' "$KERNEL_CONFIG")"
# The release can be overridden for a kernel that was not built from this repo,
# e.g. the kernel a booted system is actually running (see install-kpart.sh).
KERNEL_RELEASE="${KERNEL_RELEASE:-${KERNEL_VERSION}${KERNEL_LOCALVERSION}}"

# ---------------------------------------------------------------------------
# Boot chain (depthcharge / ChromeOS GPT)
# ---------------------------------------------------------------------------
DEPTHCHARGE_BOARD="${deviceinfo_depthcharge_board:-}"
DEPTHCHARGE_COMPRESSION="${deviceinfo_depthcharge_compression:-lzma}"
KPART_START_SECTORS="${deviceinfo_cgpt_kpart_start:-8192}"
KPART_SIZE_SECTORS="${deviceinfo_cgpt_kpart_size:-262144}"   # 128 MiB
KPART_PATH="${deviceinfo_cgpt_kpart:-/boot/vmlinuz.kpart}"
# The rest of the layout, after the kernel partition: a boot partition and the
# root filesystem (see scripts/lib-cgpt.sh, which creates and resolves it).
# Both values mirror Nura/pmbootstrap, which are what already worked on this
# machine: pmbootstrap's Config.boot_size defaults to 512 MiB (pmb/core/config.py)
# and the pmaports deviceinfo schema defaults flash.boot_filesystem to ext2.
# Nura's own eMMC partition table is p1 128 MiB kernel + p2 512 MiB /boot + p3 root.
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-512}"
BOOT_FS="${BOOT_FS:-ext2}"

# ---------------------------------------------------------------------------
# Debian target
# ---------------------------------------------------------------------------
DEBIAN_SUITE="${DEBIAN_SUITE:-forky}"
# Map the deviceinfo arch (distro/Alpine style, e.g. aarch64) to the Debian
# architecture name (e.g. arm64). debootstrap requires the latter.
case "$DEVICE_ARCH" in
	aarch64 | arm64) _debian_arch=arm64 ;;
	armv7 | arm) _debian_arch=armhf ;;
	i686 | x86) _debian_arch=i386 ;;
	x86_64 | amd64) _debian_arch=amd64 ;;
	*) _debian_arch="$DEVICE_ARCH" ;;
esac
DEBIAN_ARCH="${DEBIAN_ARCH:-$_debian_arch}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_COMPONENTS="${DEBIAN_COMPONENTS:-main contrib non-free non-free-firmware}"

# NetworkManager Wi-Fi profiles exported from the running system (scripts/wifi.sh).
# They contain the PSK, so they deliberately live outside the repository.
WIFI_DIR="${WIFI_DIR:-$BUILD_ROOT/wifi}"

# Locale and timezone of the built image.  Both are baked into the rootfs, not
# into the kernel, so they are ordinary build inputs:
#   LOCALE=en_US.UTF-8 scripts/build-rootfs.sh
#   TIMEZONE=UTC scripts/build-rootfs.sh
# The locale must be an entry of /etc/locale.gen (Debian ships every entry
# commented out; rootfs-setup.sh uncomments and generates the requested one),
# the timezone a name under /usr/share/zoneinfo (e.g. UTC, Europe/Madrid).
LOCALE="${LOCALE:-en_US.UTF-8}"
TIMEZONE="${TIMEZONE:-America/Mexico_City}"

# ---------------------------------------------------------------------------
# Build directories
# ---------------------------------------------------------------------------
ROOTFS="${ROOTFS:-$WORK_DIR/rootfs-$DEVICE}"
KERNEL_STAGE="${KERNEL_STAGE:-$WORK_DIR/kernel-stage-$KERNEL_FLAVOR}"
KPART="${KPART:-$WORK_DIR/$DEVICE.vmlinuz.kpart}"

export REPO_DIR BUILD_ROOT WORK_DIR SRC_DIR DEVICE DEVICE_DIR KERNEL_DIR
export UI UIS_DIR UI_DIR WIFI_DIR
export LOCALE TIMEZONE
export BOOT_SIZE_MIB BOOT_FS KERNEL_RELEASE
