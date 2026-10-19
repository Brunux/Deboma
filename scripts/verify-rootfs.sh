#!/bin/bash
# Off-device verification of a rootfs built by this repository.
#
# The host-side counterpart of scripts/check-system.sh: that one runs *on the
# booted device* and measures the hardware; this one runs on the build host
# against $ROOTFS and refuses to call a tree good while the build is still
# half-finished. It needs no root and changes nothing - it reads files, compares
# the declared package lists against the rootfs's own dpkg database, and asserts
# the shape the build is supposed to have (the overlay files and their modes, the
# commands setup.sh puts on PATH, the generated menu extension, the staged
# omasnap, the revision and the shipped repository copy).
#
# A rootfs that passes here can still fail on the device (firmware, the boot
# chain, a driver): what it cannot be is *incomplete*, which is the failure that
# costs a card, a reboot and a kernel partition to find. Run it after
# build-rootfs.sh (and install-kernel.sh / install-omasnap.sh when they are part
# of the flow) and before make-image.sh / write-sd.sh.
#
# Usage:
#   scripts/verify-rootfs.sh [ROOTFS]
#
# ROOTFS defaults to $WORK_DIR/rootfs-$DEVICE, as in the rest of the repository;
# every build input (BUILD_ROOT, WORK_DIR, ROOTFS, DEVICE, UI, USERNAME) is
# honoured, and each is reported, because verifying the wrong tree is easy.
#
# Exit status: 0 when nothing FAILs, 1 otherwise.
#
# Pitfall, with `pipefail` set: never test the status of `producer | grep -q ...`
# (see scripts/check-system.sh) - capture the output and use a here-string.
set -uo pipefail

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
# lib.sh sets `set -e`, which would abort on the first check that legitimately
# fails; the report has to collect every FAIL.
set +e

ROOTFS="${1:-$ROOTFS}"
USERNAME="${USERNAME:-brunux}"
HOME_DIR="$ROOTFS/home/$USERNAME"

PASS=0 WARN=0 FAIL=0
if [ -t 1 ]; then
	C_OK=$'\033[1;32m' C_WARN=$'\033[1;33m' C_FAIL=$'\033[1;31m'
	C_HEAD=$'\033[1;34m' C_DIM=$'\033[1;30m' C_OFF=$'\033[0m'
else
	C_OK= C_WARN= C_FAIL= C_HEAD= C_DIM= C_OFF=
