#!/bin/bash
# Build a distributable disk image from the built rootfs, without a card.
#
# Usage: make-image.sh [OUTPUT.img] [SIZE_MIB]
#
#   OUTPUT   destination, default $WORK_DIR/<device>.img
#   SIZE_MIB total size, default $IMAGE_SIZE_MIB or 6144
#
# The size is not cosmetic: p1 (kernel) and p2 (/boot) come off the top, so p3
# gets $SIZE_MIB - 640 MiB, and the root filesystem has to fit in it. The current
# Omarchy rootfs is ~4.6 GiB, which is what moved the default up from 4096: at
# 4 GiB the copy died with a bare `rsync: write failed ... No space left on
# device` twenty minutes in. The check below refuses that up front instead.
#
# The image carries the same ChromeOS GPT and the same signed kpart as
# scripts/write-sd.sh (both come from scripts/lib-cgpt.sh), so flashing it is
# plain dd:
#
#   xz -dc <device>.img.xz | sudo dd of=/dev/mmcblk1 bs=4M conv=fsync
#
# and the card boots from the firmware's external-disk entry. Two things differ
# from write-sd.sh, and both are about the file being *published*:
#
#   * the size is fixed by argument instead of taken from a device, so the same
#     build can be written to any card that is at least this big;
#   * the copy is sanitized (scripts/lib-dist.sh) and asserted clean, because
#     the build rootfs deliberately knows the maintainer's Wi-Fi networks.
#
# The rootfs is verified first (scripts/verify-rootfs.sh), and the image is not
# built from a tree that does not verify: this is the step whose output gets
# published and flashed, where a package that never installed or a kernel that
# was never staged is invisible until the card is in the machine. VERIFY=no
# skips it.
#
# A card larger than the image keeps the unused space: growing the root
# partition is `cgpt add -i 3 -s <sectors>` plus a resize2fs, documented in the
# release notes. This script does not do it, because it does not know the card.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-cgpt.sh"
. "$(dirname "$0")/lib-dist.sh"

IMG="${1:-$WORK_DIR/$DEVICE.img}"
SIZE_MIB="${2:-${IMAGE_SIZE_MIB:-6144}}"
KPART_IMG="$WORK_DIR/kpart-image-$DEVICE.img"

if [ "$(id -u)" -ne 0 ]; then
	# The tree is verified *before* anything is written, and as the invoking user
	# so git can read the checkout. The failures this catches are silent: a
	# package list that moved after the rootfs was built, a kernel that was never
	# installed, an overlay file that did not arrive. VERIFY=no skips it.
	if [ "${VERIFY:-yes}" != no ]; then
		"$REPO_DIR/scripts/verify-rootfs.sh" "$ROOTFS" ||
			die "the rootfs did not verify: fix what the report lists above"
	fi
	# Forward every resolved build input: sudo does not preserve the caller's
	# environment, so a build root outside $HOME (e.g. moved to a bigger disk)
	# would be dropped here and replaced by the default.
	exec sudo -n \
		BUILD_ROOT="$BUILD_ROOT" WORK_DIR="$WORK_DIR" SRC_DIR="$SRC_DIR" \
		DEVICE="$DEVICE" ROOTFS="$ROOTFS" KERNEL_RELEASE="$KERNEL_RELEASE" \
		"$(readlink -f "$0")" "$IMG" "$SIZE_MIB"
fi

[ -d "$ROOTFS" ] || die "rootfs not found: $ROOTFS (run build-rootfs.sh first)"
[ -f "$ROOTFS/boot/vmlinuz-$KERNEL_RELEASE" ] ||
	die "the rootfs has no /boot/vmlinuz-$KERNEL_RELEASE: run install-kernel.sh first"

