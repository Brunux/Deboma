#!/bin/bash
# Rewrite the ChromeOS kernel partition that this system was booted from.
#
# Counterpart of boot-deploy's flash_updated_depthcharge_kernel(): a machine
# that boots from a ChromeOS kernel partition keeps the kernel *inside* that
# partition, so installing a new kernel into /boot and /lib/modules is not
# enough - the partition has to be rewritten too, or the firmware goes on
# loading the old kernel while the rest of the system moves on.
#
# The partition is not assumed or configured: it is the one depthcharge
# substituted into kern_guid= in /proc/cmdline, so this always acts on the
# device it is actually running from (card or eMMC).
#
# Usage:
#   scripts/install-kpart.sh [KPART_IMAGE]
#
# Without an argument the kpart is built from the running system (its kernel
# release, /boot and the DTBs there), which is what a kernel update needs. With
# an argument, that prebuilt image is written instead (e.g. the one produced by
# scripts/build.sh on the build host).
#
# Writing requires CONFIRM=yes; what it replaces is backed up first.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-cgpt.sh"

if [ "$(id -u)" -ne 0 ]; then
	# sudo -n starts from a clean environment, so CONFIRM=yes has to be forwarded
	# explicitly or the guard below can never pass through the re-exec.
	exec sudo -n DEVICE="$DEVICE" CONFIRM="${CONFIRM:-}" "$(readlink -f "$0")" "$@"
fi

# Never act from a chroot: /proc/cmdline there belongs to the host, so the GUID
# would point at the host's kernel partition. boot-deploy guards this too.
#
# `stat -L` is what makes the comparison mean anything: without it, stat reports
# the procfs symlink itself (device 0:28), which can never equal the device:inode
# of /, so the guard passed silently. And the answer is the other way round from
# what it looks: *equal* means this root is PID 1's root, i.e. a real system, so a
# chroot is when they differ -- the original refused when they were equal, which
# is every real system. Both sides must be known before refusing, so a system
# where /proc hides PID 1 is not mistaken for a chroot.
_root="$(stat -Lc %d:%i / 2>/dev/null || true)"
_pid1_root="$(stat -Lc %d:%i /proc/1/root 2>/dev/null || true)"
if [ -n "$_root" ] && [ -n "$_pid1_root" ] && [ "$_root" != "$_pid1_root" ]; then
	die "running in a chroot: /proc/cmdline describes the host, not this system"
fi

GUID=""
for _x in $(cat /proc/cmdline); do
	case "$_x" in
		kern_guid=*) GUID="${_x#kern_guid=}" ;;
	esac
done
[ -n "$GUID" ] || die "no kern_guid= in /proc/cmdline: this kernel was not loaded by depthcharge"
PART="$(findfs PARTUUID="$GUID" 2>/dev/null || true)"
[ -n "$PART" ] || die "no partition with PARTUUID=$GUID (from kern_guid in /proc/cmdline)"
DISK="/dev/$(lsblk -nro PKNAME "$PART")"
log "Kernel partition: $PART (disk $DISK, PARTUUID $GUID)"

ROOT_UUID="$(findmnt -n -o UUID / 2>/dev/null || true)"
[ -n "$ROOT_UUID" ] || ROOT_UUID="$(blkid -s UUID -o value "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)"
[ -n "$ROOT_UUID" ] || die "could not read the UUID of the root filesystem"

if [ -n "${1:-}" ]; then
	IMG="$(readlink -f "$1")"
	[ -f "$IMG" ] || die "not a file: $IMG"
	log "Using the prebuilt kpart $IMG"
else
	# The running kernel, not the repository's: that is the one /lib/modules and
	# /boot describe right now.
	KERNEL_RELEASE="$(uname -r)"
	export KERNEL_RELEASE
	[ -d "/lib/modules/$KERNEL_RELEASE" ] || die "no /lib/modules/$KERNEL_RELEASE"
	IMG="$WORK_DIR/kpart-running-$DEVICE"
	log "Building the kpart from the running system ($KERNEL_RELEASE)"
	"$REPO_DIR/scripts/make-kpart.sh" / "$IMG" "root=UUID=$ROOT_UUID rootwait rw"
fi

kpart_fits "$IMG" "$PART"
kpart_verify "$IMG"

# The partition looked up from kern_guid has to be a ChromeOS kernel partition,
# not merely a partition: writing a kpart into the root filesystem because a
# GUID was wrong would be unrecoverable.
_idx="$(printf '%s' "$PART" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
if [ -n "$_idx" ] && command -v cgpt >/dev/null 2>&1; then
	_table="$(cgpt show -i "$_idx" "$DISK" 2>/dev/null || true)"
	case "$_table" in
		*"ChromeOS kernel"*) ;;
		*) die "$PART is not a ChromeOS kernel partition (kernel partition expected)" ;;
	esac
	log "Plan: write $IMG ($(stat -c %s "$IMG") bytes) to $PART"
	printf '%s\n' "$_table"
else
	log "Plan: write $IMG ($(stat -c %s "$IMG") bytes) to $PART"
fi
[ "${CONFIRM:-}" = "yes" ] || die "refusing to write without CONFIRM=yes (CONFIRM=yes scripts/install-kpart.sh)"

# Keep a copy of what was there, so a bad image is recoverable without going
# back to a microSD.
BACKUP="$WORK_DIR/kpart-backup-$(date +%Y%m%d-%H%M%S).img"
log "Backing up the current kernel partition to $BACKUP"
log "  (recover with: dd if=$BACKUP of=$PART bs=1M conv=fsync)"
dd if="$PART" of="$BACKUP" bs=1M 2>/dev/null

log "Writing the kpart"
dd if="$IMG" of="$PART" bs=1M conv=fsync
sync

futility show "$PART" 2>/dev/null | grep -E 'Kernel partition|Header version|Body verification' ||
	warn "could not re-read the kernel partition with futility"

log "Done. Reboot to run the new kernel; keep $BACKUP until it has booted."