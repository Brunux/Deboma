#!/bin/bash
# Install host build dependencies.
#
# The build system targets an Alpine host (apk), which is what the reference
# machine ran when the first release was cut; the same tools are installable
# from Debian (apt), which is what a Hayato running *this* port is.  Both paths
# install the same set: a Linux kernel built with LLVM=1, debootstrap for the
# target rootfs, and the ChromeOS GPT / depthcharge tools.
#
# Run as a normal user (it re-execs itself through sudo) or as root.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

if [ "$(id -u)" -ne 0 ]; then
	exec sudo -n "$(readlink -f "$0")" "$@"
fi

if command -v apk >/dev/null 2>&1; then
	log "Installing host build dependencies (apk)"
	apk add --no-cache \
		bash bc bison flex \
		clang clang-libclang lld llvm \
		rust rust-bindgen rust-src rustfmt \
		openssl openssl-dev elfutils-dev pahole \
		perl python3 \
		findutils rsync cpio \
		xz zstd lz4 gzip \
		git curl wget \
		dtc kmod \
		make gcc musl-dev binutils pkgconf \
		debootstrap \
		cgpt vboot-utils depthcharge-tools \
		e2fsprogs dosfstools parted gptfdisk \
		util-linux
elif command -v apt-get >/dev/null 2>&1; then
	# Debian names differ in a few places, all of them deliberate:
	#   * musl-dev has no role here - Debian's libc is glibc and build-essential
	#     already pulls libc6-dev in;
	#   * rust-bindgen is `bindgen`, elfutils-dev is `libelf-dev` (elfutils) +
	#     `dwarves` (pahole) + `libelf-dev`'s headers, openssl-dev is
	#     `libssl-dev`;
	#   * futility is `vboot-kernel-utils` and cgpt is `cgpt`: vboot-utils only
	#     ships crossystem, so installing it alone leaves both missing;
	#   * gptfdisk is `gdisk`, dtc is `device-tree-compiler`.
	# clang/lld/llvm build the kernel with LLVM=1; rustc/rust-src/bindgen are
	# needed by CONFIG_RUST=y and dwarves by CONFIG_DEBUG_INFO_BTF=y.
	log "Installing host build dependencies (apt)"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y \
		bash bc bison flex \
		build-essential clang lld llvm libclang-dev \
		rustc rust-src cargo bindgen \
		libssl-dev libelf-dev dwarves \
		perl python3 \
		findutils rsync cpio \
		xz-utils zstd lz4 gzip \
		git curl wget ca-certificates \
		device-tree-compiler kmod \
		make pkgconf \
		debootstrap \
		cgpt vboot-kernel-utils depthcharge-tools \
		e2fsprogs dosfstools parted gdisk \
		util-linux
else
	die "no supported package manager found (apk or apt-get)"
fi

log "Done. Tool versions:"
clang --version | head -1
ld.lld --version
rustc --version 2>/dev/null || true
bindgen --version 2>/dev/null || true
debootstrap --version 2>/dev/null || true
