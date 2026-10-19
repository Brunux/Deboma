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
	# omarchy-channel-set rewrites pacman's mirrorlist and installs the omarchy
	# packages through pacman; it sources install/helpers/pacman.sh, which this
	# port does not vendor, so it dies before it does anything. The whole family
	# goes, and the Update > Channel rows go with it - keeping only "current"
	# would leave a command nothing reads.
	'omarchy-channel-*'
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
	# omarchy-setup-input installs Fcitx5 through omarchy-pkg-add (pacman). This
	# port has no input-method engine, so the command and its Setup row are left
	# out together; SUPER+I / SUPER+SHIFT+I stay bound and do nothing without
	# fcitx5 (the CTRL+SPACE passthrough is gated on fcitx5-remote already).
	'omarchy-setup-input'
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
	# omarchy-transcode and omarchy-transcode-ascii are deliberately NOT here:
	# they need only what this port installs (file, magick/convert, ffmpeg,
	# wl-copy and awk) and were left out while `file` was missing, which broke
	# the MIME sniff before the menu could tell a picture from a video.
	# `omarchy transcode ascii <image> <output>` is also how a custom screensaver
	# logo is made.
	# The camera overlay needs a working MT8192 camera stack, which this port does
	# not have, so the two helpers that list and resize it stay out.
	'omarchy-capture-webcam-list'
	'omarchy-capture-webcam-resize'
	'omarchy-apply-hardware'
	# omarchy-apply-lock writes the lock screen's PAM file from Arch's stack
	# (system-local-login, pam_systemd_home, pam_faillock without its tally
	# directory). uis/omarchy/files/etc/pam.d/omarchy-lock-password ships the
	# Debian stack instead, so this command must stay off PATH: running it would
	# replace that file and the lock screen would reject the correct password.
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

# The one command a glob above would take that works here unchanged:
# omarchy-update-time only runs `systemctl restart systemd-timesyncd`, and
# systemd-timesyncd is the NTP client this port installs on purpose (Debian
# enables none, packages/base.list). Upstream's Update > Time row is the manual's
# way to resync a clock that drifted, so the row is left visible with it.
KEEP=(
	'omarchy-update-time'
)

# arch_only <name>: does this build leave the command off PATH? One definition,
# used by the symlink farm and by the menu-row generator, so an exception cannot
# drift from the rows it un-hides.
arch_only() {
	local _n="$1" _p
	for _p in "${KEEP[@]}"; do
		# shellcheck disable=SC2254  # the RHS is meant to be a glob
		[[ $_n == $_p ]] && return 1
	done
	for _p in "${EXCLUDE[@]}"; do
		# shellcheck disable=SC2254  # the RHS is meant to be a glob
		[[ $_n == $_p ]] && return 0
	done
	return 1
}

# Menu rows whose action needs something Debian does not package at all, listed
# by menu id because the EXCLUDE globs above can only match Arch-only commands.
# Every Share row ends in LocalSend — the clipboard, file and folder rows go
# through omarchy-menu-share and the Receive row calls it directly — and there is
# no localsend in Debian; hiding the parent row takes the submenu with it.
HIDE_ROWS=(
	'trigger.share'
)

log "Putting the omarchy-* commands on PATH (/usr/bin)"
linked=0
skipped=0
for f in "$OMARCHY_PATH"/bin/*; do
	[ -f "$f" ] || continue
	n="${f##*/}"
	if arch_only "$n"; then
		skipped=$((skipped + 1))
		continue
	fi
	ln -sf "$f" "/usr/bin/$n"
	linked=$((linked + 1))
done
# The farm only adds, so a name a pattern added later covers would keep its link:
# the command would still be reachable (and its menu row hidden with it). Prune
# the links this repository owns - they point into $OMARCHY_PATH/bin - and leave
# a real file, or a link someone placed elsewhere, alone.
pruned=0
for l in /usr/bin/omarchy-*; do
	[ -L "$l" ] || continue
	case "$(readlink "$l")" in
		"$OMARCHY_PATH"/bin/*) ;;
		*) continue ;;
	esac
	if arch_only "${l##*/}"; then
		rm -f "$l"
		pruned=$((pruned + 1))
	fi
