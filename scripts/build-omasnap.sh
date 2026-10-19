#!/bin/bash
# Build omasnap and stage it for the image.
#
# omasnap (github.com/omacom/omasnap) is the screenshot and annotation overlay
# the desktop's capture commands exec: omarchy-capture-screenshot is a thin
# wrapper whose last line is `exec omasnap`, so Print and SUPER+SHIFT+S do
# nothing at all without the binary, and Debian has no package for it. Debian's
# alternatives (grim+slurp, swappy) are different programs that the capture menu
# never calls. The port therefore builds upstream's own tool, from the tag
# pinned in uis/<ui>/omasnap.version.
#
# It captures through ext-image-copy-capture (Hyprland advertises it) and paints
# with Qt6, LayerShellQt, libdeflate and wayland-client; every one of those is a
# Debian package that scripts/00-deps.sh installs. The result is a staged tree,
# installed into a rootfs by scripts/install-omasnap.sh - the same split as the
# kernel:
#   $OMASNAP_STAGE/usr/bin/omasnap
#   $OMASNAP_STAGE/usr/share/applications/omasnap.desktop
set -euo pipefail
. "$(dirname "$0")/lib.sh"

VERSION_FILE="$UI_DIR/omasnap.version"
[ -f "$VERSION_FILE" ] ||
	die "$VERSION_FILE is missing: UI '$UI' pins no omasnap version (its capture commands need it)"
OMASNAP_VERSION="$(tr -d '[:space:]' <"$VERSION_FILE")"
OMASNAP_SRC="${OMASNAP_SRC:-$SRC_DIR/omasnap-$OMASNAP_VERSION}"

# Jobs: the reasoning is build-kernel.sh's, with a larger per-job peak because
# every translation unit here includes the Qt headers. A quiet machine gets all
# the cores; a machine with the desktop running gets fewer instead of swapping
# until the OOM killer removes a compiler. JOBS=<n> overrides, and the log line
# records what was chosen.
if [ -z "${JOBS:-}" ]; then
	mem_avail_mib=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
	reserve_mib=1024 # left to the desktop, the shell and the linker
	per_job_mib=700  # Qt-heavy C++ translation unit peak
	JOBS=$(((mem_avail_mib - reserve_mib) / per_job_mib))
	if [ "$JOBS" -lt 1 ]; then JOBS=1; fi
	if [ "$JOBS" -gt "$(nproc)" ]; then JOBS=$(nproc); fi
fi

# pkg-config and the header check rather than a package-manager query, so the
# answer means the same on an apt host and on an apk one. LayerShellQt ships a
# CMake package and headers but no pkg-config file.
missing=""
for tool in cmake ninja pkg-config; do
	command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
for mod in Qt6Widgets libdeflate wayland-client; do
	pkg-config --exists "$mod" 2>/dev/null || missing="$missing pkg:$mod"
done
[ -d /usr/include/LayerShellQt ] || missing="$missing LayerShellQt-headers"
[ -z "$missing" ] ||
	die "missing omasnap build dependencies:$missing (scripts/00-deps.sh installs them)"

if [ ! -d "$OMASNAP_SRC/.git" ]; then
	log "Downloading omasnap v$OMASNAP_VERSION"
	git clone --depth 1 --branch "v$OMASNAP_VERSION" \
		https://github.com/omacom/omasnap "$OMASNAP_SRC"
fi

log "Configuring omasnap $OMASNAP_VERSION"
cmake -S "$OMASNAP_SRC" -B "$OMASNAP_SRC/build" -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr \
	-DBUILD_TESTING=OFF

log "Building omasnap $OMASNAP_VERSION ($JOBS jobs)"
ninja -C "$OMASNAP_SRC/build" -j"$JOBS"

log "Staging omasnap into $OMASNAP_STAGE"
rm -rf "$OMASNAP_STAGE"
DESTDIR="$OMASNAP_STAGE" cmake --install "$OMASNAP_SRC/build"
[ -x "$OMASNAP_STAGE/usr/bin/omasnap" ] || die "the build staged no usr/bin/omasnap"

# It answers --version before it initialises Qt, and the Qt noise that follows
# is expected here: a build host has no compositor to talk to.
"$OMASNAP_STAGE/usr/bin/omasnap" --version 2>/dev/null || true

log "omasnap staged: $OMASNAP_STAGE/usr/bin/omasnap"
