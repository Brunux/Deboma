#!/bin/bash
# ChromeOS GPT helpers, shared by every script that writes a bootable disk:
#   write-sd.sh      writes a card from the built rootfs
#   install-emmc.sh  writes the internal storage from the running system
#   install-kpart.sh rewrites only the kernel partition of the running system
#
# Sourced after lib.sh, which provides die()/log()/warn() and the geometry
# (KPART_START_SECTORS, KPART_SIZE_SECTORS, BOOT_SIZE_MIB, BOOT_FS).
#
# The layout is Nura's (and pmbootstrap's), reproduced deliberately:
#   p1  kernel  128 MiB  (pmOS_kernel)  ChromeOS kernel partition: the signed kpart
#   p2  boot    512 MiB  (pmOS_boot)    the kernel, initramfs and DTBs
#   p3  root    the rest (pmOS_root)    the Debian root filesystem
# depthcharge only reads p1 - it loads the kpart, which is self-contained - but
# /boot is kept separate exactly as Nura has it, so the two installations on
# this machine look the same and the eMMC is a faithful copy of the tested card.
#
# This file follows the install method pmbootstrap proved on this Chromebook,
# part by part, because that method is the one known to boot here:
#   partition_cgpt()          -> disk_layout_create()  (pmb/install/partition.py)
#   sanity_check_boot_size()  -> the 512 MiB floor in disk_layout_create()
#   mount_disk()              -> the "is it mounted?" refusal in disk_release()
#   format()                  -> disk_layout_mount()   (pmb/install/format.py)
#   create_fstab()            -> disk_layout_fstab()   (pmb/install/_install.py)
#   partitions_mount()        -> root, then /boot, into one mountpoint
#   check_image_size()        -> kpart_fits()          (boot-deploy-functions.sh)
# The geometry is read from the same deviceinfo variables (cgpt_kpart_start and
# cgpt_kpart_size; 8192 and 262144 sectors on google-asurada), and the cgpt flags
# (-S 1 -T 5 -P 10, kernel/efi/data types, pmOS_* labels) are the ones
# pmb/install/partition.py passes. Deviations are called out at the line that
# makes them; there is no silent one.

# Prepare a disk for repartitioning. Both naming schemes are covered: mmcblk1p1
# and sda1.
#
# mount_disk() in pmb/install/blockdevice.py refuses to touch a disk when any of
# its partitions is mounted ("is mounted! Will not attempt to format this!") and
# the same refusal is kept here instead of silently unmounting: a card the
# desktop auto-mounted has to be unmounted on purpose. Active swap is turned off
# as well - pmbootstrap does not check for it, but mkfs on a live swap partition
# fails - and no signature is wiped: parted writes both GPT tables and
# `mkfs -F` overwrites whatever the partitions carried.
disk_release() {
	_disk="$1"
	for _part in "$_disk" "$_disk"p* "$_disk"[0-9]*; do
		[ -b "$_part" ] || continue
		# `mountpoint -q "$_part"` is the obvious test and it is the wrong one:
		# it asks whether that path *is* a mount point, which a device node never
		# is, so it answered "no" for a mounted partition and the refusal never
		# fired. The mount table has to be searched by source instead - the same
		# mistake the old unmounting code was making, silently.
		if findmnt -rn -S "$_part" >/dev/null 2>&1 || grep -qs "^$_part " /proc/mounts; then
			die "$_part is mounted; unmount it first (udisksctl unmount -b $_part) and run again"
		fi
		swapoff "$_part" 2>/dev/null || true
	done
}