done
log "  $linked command(s) linked, $skipped Arch-only command(s) left out${pruned:+, $pruned stale link(s) removed}"

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

# Natural (inverse) scrolling is this port's default: two fingers up move the
# content up, as on a phone. Upstream's default/hypr/input.lua sets
# natural_scroll = false, and the user file is loaded *after* the defaults
# (hyprland.lua requires hypr.input last), so the same hl.config block here wins
# and only that key changes: hl.config merges, which keeps the layout, the tap
# and drag flags, the repeat rate and the rest of the touchpad block. Appended
# rather than replacing config/hypr/input.lua so the documented examples stay.
_hypr_input="$HOME/.config/hypr/input.lua"
if [ -f "$_hypr_input" ]; then
	if ! grep -q 'omarchy-debian: natural scroll' "$_hypr_input"; then
		cat >>"$_hypr_input" <<'EOF'

-- omarchy-debian: natural scroll on by default.
-- Upstream ships natural_scroll = false; this port defaults to the phone-like
-- direction (two fingers up move the content up). Set it to false, or delete
-- this block, to get Omarchy's default back.
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
    },
  },
})
EOF
	fi
	chown "$USERNAME:$USERNAME" "$_hypr_input"
else
	warn "$_hypr_input is missing; the touchpad keeps upstream's scroll direction"
fi

# The screensaver and the About panel paint the Omarchy logo from plain text:
# omarchy-screensaver runs `ttfx -i ~/.config/omarchy/branding/screensaver.txt`
# and the About panel reads ~/.config/omarchy/branding/about.txt. Upstream's
# package installs the two sources as /usr/share/omarchy/{logo,icon}.txt (both
# vendored under files/usr/share/omarchy/) and its installer seeds these copies;
# nothing did here, so the screensaver had no input file and About was empty.
# `omarchy transcode ascii <image> <output>` replaces either with your own logo.
log "Seeding the screensaver and About branding"
if [ -f "$OMARCHY_PATH/logo.txt" ] && [ -f "$OMARCHY_PATH/icon.txt" ]; then
	install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$HOME/.config/omarchy/branding"
	install -m 0644 -o "$USERNAME" -g "$USERNAME" \
		"$OMARCHY_PATH/logo.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
	install -m 0644 -o "$USERNAME" -g "$USERNAME" \
		"$OMARCHY_PATH/icon.txt" "$HOME/.config/omarchy/branding/about.txt"
else
	warn "$OMARCHY_PATH/logo.txt or icon.txt is missing; the screensaver has nothing to paint"
fi

# Where a theme of your own goes. omarchy-theme-list, -extras, -install and
# -plymouth-list all read ~/.config/omarchy/themes, and `find` on the missing
# directory writes "No such file or directory" to stderr ahead of the 23 system
# themes. omarchy-upgrade-to-quattro creates it for systems coming from v3 (its
# own `mkdir -p`), which a fresh v4 install never runs - so the port creates it,
# and with it the place the manual's "write your own theme" chapter assumes.
log "Creating ~/.config/omarchy/themes"
install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$HOME/.config/omarchy/themes"

# ~/.bashrc: Debian seeds it from /etc/skel, and nothing sourced Omarchy's shell
# environment, so `ls` stayed Debian's ls, the ff/ll helpers did not exist,
# zoxide and fzf were never initialised and starship never drew the prompt.
# Upstream copies default/bashrc over ~/.bashrc when that file is missing or is a
# known default (install_bash_startup in omarchy-upgrade-to-quattro); the port
# appends the source line to Debian's file instead, so the history, lesspipe and
# completion settings Debian writes there keep working. default/bashrc returns
# early for non-interactive shells, so non-login scripts are unaffected.
log "Wiring Omarchy's shell environment into ~/.bashrc"
_bashrc="$HOME/.bashrc"
if [ ! -e "$_bashrc" ]; then
	install -m 0644 -o "$USERNAME" -g "$USERNAME" /dev/null "$_bashrc"
fi
if ! grep -qF '/usr/share/omarchy/default/bashrc' "$_bashrc"; then
	cat >>"$_bashrc" <<'EOF'