fi
ok()      { PASS=$((PASS + 1)); printf '  %sOK%s    %s\n' "$C_OK" "$C_OFF" "$*"; }
warn()    { WARN=$((WARN + 1)); printf '  %sWARN%s  %s\n' "$C_WARN" "$C_OFF" "$*"; }
fail()    { FAIL=$((FAIL + 1)); printf '  %sFAIL%s  %s\n' "$C_FAIL" "$C_OFF" "$*"; }
skip()    { printf '  %sSKIP%s  %s\n' "$C_DIM" "$C_OFF" "$*"; }
info()    { printf '  ----  %s\n' "$*"; }
section() { printf '\n%s==> %s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
check()   { # check <description> <command...>
	desc="$1"; shift
	if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

printf 'rootfs verification  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
info "rootfs   $ROOTFS"
info "device   $DEVICE   ui $UI   kernel $KERNEL_RELEASE   user $USERNAME"

if [ ! -d "$ROOTFS" ]; then
	fail "no rootfs at $ROOTFS (build it first: scripts/build-rootfs.sh)"
	printf '\n==> Summary  0 OK, 0 WARN, 1 FAIL\n'
	exit 1
fi

# ---------------------------------------------------------------------------
section "rootfs"
# ---------------------------------------------------------------------------
# A root filesystem needs the mount points its initramfs moves `/dev`, `/proc`
# and `/sys` into before it hands over to systemd. install-emmc.sh has already
# been bitten by this: a copy that drops them boots the kernel, mounts the root
# read-write and stops at `run-init: opening console: No such file or directory`
# with a black screen, which reads as a firmware problem.
for _d in dev proc sys run mnt media tmp; do
	check "$_d/ exists" test -d "$ROOTFS/$_d"
done
check "/sbin/init resolves" test -x "$ROOTFS/sbin/init"
check "/etc/fstab is present" test -s "$ROOTFS/etc/fstab"
check "the Debian suite is installed (/etc/debian_version)" test -s "$ROOTFS/etc/debian_version"
check "the dpkg database is present" test -s "$ROOTFS/var/lib/dpkg/status"
check "systemd is installed" test -x "$ROOTFS/usr/lib/systemd/systemd"
check "apt can run (the sources list)" test -s "$ROOTFS/etc/apt/sources.list"

if [ -s "$ROOTFS/etc/shadow" ]; then
	# build-rootfs.sh must ship no password hash for the desktop user beyond the
	# one its password is set with; root locking is Debian's own business.
	check "the desktop user exists" grep -q "^$USERNAME:" "$ROOTFS/etc/passwd"
else
	fail "/etc/shadow is missing"
fi

# ---------------------------------------------------------------------------
section "kernel and omasnap (staged separately)"
# ---------------------------------------------------------------------------
# These two are not part of build-rootfs.sh: install-kernel.sh and
# install-omasnap.sh copy them in afterwards, so a rootfs built by the bare
# rootfs step is *incomplete but correct* - a WARN with the command to run, not
# a FAIL.
if [ -f "$ROOTFS/boot/vmlinuz-$KERNEL_RELEASE" ]; then
	ok "the kernel is staged (/boot/vmlinuz-$KERNEL_RELEASE)"
	check "its modules are staged (/lib/modules/$KERNEL_RELEASE)" \
		test -d "$ROOTFS/lib/modules/$KERNEL_RELEASE"
	check "the initramfs is present" \
		bash -c "ls '$ROOTFS'/boot/initrd.img-* >/dev/null 2>&1"
else
	warn "no kernel staged: run scripts/install-kernel.sh $ROOTFS"
fi
if [ -x "$ROOTFS/usr/bin/omasnap" ]; then
	ok "omasnap is installed (Print and SUPER+SHIFT+S capture)"
else
	warn "omasnap is not installed: run scripts/install-omasnap.sh $ROOTFS"
fi

# ---------------------------------------------------------------------------
section "overlay files ($UI)"
# ---------------------------------------------------------------------------
# Every file uis/<ui>/files/ ships is checked against the rootfs with the mode it
# carries in the repository, so a new file cannot be added to the overlay and
# silently not arrive - nor arrive with `cp -a` damage (see AGENTS.md: copying a
# staged tree with `cp -a` rewrites the *destination* directory's owner and mode).
_ui_files=0
_bad=""
if [ -d "$UI_DIR/files" ]; then
	while IFS= read -r -d '' _src; do
		_rel="${_src#"$UI_DIR"/files/}"
		_ui_files=$((_ui_files + 1))
		case "$_rel" in
		home/*)
			# files/home/ is merged into /home/$USERNAME and owned by it.
			_owner="$USERNAME"
			;;
		*)
			# files/etc and files/usr arrive as root (rootfs-setup.sh chowns the
			# staged tree to root:root before it copies it in).
			_owner="root"
			;;
		esac
		_mode="$(stat -c '%a' "$_src")"
		_got="$(stat -c '%a %U' "$ROOTFS/$_rel" 2>/dev/null || true)"
		[ "$_got" = "$_mode $_owner" ] || _bad="$_bad $_rel(want $_mode $_owner, got ${_got:-nothing})"
	done < <(find "$UI_DIR/files" -type f -print0 | sort -z)
fi
if [ -n "$_bad" ]; then
	fail "overlay file(s) missing or with the wrong mode/owner:$_bad"
elif [ "$_ui_files" -gt 0 ]; then
	ok "$_ui_files overlay file(s) match the modes uis/$UI ships"
else
	warn "uis/$UI/files is empty or missing: nothing was overlaid"
fi

# The specific failures the port has hit, named so the report says what breaks:
check "ttfx is executable (the screensaver's renderer)" test -x "$ROOTFS/usr/local/bin/ttfx"
check "the lock screen's PAM service is installed" \
	test -s "$ROOTFS/etc/pam.d/omarchy-lock-password"
check "the lock's PAM stack uses Debian's common-auth" \
	grep -q 'common-auth' "$ROOTFS/etc/pam.d/omarchy-lock-password"
check "the screensaver art is vendored" test -s "$ROOTFS/usr/share/omarchy/logo.txt"
check "the About art is vendored" test -s "$ROOTFS/usr/share/omarchy/icon.txt"
check "the backlight udev rule is installed" \
	test -s "$ROOTFS/etc/udev/rules.d/90-brightnessctl.rules"
check "the Nerd Font alias is installed" \
	test -s "$ROOTFS/etc/fonts/conf.d/50-omarchy-debian-fonts.conf"
check "the keyd config is installed" test -s "$ROOTFS/etc/keyd/default.conf"

# ---------------------------------------------------------------------------
section "commands setup.sh owns ($UI)"
# ---------------------------------------------------------------------------
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
check "the vendored tree is installed ($OMARCHY_PATH)" \
	test -d "$ROOTFS$OMARCHY_PATH/bin"
# A representative pair per direction; the full list is EXCLUDE in
# uis/<ui>/setup.sh, which is what generates both the PATH and the hidden rows.
for _c in omarchy omarchy-theme-set omarchy-screensaver omarchy-menu-keybindings \
	omarchy-transcode omarchy-update-time omarchy-language; do
	check "on PATH: $_c" test -x "$ROOTFS/usr/bin/$_c"
done
for _c in omarchy-pkg-add omarchy-update omarchy-setup-input omarchy-apply-lock \
	omarchy-channel-set omarchy-channel-current omarchy-provision-first-run; do
	check "left off PATH: $_c" bash -c "! test -e '$ROOTFS/usr/bin/$_c'"
done
# The link must resolve *inside the rootfs*, not to a path in this checkout: a
# link written with an absolute host path still looks executable here and lands
# dangling on the device.
_dangling=""
while IFS= read -r -d '' _l; do
	_t="$(readlink "$_l")"
	case "$_t" in
	"$OMARCHY_PATH"/*) ;;
	*) _dangling="$_dangling ${_l##*/}" ;;
	esac
done < <(find "$ROOTFS/usr/bin" -maxdepth 1 -name 'omarchy-*' -type l -print0 2>/dev/null)
if [ -z "$_dangling" ]; then
	ok "every /usr/bin/omarchy-* link points into $OMARCHY_PATH"
else
	fail "link(s) pointing somewhere else:$_dangling"
fi

# ---------------------------------------------------------------------------
section "the desktop user's home"
# ---------------------------------------------------------------------------
EXT="$HOME_DIR/.config/omarchy/extensions/omarchy-menu.jsonc"
check "the menu extension was generated" test -s "$EXT"
check "the Share submenu is hidden (by row id)" grep -q 'trigger.share' "$EXT"
check "the Update > Channel rows are hidden" grep -q 'update.channel.stable' "$EXT"
check "the Update > Time row is not hidden" bash -c "! grep -q '\"update.time\"' '$EXT'"
check "the screensaver branding is seeded" \
	test -s "$HOME_DIR/.config/omarchy/branding/screensaver.txt"
check "the About branding is seeded" test -s "$HOME_DIR/.config/omarchy/branding/about.txt"
check "~/.config/omarchy/themes exists (omarchy theme list)" \
	test -d "$HOME_DIR/.config/omarchy/themes"
check "~/.bashrc sources Omarchy's shell environment" \
	bash -c "grep -q 'source .*omarchy/default/bashrc' '$HOME_DIR/.bashrc'"
check "bat is reachable by its Arch name" test -e "$ROOTFS/usr/local/bin/bat"
check "shell.json is seeded" test -s "$HOME_DIR/.config/omarchy/shell.json"
check "the touchpad scrolls naturally (port default in ~/.config/hypr/input.lua)" \
	grep -q 'omarchy-debian: natural scroll' "$HOME_DIR/.config/hypr/input.lua"
check "first-run provisioning is marked done (no retry at login)" \
	test -f "$HOME_DIR/.local/state/omarchy/done/first-run-user"
# The extension hides nothing when it is empty; what it hides is the build's own
# EXCLUDE list, so only a positive count is asserted here (the exact number is
# printed by setup.sh at build time, and moves with the pinned menu).
_hidden="$(grep -c 'when":"false' "$EXT" 2>/dev/null)"
if [ "${_hidden:-0}" -gt 0 ]; then
	info "$_hidden menu row(s) hidden by the extension"
else
	fail "the menu extension hides no rows: the Install/Remove/Update rows that cannot work are visible"
fi

# ---------------------------------------------------------------------------
section "declared packages"
# ---------------------------------------------------------------------------
# The lists are read from the copy of this repository *the image ships*, not from
# the working tree: that copy is what the release carries, and checking the
# checkout would hide a tree that was staged before a list changed.
SHIPPED_REPO="$(ls -d "$ROOTFS"/home/*/Dev/"$(basename "$REPO_DIR")" 2>/dev/null | head -n1)"
if [ -z "$SHIPPED_REPO" ]; then
	warn "no shipped repository copy under $ROOTFS/home/*/Dev: cannot check the declared lists"
else
	info "lists from $SHIPPED_REPO"
	# The UI this image was built with, taken from its own revision file, so the
	# other uis/*/packages.list is never checked against this rootfs.
	_ui="$UI"
	if [ -s "$ROOTFS/etc/debian-aarch64-revision" ]; then
		_ui="$(sed -n 's/^ui //p' "$ROOTFS/etc/debian-aarch64-revision" | head -n1)"
	fi
	_ui_lists="$SHIPPED_REPO"/uis/*/packages.list
	[ -n "$_ui" ] && [ -f "$SHIPPED_REPO/uis/$_ui/packages.list" ] &&
		_ui_lists="$SHIPPED_REPO/uis/$_ui/packages.list"
	# Installed set straight from the rootfs's dpkg database: no chroot, no
	# dpkg-query, no root (the status file is the same data).
	_installed="$(awk '/^Package: /{p=$2} /^Status: install ok installed$/{print p}' \
		"$ROOTFS/var/lib/dpkg/status")"
	_count=0
	_missing=""
	for _list in "$SHIPPED_REPO"/packages/*.list "$SHIPPED_REPO"/devices/*/packages.list $_ui_lists; do
		[ -f "$_list" ] || continue
		while read -r _pkg; do
			case "$_pkg" in '' | '#'*) continue ;; esac
			_count=$((_count + 1))
			grep -qxF "$_pkg" <<<"$_installed" || _missing="$_missing $_pkg"
		done <"$_list"
	done
	if [ -z "$_missing" ]; then
		ok "all $_count declared package(s) (uis/$_ui) are installed"
	else
		fail "declared but not installed:$_missing"
	fi
