#!/bin/bash
# Move NetworkManager Wi-Fi profiles between the running system and a rootfs.
#
# The profiles hold the network PSK in clear text, so they are NEVER versioned:
# they live outside the repository, in $WIFI_DIR ($BUILD_ROOT/wifi by default).
#
#   scripts/wifi.sh export [SRC]         running system -> $WIFI_DIR
#   scripts/wifi.sh import [SRC] [DEST]  $WIFI_DIR -> DEST/etc/NetworkManager/system-connections
#
# SRC defaults to /etc/NetworkManager/system-connections and DEST to $ROOTFS
# (the built rootfs). Both directions need root: the files are 0600 root.
#
# `import` drops the `interface-name=` line. The two systems name the wireless
# interface differently (Nura: wlan0, Debian/systemd: wlp1s0), and a profile
# pinned to a name that does not exist is never activated. Without the line
# NetworkManager binds the profile to any Wi-Fi device.
#
# Importing into a *running* system also needs `nmcli connection reload`.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

NM_DIR=/etc/NetworkManager/system-connections

usage() {
	sed -n '2,20p' "$0" | cut -c3-
	exit "${1:-1}"
}

# Print every profile path in a directory, one per line (names may have spaces).
list_profiles() {
	local dir="$1" f found=0
	[ -d "$dir" ] || die "not a directory: $dir"
	for f in "$dir"/*.nmconnection; do
		[ -e "$f" ] || continue
		printf '%s\n' "$f"
		found=1
	done
	[ "$found" -eq 1 ] || die "no *.nmconnection profiles in $dir"
}

do_export() {
	local src="${1:-$NM_DIR}" f n=0
	need_root
	install -d -m 700 "$WIFI_DIR"
	while IFS= read -r f; do
		install -m 600 -o root -g root "$f" "$WIFI_DIR/$(basename "$f")"
		n=$((n + 1))
	done < <(list_profiles "$src")
	log "Exported $n profile(s) to $WIFI_DIR"
}

do_import() {
	local src="${1:-$WIFI_DIR}" dest="${2:-$ROOTFS}" dir f name tmp n=0
	need_root
	[ -d "$dest" ] || die "not a directory: $dest"
	dir="$dest$NM_DIR"
	install -d -m 700 "$dir"
	while IFS= read -r f; do
		name="$(basename "$f")"
		tmp="$dir/.$name.tmp"
		sed '/^interface-name=/d' "$f" >"$tmp"
		chown root:root "$tmp"
		chmod 600 "$tmp"
		mv -f "$tmp" "$dir/$name"
		n=$((n + 1))
	done < <(list_profiles "$src")
	log "Imported $n profile(s) into $dir (interface-name dropped)"
}

case "${1:-}" in
export)
	shift
	do_export "${1:-}"
	;;
import)
	shift
	do_import "${1:-}" "${2:-}"
	;;
*)
	usage
	;;
esac