# Omarchy aliases, functions, zoxide/fzf integration and the starship prompt.
[[ -r /usr/share/omarchy/default/bashrc ]] && source /usr/share/omarchy/default/bashrc
EOF
	chown "$USERNAME:$USERNAME" "$_bashrc"
fi

# Arch installs the Rust bat as `bat`; Debian's package of the same program
# installs the binary as `batcat` (the name `bat` belongs to an unrelated
# package). Omarchy's aliases, its MANPAGER and the fzf previews call `bat`, so
# the Arch name is provided here; /usr/local/bin precedes /usr/bin and no Debian
# package ships /usr/local/bin/bat. `fd` needs no alias: the pinned tree never
# calls it, and fd-find is installed for the user as `fdfind`.
log "Providing the Arch name of bat (/usr/local/bin/bat -> /usr/bin/batcat)"
install -d -m 0755 /usr/local/bin
ln -sf /usr/bin/batcat /usr/local/bin/bat

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
				[[:space:]]*'"'*) ;;
				*) continue ;;
			esac
			_id=${_line#*\"}; _id=${_id%%\"*}
			_skip=0
			# Rows that reach for something Debian does not package at all
			# (LocalSend) are listed by id; a submenu parent has no action, so
			# this test has to come before the action is required.
			for _row in "${HIDE_ROWS[@]}"; do
				if [[ $_id == $_row ]]; then _skip=1; break; fi
			done
			if [ "$_skip" = 0 ]; then
				case "$_line" in
					*'"action":"'*) ;;
					*) continue ;;
				esac
				_action=${_line#*\"action\":\"}; _action=${_action%%\"*}
				# Word-split the action and match every token against the same
				# predicate the PATH exclusion uses, so "needs an Arch-only
				# command" has one definition (KEEP included).
				for _tok in $(printf '%s' "$_action" | tr -c 'A-Za-z0-9_.:/-' ' '); do
					if arch_only "$_tok"; then _skip=1; break; fi
				done
			fi
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

# First-run provisioning is marked done here, at build time. Omarchy's autostart
# entry (default/hypr/autostart.lua) runs `omarchy-provision-first-run` at every
# login and that script is gated on the marker below; unmarked, it walks its
# steps - `bash $OMARCHY_PATH/install/user/first-run/*.sh`, a tree this port does
# not vendor - exits 127 and retries at the *next* login, appending one attempt
# per boot to ~/.local/state/omarchy/first-run.log and costing a login the
# failed work every time. What it would have done once is done here instead:
# omarchy-provision-user's per-user prefix (dev-aware skill symlinks, the xdg
# user dirs and the GTK bookmarks), which needs a real $HOME and a non-root
# user, so it cannot be a plain file under files/home/.
#
# The prefix stops at `source $OMARCHY_INSTALL/user/all.sh`, so finalize-user
# stays unmarked on purpose - the script is not finished by upstream's
# definition, only its per-login cost is removed. Vendoring install/ later means
# deleting the first-run-user marker (`rm ~/.local/state/omarchy/done/first-run-user`).
log "Running the per-user provisioning prefix once"
if ! command -v setpriv >/dev/null 2>&1 || [ ! -x "$OMARCHY_PATH/bin/omarchy-provision-user" ]; then
	warn "setpriv or omarchy-provision-user is missing; the per-user prefix was not run"
elif setpriv --reuid="$(id -u "$USERNAME")" --regid="$(id -g "$USERNAME")" --clear-groups \
	env HOME="$HOME" OMARCHY_PATH="$OMARCHY_PATH" \
	PATH="$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin:/bin" \
	bash "$OMARCHY_PATH/bin/omarchy-provision-user"; then
	warn "omarchy-provision-user completed - install/ is vendored? keep finalize-user, revisit the first-run marker"
else
	log "  omarchy-provision-user stopped at the missing install/ tree, as expected"
fi
install -d -m 0755 -o "$USERNAME" -g "$USERNAME" "$HOME/.local/state/omarchy/done"
install -m 0644 -o "$USERNAME" -g "$USERNAME" /dev/null \
	"$HOME/.local/state/omarchy/done/first-run-user"

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