fi

# ---------------------------------------------------------------------------
section "revision"
# ---------------------------------------------------------------------------
if [ -s "$ROOTFS/etc/debian-aarch64-revision" ]; then
	sed 's/^/  ----  /' "$ROOTFS/etc/debian-aarch64-revision"
	_built="$(sed -n 's/^commit //p' "$ROOTFS/etc/debian-aarch64-revision" | head -n1)"
	# -c safe.directory: this also runs from make-image.sh / write-sd.sh, which
	# re-exec through sudo, and git refuses a tree owned by another user.
	_head="$(git -C "$REPO_DIR" -c safe.directory="$REPO_DIR" rev-parse --short HEAD 2>/dev/null)"
	if [ -n "$_built" ] && [ -n "$_head" ] && [ "$_built" != "$_head" ]; then
		warn "built from $_built, HEAD is $_head: rebuild before publishing this tree"
	elif [ -n "$_head" ]; then
		ok "the tree was built from HEAD ($_built)"
	fi
	if [ -n "$(git -C "$REPO_DIR" -c safe.directory="$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
		warn "the working tree has uncommitted changes, which the image does not carry"
	fi
else
	fail "/etc/debian-aarch64-revision is missing: the image does not say what it is"
fi

# ---------------------------------------------------------------------------
printf '\n%s==> Summary  %d OK, %d WARN, %d FAIL%s\n' "$C_HEAD" "$PASS" "$WARN" "$FAIL" "$C_OFF"
printf 'Not checked here: the hardware, the firmware and the boot chain - that is\n'
printf 'scripts/check-system.sh on the booted system.\n'
[ "$FAIL" -eq 0 ]
