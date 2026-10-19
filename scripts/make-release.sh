#!/bin/bash
# Build every asset of one GitHub release into a directory:
#
#   <device>.img             the disk image (make-image.sh); stays on this host
#   <device>.img.xz          the same image, compressed for download
#   <device>-rootfs.tar.zst  the root filesystem as a tarball
#   <device>.vmlinuz.kpart   the kernel partition that matches the image
#   SHA256SUMS               hashes of the published files, nothing else
#   PUBLISHED                the published files, one per line (what to attach)
#
# Usage: make-release.sh [OUTDIR]     (default $WORK_DIR/release-<device>)
#
# The release notes are not generated here: they are written by hand, kept in
# docs/releases/ so they are versioned like everything else, and reused for the
# annotated tag and for the GitHub release.
#
# Four things are worth knowing about the assets:
#
#   * GitHub refuses a release asset of 2 GiB or more ("size must be less than
#     2147483648"), and the rootfs tarball went past that line the first time it
#     was published. An asset that does not fit is split into equal parts
#     (<name>.part-00, .part-01, ...) and the original is removed: the parts are
#     the published form of it, and they are rejoined with `cat`. The image and
#     the kpart fit today and go through the same check, so this does not have to
#     be discovered again by whoever publishes the release that outgrows it.
#
#   * Everything that is published is sanitized and asserted clean
#     (scripts/lib-dist.sh): a released image must not carry the maintainer's
#     Wi-Fi PSKs, host keys or machine id.
#   * The kpart embeds `root=UUID=...`, so it is the kernel partition of *this*
#     image and nothing else. It is shipped because it makes p1 reproducible from
#     the release alone; anyone writing their own card gets a kpart that matches
#     their partitions from scripts/write-sd.sh or scripts/install-kpart.sh,
#     which build it from the disk they are writing to.
#   * The tarball is the root filesystem with /boot inside it (the layout mounts
#     the boot partition there), for writing a card by hand. It arrives split, so
#     it is reassembled first (only the parts are published, never the whole
#     file):
#       cat <device>-rootfs.tar.zst.part-* | zstd -dc |
#         sudo tar --acls --xattrs -xpf - -C <dir>
#       sudo ROOTFS=<dir> scripts/write-sd.sh <device>
#     which generates the fstab and the kpart for those partitions. Its own
#     /etc/fstab is the unconfigured one the build leaves behind.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-cgpt.sh"
. "$(dirname "$0")/lib-dist.sh"

OUTDIR="${1:-$WORK_DIR/release-$DEVICE}"
IMAGE_SIZE_MIB="${IMAGE_SIZE_MIB:-6144}"
export IMAGE_SIZE_MIB

# build-rootfs.sh documents the same pitfall: sudo drops the environment, so
# every resolved input is forwarded explicitly.
if [ "$(id -u)" -ne 0 ]; then
	exec sudo -n \
		BUILD_ROOT="$BUILD_ROOT" WORK_DIR="$WORK_DIR" SRC_DIR="$SRC_DIR" \
		DEVICE="$DEVICE" ROOTFS="$ROOTFS" \
		IMAGE_SIZE_MIB="$IMAGE_SIZE_MIB" "$(readlink -f "$0")" "$OUTDIR"
fi

IMG="$OUTDIR/$DEVICE.img"
TARBALL="$OUTDIR/$DEVICE-rootfs.tar.zst"
KPART_OUT="$OUTDIR/$DEVICE.vmlinuz.kpart"
STAGE="$WORK_DIR/release-stage-$DEVICE"

# GitHub's release asset limit, in bytes: the API answers "size must be less
# than 2147483648" for anything from 2 GiB up.
GH_ASSET_MAX=2147483647