# Create the ChromeOS GPT on <disk> and set the derived geometry in the
# variables BOOT_START/BOOT_SIZE/ROOT_START/ROOT_SIZE (in 512-byte sectors).
#
# cgpt pitfalls, all of them observed on this device:
#  * 'cgpt create -z' zeroes the GPT areas *after* writing them, so the next
#    'cgpt add' fails with GPT_ERROR_INVALID_HEADERS. Do not use -z.
#  * cgpt does not write a protective MBR, and the Linux kernel refuses to
#    parse a GPT without one (0xAA55 plus a 0xEE entry), so parted creates the
#    table first and cgpt writes the ChromeOS entries on top of it.
# The kernel partition flags (-S 1 -T 5 -P 10) are the ones pmbootstrap sets in
# pmb/install/partition.py: successful, 5 tries, priority 10.
disk_layout_create() {
	_disk="$1"
	# sanity_check_boot_size() in pmb/install/_install.py refuses to go on with a
	# boot partition below the 512 MiB default ("this can lead to problems later
	# on"), and its deviceinfo schema default for boot_filesystem is ext2 - the
	# filesystem BOOT_FS defaults to here.
	[ "$BOOT_SIZE_MIB" -ge 512 ] ||
		die "BOOT_SIZE_MIB=$BOOT_SIZE_MIB is below the 512 MiB pmbootstrap requires; use BOOT_SIZE_MIB=512"
	TOTAL="$(blockdev --getsz "$_disk")"
	BOOT_START=$((KPART_START_SECTORS + KPART_SIZE_SECTORS))
	BOOT_SIZE=$((BOOT_SIZE_MIB * 2048))
	ROOT_START=$((BOOT_START + BOOT_SIZE))
	# partition_cgpt() in pmb/install/partition.py sizes the root partition as
	# dev_size - s_root_start - 33: the 32-sector secondary GPT plus its header,
	# so the backup table is not overwritten.
	ROOT_SIZE=$((TOTAL - ROOT_START - 33))
	[ "$ROOT_SIZE" -gt 1048576 ] ||
		die "device too small for a root filesystem: $_disk ($(blockdev --getsize64 "$_disk") bytes)"

	# Not in pmbootstrap, which lets parted alone handle the old table: zero both
	# GPT areas first so that no stale header can make `cgpt create` fail with
	# GPT_ERROR_INVALID_HEADERS. parted writes the protective MBR and the table
	# right after, so the result is the same one partition_cgpt() produces.
	dd if=/dev/zero of="$_disk" bs=512 count=34 conv=fsync 2>/dev/null
	dd if=/dev/zero of="$_disk" bs=512 seek=$((TOTAL - 33)) count=33 conv=fsync 2>/dev/null
	parted -s "$_disk" mktable gpt
	cgpt create "$_disk"
	cgpt add -i 1 -b "$KPART_START_SECTORS" -s "$KPART_SIZE_SECTORS" -t kernel -l pmOS_kernel \
		-S 1 -T 5 -P 10 "$_disk"
	cgpt add -i 2 -b "$BOOT_START" -s "$BOOT_SIZE" -t efi -l pmOS_boot "$_disk"
	cgpt add -i 3 -b "$ROOT_START" -s "$ROOT_SIZE" -t data -l pmOS_root "$_disk"
	# install_system_image() runs `partprobe` right after partitioning "in case
	# parted couldn't inform the kernel"; partx -d then -a does the same job and
	# avoids BLKRRPART's EBUSY on this card.
	partprobe "$_disk" 2>/dev/null || true
	partx -d "$_disk" 2>/dev/null || true
	partx -a "$_disk" 2>/dev/null || blockdev --rereadpt "$_disk" 2>/dev/null || true
	command -v udevadm >/dev/null && udevadm settle || sleep 2
}

# Resolve the partition devices into KPART_PART/BOOT_PART/ROOT_PART.
#
# By partition *number*, never by position. `lsblk` lists a disk's partitions in
# the order the kernel handed out their minors, and that order drifts away from
# the partition numbers after the `partx -d`/`-a` round disk_layout_create() runs
# so the kernel re-reads the table it was just given. Measured over 16 attaches of
# a 2048 MiB loop (AGENTS.md, "pmbootstrap parity"): 3 came back as `3 1 2` or
# `2 1 3`, with no line missing, so taking the 2nd, 3rd and 4th line - which is
# what this function did - formatted p2 as the root filesystem and wrote the kpart
# into p3.
#
# The labels are asserted for the same reason: a resolution that goes wrong has to
# fail loudly instead of formatting or overwriting the wrong partition. cgpt
# writes pmOS_kernel/pmOS_boot/pmOS_root and everything downstream expects those.
disk_layout_parts() {
	_disk="$1"
	KPART_PART="$(lsblk -nro PATH,PARTN "$_disk" | awk '$2 == 1 { print $1; exit }')"
	BOOT_PART="$(lsblk -nro PATH,PARTN "$_disk" | awk '$2 == 2 { print $1; exit }')"
	ROOT_PART="$(lsblk -nro PATH,PARTN "$_disk" | awk '$2 == 3 { print $1; exit }')"
	[ -n "$KPART_PART" ] && [ -n "$BOOT_PART" ] && [ -n "$ROOT_PART" ] ||
		die "could not resolve partitions on $_disk"
	for _p in "$KPART_PART" "$BOOT_PART" "$ROOT_PART"; do
		[ "$_p" != "$_disk" ] ||
			die "refusing to operate on the whole disk; partition resolution failed for $_disk"
	done
	[ "$(lsblk -nro PARTLABEL "$KPART_PART")" = "pmOS_kernel" ] ||
		die "$KPART_PART is not the pmOS_kernel partition: partition resolution is wrong"
	[ "$(lsblk -nro PARTLABEL "$BOOT_PART")" = "pmOS_boot" ] ||
		die "$BOOT_PART is not the pmOS_boot partition: partition resolution is wrong"
	[ "$(lsblk -nro PARTLABEL "$ROOT_PART")" = "pmOS_root" ] ||
		die "$ROOT_PART is not the pmOS_root partition: partition resolution is wrong"
}

