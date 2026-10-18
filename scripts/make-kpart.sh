#!/bin/bash
# Build the signed depthcharge FIT kernel partition image (kpart) for the device.
#
# Mirrors pmOS boot-deploy for ChromeOS devices:
#   depthchargectl build --root none --board <board> --kernel ... \
#       --kernel-cmdline ... --initramfs ... --fdtdir ... --compress ... -o ...
#
# Usage: make-kpart.sh [ROOTFS] [OUTPUT] [CMDLINE_EXTRA]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ -n "${1:-}" ] && ROOTFS="$1"
OUT="${2:-$KPART}"
CMDLINE_EXTRA="${3:-}"

KERNEL_IMG="$ROOTFS/boot/vmlinuz-$KERNEL_RELEASE"
INITRD="$ROOTFS/boot/initrd.img-$KERNEL_RELEASE"
[ -f "$KERNEL_IMG" ] || die "kernel not found: $KERNEL_IMG"
[ -f "$INITRD" ] || die "initramfs not found: $INITRD"
[ -n "$DEPTHCHARGE_BOARD" ] || die "deviceinfo_depthcharge_board not set for $DEVICE"

# Stage the DTBs in a throwaway directory. It is deliberately not a fixed path:
# install-kpart.sh builds the kpart as root (it rewrites a partition), while
# build.sh does it as the invoking user, and a shared directory would be left
# root-owned and unremovable by the other side.
BUILDDIR="$(mktemp -d "$WORK_DIR/kpart-dtbs-$DEVICE.XXXXXX")"
DCT_TMP="$(mktemp -d "$WORK_DIR/dct-$DEVICE.XXXXXX")"
trap 'rm -rf "$BUILDDIR" "$DCT_TMP"' EXIT
# Same reason for the output: write-sd.sh and install-emmc.sh build the kpart as
# root, and depthchargectl cannot overwrite a root-owned file as brunux.
if [ -e "$OUT" ] && [ ! -w "$OUT" ]; then
	rm -f "$OUT" 2>/dev/null || sudo -n rm -f "$OUT" ||
		die "cannot replace $OUT (root-owned): remove it first"
fi
# Expand the deviceinfo_dtb glob (e.g. "mediatek/mt8192-asurada*").
# shellcheck disable=SC2086
set -- "$ROOTFS"/boot/dtbs/$DTB_GLOB.dtb
[ -e "$1" ] || die "no DTBs matching '$DTB_GLOB' under $ROOTFS/boot/dtbs"
cp "$@" "$BUILDDIR"/

# depthchargectl/mkdepthcharge prepends "kern_guid=%U" itself (see
# --no-kern-guid), so it must NOT be added here.
#
# get_cmdline() in boot-deploy-functions.sh appends the UUIDs to the deviceinfo
# command line separated by a space; the separator is built here instead of being
# inherited from the `tr '\n' ' '` in lib.sh, which only produces one when the
# file ends with a newline. Without this, a kernel-cmdline.conf whose last line
# has no trailing newline would be glued to root=UUID=... and depthcharge would
# hand the kernel a command line it cannot parse.
CMDLINE="$(printf '%s %s' "$KERNEL_CMDLINE" "$CMDLINE_EXTRA" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')"
log "Building kpart (device=$DEVICE board=$DEPTHCHARGE_BOARD compression=$DEPTHCHARGE_COMPRESSION)"
log "  kernel : $KERNEL_IMG"
log "  initrd : $INITRD"
log "  dtbs   : $(ls "$BUILDDIR")"
log "  cmdline: $CMDLINE"

depthchargectl build --root none \
	--board "$DEPTHCHARGE_BOARD" \
	--kernel "$KERNEL_IMG" \
	--kernel-cmdline "$CMDLINE" \
	--initramfs "$INITRD" \
	--fdtdir "$BUILDDIR" \
	--compress "$DEPTHCHARGE_COMPRESSION" \
	--timestamp "${SOURCE_DATE_EPOCH:-$(date +%s)}" \
	--tmpdir "$DCT_TMP" \
	--output "$OUT"

log "Built $OUT ($(du -h "$OUT" | cut -f1))"
