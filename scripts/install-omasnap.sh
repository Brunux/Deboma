#!/bin/bash
# Install the staged omasnap (scripts/build-omasnap.sh) into a rootfs.
#
# Usage: install-omasnap.sh [ROOTFS]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ -n "${1:-}" ] && ROOTFS="$1"

if [ "$(id -u)" -ne 0 ]; then
	# sudo does not preserve the caller's environment: forward every resolved
	# build input, or a build root outside $HOME and a ROOTFS override would be
	# silently replaced by their defaults.
	exec sudo -n \
		BUILD_ROOT="$BUILD_ROOT" WORK_DIR="$WORK_DIR" SRC_DIR="$SRC_DIR" \
		DEVICE="$DEVICE" UI="$UI" ROOTFS="$ROOTFS" OMASNAP_STAGE="$OMASNAP_STAGE" \
		"$(readlink -f "$0")" "${1:-}"
fi

[ -d "$ROOTFS" ] || die "rootfs not found: $ROOTFS (run build-rootfs.sh first)"
[ -x "$OMASNAP_STAGE/usr/bin/omasnap" ] ||
	die "staged omasnap not found: $OMASNAP_STAGE (run build-omasnap.sh first)"

log "Installing omasnap into $ROOTFS"
install -Dm755 "$OMASNAP_STAGE/usr/bin/omasnap" "$ROOTFS/usr/bin/omasnap"
# The annotation editor's own entry ("Open with omasnap") and the font licenses
# the binary is built against. One install per file rather than a copy of the
# staged share tree: `cp -a "$stage/usr/share/." "$ROOTFS/usr/share/"` carries
# the *source* directory's owner and mode onto the destination directory itself,
# so the image would come out with /usr/share and /usr/share/applications owned
# by - and 0775 instead of Debian's 0755 - the build user.
install -Dm644 "$OMASNAP_STAGE/usr/share/applications/omasnap.desktop" \
	"$ROOTFS/usr/share/applications/omasnap.desktop"
for _license in "$OMASNAP_STAGE"/usr/share/licenses/omasnap/*; do
	[ -f "$_license" ] || continue
	install -Dm644 "$_license" "$ROOTFS/usr/share/licenses/omasnap/${_license##*/}"
done
command -v update-desktop-database >/dev/null &&
	update-desktop-database "$ROOTFS/usr/share/applications" || true

log "omasnap installed: ${ROOTFS%/}/usr/bin/omasnap"
