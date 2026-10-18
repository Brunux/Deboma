#!/bin/bash
# uis/omarchy/setup.sh — runs inside the chroot, as root, after uis/omarchy/files
# has been overlaid. This is the Debian counterpart of the Omarchy installer's
# config/user steps, reduced to what a Debian base actually needs:
#
#   * the omarchy-* commands on PATH, which upstream's Arch package provides as
#     /usr/bin/omarchy-* but a checkout keeps under $OMARCHY_PATH/bin;
#   * ~/.config seeded from the vendored tree, which is what omarchy-refresh-config
#     and the install scripts do on Arch.
#
# It deliberately does not run upstream's install/ scripts: those are pacman,
# SDDM, LUKS and platform provisioning for Arch (docs/plan-omarchy.md).
set -euo pipefail

: "${USERNAME:=brunux}"
HOME="/home/$USERNAME"
OMARCHY_PATH=/usr/share/omarchy

log() { printf '\n\033[1;34m[omarchy] ==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[omarchy] WARN: %s\033[0m\n' "$*" >&2; }

[ -d "$OMARCHY_PATH/bin" ] || { warn "$OMARCHY_PATH/bin is missing, nothing to do"; exit 0; }

# Arch-only command families left off PATH: package management and updates,
# the installer/provisioner, AUR/web-app/gaming/AI installers, and the helpers
# that call pacman, yay or systemd units Debian does not have. The desktop does
# not offer features it cannot perform here; the rest of bin/ is linked.
#
# An array, matched with [[ ]], because a multi-line string in a `case` pattern
# list is not word-split by bash and would silently match nothing.
EXCLUDE=(
	'omarchy-update*'
	'omarchy-pkg-*'
	'omarchy-install-*'
	'omarchy-remove-*'
	'omarchy-migrate*'
	'omarchy-upgrade-to-quattro'
	'omarchy-reinstall*'
	'omarchy-dev-*'
	'omarchy-refresh-pacman'
	'omarchy-refresh-limine'
	'omarchy-refresh-plymouth'
	'omarchy-refresh-sddm'
	'omarchy-plymouth-*'
	'omarchy-snapshot'
	'omarchy-boot-direct'
	'omarchy-setup-direct-boot'
	'omarchy-mise-*'
	'omarchy-agent*'
	'omarchy-voxtype*'
	'omarchy-dictation*'
	'omarchy-tailscale-*'
	'omarchy-openclaw*'
	'omarchy-webapp*'
	'omarchy-games-*'
	'omarchy-drive-*'
	'omarchy-hibernation-*'
	# omarchy-cmd-present / omarchy-cmd-missing are generic `command -v`
	# predicates, not Arch tooling: the linked omarchy-launch-editor,
	# omarchy-theme-set-vscode/-browser and the battery-low hook call them, and
	# the shell defines its own copies. They must stay on PATH (the other
	# omarchy-cmd-* helpers are browser/terminal detection and are generic too).
	'omarchy-security-*'
	'omarchy-setup-security-*'
	'omarchy-remove-security-*'
	'omarchy-tui-*'
	'omarchy-locale-generate'
	'omarchy-sudo-docker'
	'omarchy-sudo-keepalive'
	'omarchy-sudo-passwordless'
	'omarchy-windows-*'
	'omarchy-upload-log'
	'omarchy-transcode'
	'omarchy-transcode-ascii'
	'omarchy-capture-webcam-list'
	'omarchy-capture-webcam-resize'
	'omarchy-apply-hardware'
	'omarchy-apply-lock'
	'omarchy-apply-system'
	'omarchy-apply-n1x-gpu-memory'
	'omarchy-gpu-screen-recorder'
	'omarchy-provision-*'
	'omarchy-system-factory-reset'
	'omarchy-system-factory-reset-finish'
	'omarchy-n1x-probe'
	'omarchy-cliamp'
)