# Format and mount the boot and root partitions into <mountpoint>.
# Sets BOOT_UUID and ROOT_UUID. Unmount with disk_layout_umount.
disk_layout_mount() {
	_disk="$1" _mnt="$2"
	# The mkfs command lines are the ones format_partition_with_filesystem() in
	# pmb/install/format.py builds for these two filesystems: mkfs.ext2 for the
	# boot partition (the schema default), mkfs.ext4 for the root, both with -F
	# -q and the pmOS_* label. It adds -i 8192 only when formatting an image
	# file, to keep a small image from running out of inodes; our images are
	# 4 GiB with ~90k files, so the default ratio is already enough.
	log "Formatting $BOOT_PART ($BOOT_FS, label pmOS_boot)"
	command -v "mkfs.$BOOT_FS" >/dev/null ||
		die "no mkfs.$BOOT_FS on this system; set BOOT_FS to a filesystem it can create"
	"mkfs.$BOOT_FS" -F -q -L pmOS_boot "$BOOT_PART" >/dev/null
	BOOT_UUID="$(blkid -s UUID -o value "$BOOT_PART")"
	log "Formatting $ROOT_PART (ext4, label pmOS_root)"
	mkfs.ext4 -F -q -L pmOS_root "$ROOT_PART" >/dev/null
	ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
	[ -n "$BOOT_UUID" ] && [ -n "$ROOT_UUID" ] || die "could not read partition UUIDs on $_disk"
	log "Root UUID: $ROOT_UUID"

	mkdir -p "$_mnt"
	mount "$ROOT_PART" "$_mnt"
	mkdir -p "$_mnt/boot"
	mount "$BOOT_PART" "$_mnt/boot"
}

disk_layout_umount() {
	_mnt="$1"
	mountpoint -q "$_mnt/boot" && umount "$_mnt/boot" || true
	mountpoint -q "$_mnt" && umount "$_mnt" || true
}

# /etc/fstab for the layout above (both filesystems, by UUID).
#
# Options as create_fstab() in pmb/install/_install.py writes them: plain
# "defaults" for the root and nodev,nosuid,noexec for /boot - which is also how
# the running Nura system mounts its /boot. The pass column is the one
# difference: pmbootstrap writes 0 0 because its init takes care of fsck, while
# Debian expects 1 for the root and 2 for the others so systemd-fsck orders them.
disk_layout_fstab() {
	_mnt="$1"
	cat >"$_mnt/etc/fstab" <<EOF
UUID=$ROOT_UUID	/	ext4	defaults	0 1
UUID=$BOOT_UUID	/boot	$BOOT_FS	nodev,nosuid,noexec	0 2
EOF
}

# The kernel partition is 128 MiB; refuse to write an image that does not fit,
# as boot-deploy does (check_image_size in boot-deploy-functions.sh).
kpart_fits() {
	_img="$1" _part="$2"
	_img_size="$(stat -c %s "$_img")"
	_part_size="$(blockdev --getsize64 "$_part")"
	[ "$_img_size" -le "$_part_size" ] ||
		die "the kpart ($_img_size bytes) does not fit in $_part ($_part_size bytes)"
	log "kpart $((_img_size / 1024 / 1024)) MiB fits in $_part ($((_part_size / 1024 / 1024)) MiB)"
}

# Verify the signed FIT when futility is available (package
# vboot-kernel-utils). It reads the partition or the image file directly.
kpart_verify() {
	_img="$1"
	if ! command -v futility >/dev/null 2>&1; then
		warn "futility not installed (vboot-kernel-utils): skipping kpart verification"
		return 0
	fi
	if ! _out="$(futility show "$_img" 2>/dev/null)"; then
		die "futility rejected the kpart: $_img"
	fi
	_ver="$(printf '%s\n' "$_out" | sed -n 's/^ *Header version: *//p' | head -1)"
	# Not `printf ... | grep -q`: with `pipefail` the SIGPIPE grep causes when it
	# exits on the match can make the pipeline report failure (the same pitfall is
	# documented in scripts/check-system.sh).
	case "$_out" in
		*'Body verification succeeded'*)
			log "futility: dev-signed FIT, preamble ${_ver:-?}, body verification succeeded"
			;;
		*)
			die "futility could not verify the kpart body: $_img"
			;;
	esac
}