# Refuse an image the rootfs cannot fit in, before the slow parts. p1 (kernel)
# and p2 (/boot) are carved off the top and p3 also leaves room for the secondary
# GPT (33 sectors, see lib-cgpt.sh), so p3 is SIZE_MIB minus both. The measurement
# is `du` of the rootfs as it will be copied, plus a margin for ext4's own
# metadata: a nearly full image cannot be repaired once it is on a card.
_p3_mib=$(( SIZE_MIB - KPART_SIZE_SECTORS * 512 / 1024 / 1024 - BOOT_SIZE_MIB - 1 ))
_need_mib=$(( $(du -smx "$ROOTFS" | awk '{print $1}') * 105 / 100 + 150 ))
if [ "$_need_mib" -gt "$_p3_mib" ]; then
	die "the rootfs needs ~${_need_mib} MiB but p3 would be ${_p3_mib} MiB at ${SIZE_MIB} MiB: raise it, e.g. IMAGE_SIZE_MIB=$(( (SIZE_MIB + _need_mib - _p3_mib + 511) / 512 * 512 ))"
fi
log "Rootfs size: ${_need_mib} MiB needed in p3, ${_p3_mib} MiB available"

log "Image: $IMG ($SIZE_MIB MiB, device=$DEVICE)"
rm -f "$IMG"
truncate -s "${SIZE_MIB}M" "$IMG"

# Populate through a loop device, so the layout code (which is written against a
# disk and its /dev/<disk>p<n> partitions) is reused unchanged instead of being
# reimplemented with partition offsets.
MNT="$WORK_DIR/image-mnt-$DEVICE"
LOOP="$(losetup --show -f -P "$IMG")"
trap 'disk_layout_umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT
log "Loop device: $LOOP"

disk_release "$LOOP"
disk_layout_create "$LOOP"
disk_layout_parts "$LOOP"
disk_layout_mount "$LOOP" "$MNT"

# The maintainer's state is excluded from the copy, not deleted after it: a
# deleted file is still in the image's free blocks (scripts/lib-dist.sh).
log "Copying root filesystem"
# A leftover mount under the rootfs (e.g. a chroot /proc or /sys someone forgot
# to unmount) is never wanted: rsync would copy the live host's pseudo-filesystems
# and fail on their unreadable entries (hit while writing a card). Refuse.
_stale_mounts="$(findmnt -rn -o TARGET 2>/dev/null | grep -F "$ROOTFS/" || true)"
[ -z "$_stale_mounts" ] ||
	die "something is mounted under $ROOTFS ($_stale_mounts); unmount it first"
EXCLUDES="$WORK_DIR/dist-excludes-$DEVICE.txt"
dist_write_excludes "$EXCLUDES"
rsync -aHAX --delete --exclude-from="$EXCLUDES" "$ROOTFS"/ "$MNT"/
disk_layout_fstab "$MNT"
dist_sanitize "$MNT"
dist_assert_clean "$MNT"
# p3 is sized by the argument, not by the rootfs: what is left over is worth
# saying out loud, because a tight image is one package away from not fitting.
log "p3 after the copy: $(df -h "$MNT" | awk 'NR==2 { print $2" total, "$4" free ("$5" used)" }')"

CMDLINE_EXTRA="root=UUID=$ROOT_UUID rootwait rw"
log "Building kpart (cmdline: $KERNEL_CMDLINE$CMDLINE_EXTRA)"
"$REPO_DIR/scripts/make-kpart.sh" "$MNT" "$KPART_IMG" "$CMDLINE_EXTRA"
kpart_fits "$KPART_IMG" "$KPART_PART"
kpart_verify "$KPART_IMG"

log "Writing kpart to $KPART_PART"
dd if="$KPART_IMG" of="$KPART_PART" bs=1M conv=fsync
sync
disk_layout_umount "$MNT"
losetup -d "$LOOP"
trap - EXIT
# The filesystem being clean is not enough: the image is what gets published.
dist_assert_no_profile_bytes "$IMG"

log "Done: $IMG ($(du -h "$IMG" | cut -f1) of data, $(du -h --apparent-size "$IMG" | cut -f1) apparent)"
log "Flash it with: xz -dc ${IMG##*/}.xz | sudo dd of=<card> bs=4M conv=fsync"
cgpt show "$IMG" || true
