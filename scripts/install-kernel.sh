#!/bin/bash
# Install the staged kernel (modules, vmlinuz, dtbs) into a rootfs and build its initramfs.
#
# Usage: install-kernel.sh [ROOTFS]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ -n "${1:-}" ] && ROOTFS="$1"

if [ "$(id -u)" -ne 0 ]; then
	exec sudo -n DEVICE="$DEVICE" "$(readlink -f "$0")" "${1:-}"
fi

[ -d "$ROOTFS" ] || die "rootfs not found: $ROOTFS (run build-rootfs.sh first)"
[ -d "$KERNEL_STAGE/lib/modules/$KERNEL_RELEASE" ] || die "staged kernel not found: $KERNEL_STAGE (run build-kernel.sh first)"

log "Installing modules for $KERNEL_RELEASE"
mkdir -p "$ROOTFS/lib/modules"
rm -rf "$ROOTFS/lib/modules/$KERNEL_RELEASE"
cp -a "$KERNEL_STAGE/lib/modules/$KERNEL_RELEASE" "$ROOTFS/lib/modules/"

log "Installing vmlinuz / config / dtbs"
mkdir -p "$ROOTFS/boot/dtbs"
# The kernel 'zinstall' target names the image vmlinuz-<release> (no plain vmlinuz).
KERNEL_IMG="$KERNEL_STAGE/boot/vmlinuz-$KERNEL_RELEASE"
[ -f "$KERNEL_IMG" ] || die "staged kernel image not found: $KERNEL_IMG"
cp "$KERNEL_IMG" "$ROOTFS/boot/vmlinuz-$KERNEL_RELEASE"
[ -f "$KERNEL_STAGE/boot/config" ] && cp "$KERNEL_STAGE/boot/config" "$ROOTFS/boot/config-$KERNEL_RELEASE"
[ -f "$KERNEL_STAGE/boot/System.map" ] && cp "$KERNEL_STAGE/boot/System.map" "$ROOTFS/boot/System.map-$KERNEL_RELEASE"
cp -a "$KERNEL_STAGE/boot/dtbs/." "$ROOTFS/boot/dtbs/"

# Force the device's early modules into the initramfs.
if [ -n "$INITFS_MODULES" ]; then
	log "Adding initramfs modules: $INITFS_MODULES"
	mkdir -p "$ROOTFS/etc/initramfs-tools"
	touch "$ROOTFS/etc/initramfs-tools/modules"
	for m in $INITFS_MODULES; do
		grep -qxF "$m" "$ROOTFS/etc/initramfs-tools/modules" || echo "$m" >>"$ROOTFS/etc/initramfs-tools/modules"
	done
fi

log "depmod + initramfs"
mount --bind /dev "$ROOTFS/dev"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
cleanup() {
	for m in dev proc sys; do
		umount -lf "$ROOTFS/$m" 2>/dev/null || true
	done
}
trap cleanup EXIT
chroot "$ROOTFS" depmod -a "$KERNEL_RELEASE"
chroot "$ROOTFS" update-initramfs -c -k "$KERNEL_RELEASE"

log "Kernel installed into $ROOTFS"
ls -la "$ROOTFS/boot"
