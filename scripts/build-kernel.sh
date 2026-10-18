#!/bin/bash
# Build the kernel for the selected device's kernel flavor and stage it.
#
# Source: mainline tarball from cdn.kernel.org + kernels/<flavor>/patches
# (applied in the order listed in kernels/<flavor>/patches/series).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

STAGE="$KERNEL_STAGE"
# Jobs for make. The core count alone is not a safe default: this machine is an
# 8-core SoC with 4 GiB of RAM, and a -j8 clang build next to the running desktop
# swaps until the OOM killer takes a compiler and the whole build with it. Cap the
# default by what the kernel believes it can hand out, keeping a reserve for the
# desktop: a quiet machine gets every core, a loaded one gets fewer. JOBS=<n>
# still overrides, and the log line below records what was used.
if [ -z "${JOBS:-}" ]; then
	mem_avail_mib=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
	reserve_mib=768  # left to the desktop, the shell and the linkers
	per_job_mib=192  # typical clang peak on this kernel tree
	JOBS=$(((mem_avail_mib - reserve_mib) / per_job_mib))
	if [ "$JOBS" -lt 2 ]; then JOBS=2; fi
	if [ "$JOBS" -gt "$(nproc)" ]; then JOBS=$(nproc); fi
fi
SERIES="$KERNEL_PATCH_DIR/series"

fetch_and_prepare() {
	mkdir -p "$SRC_DIR"
	if [ ! -f "$SRC_DIR/$KERNEL_TARBALL" ]; then
		log "Downloading $KERNEL_URL"
		curl -fSL -o "$SRC_DIR/$KERNEL_TARBALL" "$KERNEL_URL"
	fi
	if [ -f "$KERNEL_SRC/.prepared" ]; then
		return 0
	fi
	log "Extracting $KERNEL_TARBALL"
	rm -rf "$KERNEL_SRC"
	tar xf "$SRC_DIR/$KERNEL_TARBALL" -C "$SRC_DIR"

	log "Applying patches"
	if [ -f "$SERIES" ]; then
		while read -r p; do
			case "$p" in '' | '#'*) continue ;; esac
			log "  $p"
			patch -d "$KERNEL_SRC" -p1 --no-backup-if-mismatch <"$KERNEL_PATCH_DIR/$p"
		done <"$SERIES"
	fi
	cp "$KERNEL_CONFIG" "$KERNEL_SRC/.config"
	touch "$KERNEL_SRC/.prepared"
}

build_kernel() {
	log "Building kernel $KERNEL_RELEASE ($JOBS jobs)"
	make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 -j"$JOBS"
}

install_kernel() {
	log "Installing kernel into $STAGE"
	rm -rf "$STAGE"
	mkdir -p "$STAGE/boot"
	make -C "$KERNEL_SRC" ARCH="$KERNEL_ARCH" LLVM=1 \
		INSTALL_PATH="$STAGE/boot" \
		INSTALL_MOD_PATH="$STAGE" \
		INSTALL_MOD_STRIP=1 \
		INSTALL_DTBS_PATH="$STAGE/boot/dtbs" \
		zinstall modules_install dtbs_install
	cp "$KERNEL_SRC/.config" "$STAGE/boot/config"
	cp "$KERNEL_SRC/System.map" "$STAGE/boot/System.map" 2>/dev/null || true
	log "Kernel release: $(cat "$KERNEL_SRC/include/config/kernel.release")"
	ls -la "$STAGE/boot"
}

log "Device : $DEVICE"
log "Kernel : $KERNEL_FLAVOR $KERNEL_VERSION ($KERNEL_ARCH)"

fetch_and_prepare
build_kernel
install_kernel
log "Kernel build done: $STAGE"