# Print the published path(s) of one asset: the file itself when it fits on
# GitHub, otherwise the parts it was split into, one per line. An asset is
# published either whole or split, never both, so the original is removed when it
# is split: leaving it behind would make the directory look attachable and only
# fail at the upload, which is how this was found.
#
# stdout is the manifest, so nothing here may print to it except the paths: a
# `log` without the `>&2` ends up *inside* $PUBLISHED, and the checksum loop then
# reads the banner as a filename ("sha256sum: '': No such file or directory" was
# v0.2.0's last output for exactly that reason).
publish_parts() {
	local file size parts chunk
	file="$1"
	size="$(stat -c %s "$file")"
	if [ "$size" -le "$GH_ASSET_MAX" ]; then
		printf '%s\n' "$file"
		return 0
	fi
	# As few parts as fit, as equal as the size allows: the 2.2 GiB tarball comes
	# out as two parts of ~1.1 GiB, each small enough to be resumed on its own.
	parts=$(( (size + GH_ASSET_MAX - 1) / GH_ASSET_MAX ))
	chunk=$(( (size + parts - 1) / parts ))
	log "Splitting $(basename "$file") ($size bytes) into $parts parts of $chunk (GitHub's limit is $GH_ASSET_MAX)" >&2
	split -b "$chunk" -d -a 2 "$file" "$file.part-"
	rm -f "$file"
	ls "$file".part-*
}

mkdir -p "$OUTDIR"
[ -d "$ROOTFS" ] || die "rootfs not found: $ROOTFS (run build-rootfs.sh first)"

log "1/4 Image"
"$REPO_DIR/scripts/make-image.sh" "$IMG" "$IMAGE_SIZE_MIB"

log "2/4 Compressing the image"
xz -T0 -6 -f -k "$IMG"

log "3/4 Root filesystem tarball"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# Same exclusion as the image: the profiles must not be copied and then deleted,
# or their bytes survive in the staging filesystem (scripts/lib-dist.sh).
# A leftover mount under the rootfs is refused for the same reason it is in
# make-image.sh: rsync would copy the live host's pseudo-filesystems.
_stale_mounts="$(findmnt -rn -o TARGET 2>/dev/null | grep -F "$ROOTFS/" || true)"
[ -z "$_stale_mounts" ] ||
	die "something is mounted under $ROOTFS ($_stale_mounts); unmount it first"
EXCLUDES="$WORK_DIR/dist-excludes-$DEVICE.txt"
dist_write_excludes "$EXCLUDES"
rsync -aHAX --delete --exclude-from="$EXCLUDES" "$ROOTFS"/ "$STAGE"/
dist_sanitize "$STAGE"
dist_assert_clean "$STAGE"
dist_assert_no_profile_bytes "$STAGE"
# --acls/--xattrs/--xattrs-include keep what rsync -A/-X preserved, and
# --numeric-owner because the tarball is extracted as root, where the numbers
# are what count.
tar --acls --xattrs --xattrs-include='*' --numeric-owner -cpf - -C "$STAGE" . |
	zstd -T0 -12 -q -f -o "$TARBALL"
rm -rf "$STAGE"

log "4/4 kpart of the released image"
# Read the image's root UUID back instead of assuming it: the kpart must embed
# exactly the UUID the image boots with.
LOOP="$(losetup --show -f -P "$IMG")"
ROOT_UUID_IMG="$(blkid -s UUID -o value "${LOOP}p3" 2>/dev/null || true)"
losetup -d "$LOOP"
[ -n "$ROOT_UUID_IMG" ] || die "could not read the image's root UUID back from $IMG"
"$REPO_DIR/scripts/make-kpart.sh" "$ROOTFS" "$KPART_OUT" "root=UUID=$ROOT_UUID_IMG rootwait rw"
kpart_verify "$KPART_OUT"

log "Published files"
# What is attached to the release, and what SHA256SUMS covers - exactly those
# files and nothing else. The uncompressed image stays on this host: it is 6 GiB
# and `sha256sum -c SHA256SUMS` would report it missing on every download.
PUBLISHED="$OUTDIR/PUBLISHED"
: >"$PUBLISHED"
for asset in "$IMG.xz" "$TARBALL" "$KPART_OUT"; do
	publish_parts "$asset" >>"$PUBLISHED"
done
sed 's|^.*/||;s/^/  /' "$PUBLISHED"

log "Checksums"
(
	cd "$OUTDIR"
	while IFS= read -r published; do
		[ -n "$published" ] || continue
		sha256sum "$(basename "$published")"
	done <"$PUBLISHED"
) >"$OUTDIR/SHA256SUMS"
sed 's/^/  /' "$OUTDIR/SHA256SUMS"

log "Assets in $OUTDIR"
ls -lh "$OUTDIR" | sed 's/^/  /'
log "Attach SHA256SUMS and the $(wc -l <"$PUBLISHED") published file(s) above"