log "Putting the omarchy-* commands on PATH (/usr/bin)"
linked=0
skipped=0
for f in "$OMARCHY_PATH"/bin/*; do
	[ -f "$f" ] || continue
	n="${f##*/}"
	skip=0
	for pat in "${EXCLUDE[@]}"; do
		# shellcheck disable=SC2254  # the RHS is meant to be a glob
		if [[ $n == $pat ]]; then skip=1; break; fi
	done
	if [ "$skip" = 1 ]; then
		skipped=$((skipped + 1))
		continue
	fi
	ln -sf "$f" "/usr/bin/$n"
	linked=$((linked + 1))
done
log "  $linked command(s) linked, $skipped Arch-only command(s) left out"

log "Seeding ~/.config from $OMARCHY_PATH"
install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$HOME/.config"

# config/ is the packaged user configuration; omarchy-refresh-config copies it
# file by file, so the initial seed is the same tree. The Arch-only autostart
# entry is dropped (there is no limine/snapper here).
if [ -d "$OMARCHY_PATH/config" ]; then
	for entry in "$OMARCHY_PATH"/config/*; do
		[ -e "$entry" ] || continue
		cp -a "$entry" "$HOME/.config/"
	done
	rm -f "$HOME/.config/autostart/limine-snapper-notify.desktop"
fi

# The parts of default/ that seed ~/.config (the rest is read by path at runtime,
# e.g. default/hypr/bootstrap.lua).
for entry in omarchy uwsm environment.d; do
	[ -d "$OMARCHY_PATH/default/$entry" ] || continue
	install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$HOME/.config/$entry"
	cp -a "$OMARCHY_PATH/default/$entry/." "$HOME/.config/$entry/"
done

chown -R "$USERNAME:$USERNAME" "$HOME/.config"

# UWSM is what starts the session, and it sources /usr/share/uwsm/env.d, so the
# Omarchy env bootstrap lives there rather than only in ~/.config.
if [ -f "$OMARCHY_PATH/default/uwsm/env.d/10-omarchy" ]; then
	install -d -m 0755 /usr/share/uwsm/env.d
	install -m 0644 "$OMARCHY_PATH/default/uwsm/env.d/10-omarchy" /usr/share/uwsm/env.d/10-omarchy
fi

# Omarchy's application entries and their icons. Upstream ships them in the
# package ("package-owned under /usr/share/icons/hicolor", see omarchy-tui-install)
# and the shell's AppLibrary, the dock and the launcher menu read XDG desktop
# entries, so they belong in /usr/share. The icon files are named "Google Maps.png"
# while each entry asks for Icon=google-maps, so the name is normalised on install.
log "Installing the Omarchy application entries"
if [ -d "$OMARCHY_PATH/applications" ]; then
	install -d /usr/share/applications /usr/share/icons/hicolor/256x256/apps
	apps=0
	for d in "$OMARCHY_PATH"/applications/*.desktop; do
		[ -f "$d" ] || continue
		install -m 0644 "$d" /usr/share/applications/
		apps=$((apps + 1))
	done
	for f in "$OMARCHY_PATH"/applications/icons/*.png; do
		[ -f "$f" ] || continue
		ic=$(basename "$f" .png | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
		install -m 0644 "$f" "/usr/share/icons/hicolor/256x256/apps/$ic.png"
	done
	command -v update-desktop-database >/dev/null && update-desktop-database /usr/share/applications || true
	command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
	log "  $apps application entry(ies) installed"
fi

# The default dock pins include apps this milestone does not ship: omacalc and
# omawrite are omarchy-pkgs, deferred to F8 (docs/plan-omarchy.md). Drop any pin
# that has no .desktop anywhere, so the dock shows no dead launcher.
_shell_json="$HOME/.config/omarchy/shell.json"
if [ -f "$_shell_json" ] && command -v jq >/dev/null; then
	_keep=""
	while read -r _id; do
		[ -n "$_id" ] || continue
		for _dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
			if [ -f "$_dir/$_id.desktop" ]; then
				_keep="$_keep$_id
"
				break
			fi
		done
	done < <(jq -r '.dock.pinned[]? // empty' "$_shell_json" 2>/dev/null)
	_tmp="$(mktemp)"
	if jq --arg keep "$_keep" '.dock.pinned = ($keep | split("\n") | map(select(length > 0)))' \
		"$_shell_json" >"$_tmp"; then
		install -m 0644 -o "$USERNAME" -g "$USERNAME" "$_tmp" "$_shell_json"
	fi
	rm -f "$_tmp"
fi

# The vendored menu still offers Omarchy's Arch-only entries: the package/AUR
# install and remove rows, the AI/gaming/webapp/TUI/dev installers, omarchy-update
# and the service/security rows. Their actions call the commands the EXCLUDE
# block above deliberately leaves off PATH, so on this port a click opens a
# terminal that dies with "command not found". Hide those rows through the
# shell's own user extension (Menu.qml merges it over the vendored
# default/omarchy/omarchy-menu.jsonc) rather than show entries that cannot work;
# a submenu left with no visible row disappears with them. The list is
# regenerated from the pinned menu on every build, so a new upstream row that
# reaches for an Arch-only command is caught without editing the vendored file.
# That extension is also where upstream asks users to add their own rows, so its
# documentation (config/omarchy/extensions/omarchy-menu.jsonc) is carried over
# above the generated block instead of being replaced.
log "Hiding the menu rows that need an Arch-only command"
_menu="$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
_menu_tmpl="$OMARCHY_PATH/config/omarchy/extensions/omarchy-menu.jsonc"
_ext_dir="$HOME/.config/omarchy/extensions"
_ext="$_ext_dir/omarchy-menu.jsonc"
if [ -f "$_menu" ]; then
	install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$_ext_dir"
	_first=1
	hidden=0
	{
		printf '{\n'
		# Upstream's "how to extend the menu" comments (the template is one
		# object whose braces are replaced by this one).
		if [ -f "$_menu_tmpl" ]; then
			sed -e '1d' -e '$d' "$_menu_tmpl"
			printf '  //\n'
		fi
		printf '  // ---- Debian/Hayato port (generated by uis/omarchy/setup.sh) ----\n'
		printf '  // The rows below are hidden because their action calls an Arch-only\n'
		printf '  // command this build leaves off PATH; a false `when` hides the row and\n'
		printf '  // a submenu left with no visible row hides with it. Regenerated on every\n'
		printf '  // image build, so add your own rows outside this block.\n'
		while IFS= read -r _line; do
			case "$_line" in
				*'"action":"'*) ;;
				*) continue ;;
			esac
			_id=${_line#*\"}; _id=${_id%%\"*}
			_action=${_line#*\"action\":\"}; _action=${_action%%\"*}
			_skip=0
			# Word-split the action and match every token against the same
			# globs the PATH exclusion uses, so "needs an Arch-only command"
			# has one definition.
			for _tok in $(printf '%s' "$_action" | tr -c 'A-Za-z0-9_.:/-' ' '); do
				for _pat in "${EXCLUDE[@]}"; do
					# shellcheck disable=SC2254  # the RHS is meant to be a glob
					if [[ $_tok == $_pat ]]; then _skip=1; break; fi
				done
				[ "$_skip" = 1 ] && break
			done
			[ "$_skip" = 1 ] || continue
			if [ "$_first" = 1 ]; then _first=0; else printf ',\n'; fi
			printf '  "%s": {"when":"false"}' "$_id"
			hidden=$((hidden + 1))
		done < "$_menu"
		printf '\n}\n'
	} >"$_ext"
	chown "$USERNAME:$USERNAME" "$_ext"
	log "  $hidden menu row(s) hidden"
else
	warn "$_menu is missing; the Arch-only menu rows stay visible"
fi

# Materialise the default theme (Tokyo Night), which upstream's installer does at
# install time. Headless, because there is no session in the chroot; if a tool it
# needs is missing the shell falls back at first login and the warning says so.
log "Applying the default theme (Tokyo Night)"
env HOME="$HOME" \
	PATH="$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin:/bin" \
	OMARCHY_PATH="$OMARCHY_PATH" \
	OMARCHY_THEME_HEADLESS=1 \
	omarchy-theme-set "Tokyo Night" ||
	warn "omarchy-theme-set failed; the theme is applied on first login"
chown -R "$USERNAME:$USERNAME" "$HOME/.config" "$HOME/.local" 2>/dev/null || true

exit 0
