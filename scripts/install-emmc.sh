#!/bin/bash
# Install the currently running system onto the internal eMMC (default /dev/mmcblk0).
#
# This is the counterpart of pmbootstrap's ChromeOS install path
# (partition_cgpt + write_cgpt_kpart in pmb/) without pmbootstrap: the same
# ChromeOS GPT layout, the same cgpt flags, and the kpart written to p1. The
# difference is the source of the files: pmbootstrap copies a rootfs it built in
# a chroot, this script rsyncs the system it is running from - i.e. the card
# that has already been tested.
#
# WARNING: DESTROYS the existing eMMC contents (that is where Nura lives).
# Run it from the microSD-booted Debian system with CONFIRM=yes.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-cgpt.sh"

BLOCK="${DEVICE_BLOCK:-/dev/mmcblk0}"

if [ "$(id -u)" -ne 0 ]; then
	exec sudo -n DEVICE="$DEVICE" DEVICE_BLOCK="$BLOCK" \
		BOOT_SIZE_MIB="$BOOT_SIZE_MIB" BOOT_FS="$BOOT_FS" CONFIRM="${CONFIRM:-}" \
		"$(readlink -f "$0")" "$@"
fi

[ -b "$BLOCK" ] || die "not a block device: $BLOCK"
# The kernel that is running has to be the one that ends up in the kpart, so
# the release is not taken from the repository but from the running kernel.
KERNEL_RELEASE="$(uname -r)"
export KERNEL_RELEASE
[ -d "/lib/modules/$KERNEL_RELEASE" ] || die "no modules for the running kernel $KERNEL_RELEASE"

ROOT_SRC="$(findmnt -n -o SOURCE /)"
case "$ROOT_SRC" in
	"$BLOCK"|"$BLOCK"p*|"$BLOCK"[0-9]*) die "already running from $BLOCK; boot from microSD first" ;;
esac

log "About to ERASE and install $DEVICE on $BLOCK"
log "  running root: $ROOT_SRC (kernel $KERNEL_RELEASE)"
lsblk "$BLOCK"
[ "${CONFIRM:-}" = "yes" ] || die "refusing to continue without CONFIRM=yes"

log "Creating ChromeOS GPT on $BLOCK (kernel $((KPART_SIZE_SECTORS * 512 / 1024 / 1024)) MiB, boot ${BOOT_SIZE_MIB} MiB)"
disk_release "$BLOCK"
disk_layout_create "$BLOCK"
disk_layout_parts "$BLOCK"

MNT="$WORK_DIR/emmc-mnt-$DEVICE"
disk_layout_mount "$BLOCK" "$MNT"

# Copy the running system. /boot ends up on the separate boot partition because
# it is mounted inside the target, and everything volatile is left out so the
# eMMC does not inherit the card's journal, caches and temporary files.
log "Copying the running system to $MNT"
rsync -aHAX --delete \
	--exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
	--exclude=/mnt --exclude=/media --exclude="$MNT" --exclude="$WORK_DIR" \
	--exclude=/tmp/* --exclude=/var/tmp/* \
	--exclude=/var/cache/* --exclude=/var/log/journal/* \
	/ "$MNT"/

# Those excludes are about *contents*, but the directories themselves are part
# of a root filesystem: they are mount points, and the initramfs's run-init
# moves its own /dev, /proc and /sys into them before handing over to systemd.
# rsync drops the excluded directories entirely, so the copy came out without
# /dev, /proc, /sys, /run, /mnt and /media and the eMMC mounted its root and
# then died with "run-init: opening console: No such file or directory" /
# "Target filesystem doesn't have requested /sbin/init" / "No init found" -
# the kernel and the kpart were fine, which is what made it look like a
# firmware problem. Modes are Debian's.
for _mp in dev:755 proc:555 sys:555 run:755 mnt:755 media:755; do
	install -d -m "${_mp#*:}" -o root -g root "$MNT/${_mp%:*}"
done
unset _mp

# The copy is a different machine, so it must not inherit the card's identity:
# a shared machine id means a shared journal and DHCP identity, and shared host
# keys mean two machines with one SSH identity. Emptying the id makes systemd
# generate a new one at its first boot, and the sshd-keygen drop-in
# (scripts/rootfs-setup.sh) generates the host keys there.
: >"$MNT/etc/machine-id"
rm -f "$MNT"/etc/ssh/ssh_host_*

# A rootfs that cannot be entered must never reach the kernel partition, or the
# next reboot dies without a console to say why.
[ -d "$MNT/dev" ] ||
	die "$MNT/dev missing: run-init could not move devtmpfs into the new root"
[ -e "$MNT/sbin/init" ] ||
	die "$MNT/sbin/init missing: the boot would stop with 'No init found'"

disk_layout_fstab "$MNT"

log "Building kpart for the eMMC root (root=UUID=$ROOT_UUID, kernel $KERNEL_RELEASE)"
"$REPO_DIR/scripts/make-kpart.sh" "$MNT" "$KPART.emmc" "root=UUID=$ROOT_UUID rootwait rw"
kpart_fits "$KPART.emmc" "$KPART_PART"
kpart_verify "$KPART.emmc"

log "Writing kpart to $KPART_PART"
dd if="$KPART.emmc" of="$KPART_PART" bs=1M conv=fsync
sync
disk_layout_umount "$MNT"

log "Done. Reboot and boot the internal disk (the eMMC)."
log "  This firmware shows a developer-mode menu instead of the Ctrl+D/Ctrl+U screen:"
log "  'internal disk' is the eMMC, 'external disk' is the microSD. With the card out"
log "  the internal one is the only choice; with the card in, pick it in the menu."
log "  After a kernel update on the eMMC system, run scripts/install-kpart.sh there."
cgpt show "$BLOCK"
