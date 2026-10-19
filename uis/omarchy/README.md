# uis/omarchy — the Omarchy v4 desktop on Debian

A UI is a package list plus a file tree:

```
uis/<ui>/
  packages.list          packages to install (Debian names)
  files/                 tree overlaid onto the rootfs
    etc/...              copied to /            (owned by root)
    home/...             merged into /home/$USERNAME (owned by the user)
```

`scripts/build-rootfs.sh` stages both into the chroot and `scripts/rootfs-setup.sh`
installs them, rewriting `/home/brunux` to the configured `USERNAME` inside the
text files. Select this UI with `UI=omarchy`.

This desktop is a port of **[Omarchy v4](https://omarchy.org)** — Hyprland, the
Quickshell shell, the `omarchy-*` tooling and themes — onto this repository's
Debian `forky`/`arm64` base, reusing the kernel, device tree and boot chain
already proven for the Google Hayato.

- **Upstream:** [`omacom/omarchy`](https://github.com/omacom/omarchy), branch
  **`quattro`**, pinned at **`da2db1a2fe022089165b9edca3326886ad78dae2`**
  (2026-10-18), `version` = `4.0.0.alpha`.
- **Plan:** [`docs/plan-omarchy.md`](../../docs/plan-omarchy.md) — decisions,
  phases and the full Arch→Debian mapping rationale.

## Scope

**The desktop only.** There is no Arch base: no `pacman`/`yay`, no ISO builder,
no Omarchy installer/provisioner, no btrfs/snapper/LUKS, and none of the
`omarchy-pkgs` applications (`omawrite`, `omacalc`, `owe`, …) in this
milestone. The one exception is **omasnap**, the screenshot/annotation overlay
the desktop's own capture commands exec: there is no Debian package for it, so
the port builds it from its upstream repository at the tag pinned in
`omasnap.version` (`scripts/build-omasnap.sh`). The distribution stays Debian;
the port contributes the desktop session, its shell, its configuration, its
themes and the tooling the desktop itself uses.

## Layout

| Path | What it is |
|---|---|
| `packages.list` | The Debian package set (this file's companion), the Arch→Debian map in table form below. |
| `PROVENANCE.md` | The pinned upstream commit and exactly what was vendored or excluded. |
| `patches/` | `*.patch` + `series` against the pinned tree; empty until the port needs one. |
| `omasnap.version` | The pinned tag of the **capture overlay** (`omacom/omasnap`) that `scripts/build-omasnap.sh` builds, because omarchy-capture-screenshot execs it and Debian packages none. |
| `files/usr/share/omarchy/` | The curated vendored Omarchy tree (`config/`, `shell/`, `applications/`, `etc/`, `bin/`, `default/`, `themes/`, `version`) at upstream's runtime path. |
| `files/usr/share/wayland-sessions/omarchy.desktop` | The session entry tuigreet lists; runs UWSM → Hyprland. |
| `files/usr/local/bin/omarchy-session` | The command greetd runs by default: `uwsm start … hyprland.desktop`, as one argv. |
| `files/etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf` | Upstream's `KillMode=mixed` drop-in for the UWSM unit. |
| `files/etc/profile.d/omarchy.sh` | Puts `$OMARCHY_PATH` in login shells. |
| `setup.sh` | Runs in the chroot: symlinks the shipped `omarchy-*` commands into `/usr/bin`, seeds `~/.config` from the vendored tree, installs the UWSM env file and applies the Tokyo Night theme. **Landed (F3).** |

The vendored tree is what upstream expects at `$OMARCHY_PATH`, so the shell and the
`omarchy-*` commands find their files unchanged. The port's job is the *edges*: the
package list (done), the Debian-ised system/user overlay (pending), the session entry
(greetd, pending) and the device quirks (pending).

## What changed from Arch/Omarchy

### Session and login

Omarchy starts Hyprland through **UWSM** behind **SDDM**. This port keeps the
Debian side's **`greetd` + `tuigreet`** and starts the same **Hyprland via
UWSM** session from there (see `docs/plan-omarchy.md` §2). SDDM is not installed
and upstream's `etc/sddm.conf.d/*` and `install/login/sddm.sh` do not ship.

The chain on this port is: `greetd` → `tuigreet` (which lists
`/usr/share/wayland-sessions/omarchy.desktop`) → `/usr/local/bin/omarchy-session`
→ `uwsm start -g -1 -e -D Hyprland hyprland.desktop` → Hyprland.
`scripts/rootfs-setup.sh` became UI-aware and writes `--cmd omarchy-session` into
`/etc/greetd/config.toml`, enabling `greetd` for the desktop.

Upstream ships the `omarchy-*` commands as `/usr/bin/omarchy-*` (they come in the
Arch `omarchy` package). Here `setup.sh` symlinks them from the vendored
`$OMARCHY_PATH/bin` into `/usr/bin`, and `/etc/profile.d/omarchy.sh` plus
`/usr/share/uwsm/env.d/10-omarchy` set `$OMARCHY_PATH`. The Arch-only command
families (package management and updates, the installer/provisioner,
AUR/web-app/gaming/AI installers, and helpers that call `pacman`/`yay`) are left
off PATH rather than shipped broken: that list is the `EXCLUDE` block in
`setup.sh`, and every other command is linked.

`omarchy-cmd-present` and `omarchy-cmd-missing` are deliberately **not** excluded:
they are plain `command -v` predicates, not Arch tooling, and the linked
`omarchy-launch-editor`, `omarchy-theme-set-vscode`/`-browser` and the
`battery-low` hook call them (the shell defines its own copies). Excluding the
whole `omarchy-cmd-*` family silently broke those calls — the editor always fell
back to `nvim` and the browser/editor theme steps skipped — so the family stays
on PATH.

### Device quirks and system files

The Hayato device quirks are handled here:

- `files/etc/keyd/default.conf` — the Chromebook top-row remap (VTs, F1–F10); the
  Lock key stays unmapped so systemd-logind still suspends on `KEY_SLEEP`.
- `files/etc/udev/rules.d/90-brightnessctl.rules` — gives the `video` group write
  access to the backlight, which `omarchy-brightness-display` calls.
- `files/etc/udev/rules.d/60-omarchy-io-scheduler.rules`,
  `files/etc/modprobe.d/omarchy-usb-autosuspend.conf`,
  `files/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf` — upstream's.

Omarchy defines its own XKB option (`shift_caps_compose`) in `/etc/xkb`, which
libxkbcommon reads before the system rules, so `files/etc/xkb/rules/evdev` and
`files/etc/xkb/symbols/omarchy` are installed, alongside upstream's logind,
systemd (`nofile`, shutdown), `systemd-oomd`, `sysctl.d`, `plocate` and `zswap`
drop-ins. The ALSA UCM boot sequence comes from `alsa-utils` (base) and
`alsa-ucm-conf` (this list). `pamixer` drives the XF86Audio*
bindings, but the shipped `omarchy-capture-screenrecording` and
`omarchy-audio-input-set-default` call `pactl`, so `pulseaudio-utils` is in the
list as well (otherwise screen recording loses its audio and `check-system.sh`
SKIPs the audio check). Upstream's Arch-only system files
— mkinitcpio, limine, plymouth, sddm, docker, mise, the `sudoers.d/omarchy-*`
grants and its `nsswitch.conf` — are deliberately not installed.

### Hyprland configuration is Lua

Since 0.55 Hyprland reads `hyprland.lua` and `hypr/autostart.lua`,
`bindings.lua`, `input.lua`, `looknfeel.lua`, `monitors.lua` rather than the
legacy `hyprland.conf`. Debian `forky` ships **hyprland 0.56.2**, so the pinned
tree's Lua configuration is used as-is; v3-era `hyprland.conf` material is not
ported.

### The shell (Quickshell)

The shell's QML imports (`Quickshell*`, `qs.Commons`, `qs.Ui`, `QtQuick*`,
`QtQml.Models`) all resolve against Debian's `quickshell` 0.3.2 plus the
`qml6-module-qtquick*` set in `packages.list`; the `Quickshell.Services.*`
modules ship inside the binary and use PipeWire, UPower, polkit, Pam, BlueZ and
NetworkManager, all installed. One import, `Owe.LockFeed`, comes from the
`omarchy-pkgs` app `owe` and is deferred with the rest of that set (F8) — the lock
screen may fall back until then. This is the F4 gate: it is a **shape check on
the imports**, not a boot.

### Package-manager and installer tooling

Everything tied to Arch's package flow is dropped: `pacman`, `yay`,
`pacman-contrib`, `expac`, `kernel-modules-hook`, the mkinitcpio/limine/plymouth
integration, and the `omarchy-pkg-*` / `omarchy-update-*` commands that call
them. Debian's `apt`, this repository's `install-kernel.sh` + `install-kpart.sh`
flow and `initramfs-tools` replace all of it. The `omarchy-*` subset that ships
is the part the desktop itself reaches (theme switching, OSD, capture, audio,
network, power, session, lock); the rest is omitted rather than stubbed, and
`docs/plan-omarchy.md` F2 pins that boundary down.

The **command menu** is part of that Arch surface. The vendored
`default/omarchy/omarchy-menu.jsonc` fills its `Install` and `Remove` rows, and
several `Update`/`Setup` rows, with the very commands above, so a click opened a
floating terminal that died on `command not found`. `setup.sh` hides exactly
those rows through the shell's own extension point,
`~/.config/omarchy/extensions/omarchy-menu.jsonc` (`Menu.qml` merges it over the
vendored menu, and a submenu left with no visible row disappears with it), and
carries upstream's "how to extend the menu" comments over instead of replacing
them. The list is **generated from the pinned menu on every build**, by matching
each row's `action` against the same `EXCLUDE` globs that decide the PATH, so a
new upstream row that reaches for an Arch-only command is caught without editing
the vendored file. What survives is what works here — `Install > Style >
Theme`/`Background` and the `Update` menu's Config/Process/Hardware/Password/
Timezone/**Time** rows. The `Channel` family is Arch's mirror selection:
`omarchy-channel-set` rewrites pacman's mirrorlist and sources
`install/helpers/pacman.sh`, a file this port does not vendor, so the row died
before doing anything — it is out with the rest. The other way round,
`omarchy-update-time` is the one `omarchy-update*` command that works here
unchanged (`systemctl restart systemd-timesyncd`, the NTP client
`packages/base.list` adds on purpose), so it sits in a `KEEP` list that the
same generated rows honour, and its row stays. Verified live on the booted card
by summoning the submenu (`omarchy-shell shell toggle omarchy.menu
'{"menu":"install"}'`) and screenshotting it: `Install` went from thirteen rows
to one, `Update` kept all six, `Install > Style` kept `Theme` and `Background`
(its Arch-only `Fonts` row is gone). Re-verified on the eMMC after the second
audit: `Update` now shows Config/Process/Hardware/Password/Timezone/Time, with
no `Channel` row.

### Second audit: the installed eMMC system (2026-10-19)

The card's own install (`scripts/install-emmc.sh`) was audited against the
Omarchy manual, feature by feature, on the running desktop: the commands, the key
bindings, the bar panels and the CLI behind each of them. The boot chain, Wi-Fi,
Bluetooth, audio, suspend, the battery, the theme, the bar, the menus and the
lock behaved. What did **not** is in the table below — the features that depend
on something Arch's `omarchy` package installs in a step this port has no
counterpart for, and the ones that only asked for a tool Debian packages under
another name or a command a glob had taken with it. Each one is silent — the key
does nothing, no error is shown — which is exactly why every one of them is now a
check in `scripts/check-system.sh`.

| Symptom | What it actually was | Fix |
|---|---|---|
| The idle screensaver never appeared | `omarchy-screensaver` paints the logo with **ttfx**, which Debian does not package. | `files/usr/local/bin/ttfx` runs Debian's `python3-terminaltexteffects` in-process under ttfx's own name. |
| …and with ttfx in place it still failed | it reads `~/.config/omarchy/branding/screensaver.txt`, and neither that file nor its source `/usr/share/omarchy/logo.txt` was ever vendored or seeded. | `logo.txt`/`icon.txt` vendored; `setup.sh` seeds `~/.config/omarchy/branding/{screensaver,about}.txt` from them. |
| The lock key, `omarchy system lock` and the idle lock all did nothing (`missing-pam`) | Quickshell's lock screen authenticates through the PAM service **`omarchy-lock-password`**, i.e. `/etc/pam.d/omarchy-lock-password`. Upstream writes that file with `omarchy-apply-lock`, in Arch's shape (`system-local-login`, `pam_systemd_home`, `pam_faillock` with no tally dir) — which is excluded here. | `files/etc/pam.d/omarchy-lock-password` ships Debian's stack: `auth include common-auth` + `account include common-account`, with a comment saying why upstream's is unusable. |
| Print / SUPER+SHIFT+S captured nothing | `omarchy-capture-screenshot` ends in `exec omasnap`, and omasnap is not packaged. | Built from the pinned tag: `omasnap.version` + `scripts/build-omasnap.sh`/`install-omasnap.sh`. |
| `ls` was Debian's, no `ff`/`ll`, no prompt | nothing sourced `$OMARCHY_PATH/default/bashrc`; Debian's `~/.bashrc` was all there was. | `setup.sh` appends the `source` line to Debian's `~/.bashrc` (upstream replaces the file when it is a known default; appending keeps Debian's history/lesspipe settings). |
| `bat: command not found` (the `MANPAGER`, the fzf previews) | Debian's binary is `batcat`. | `setup.sh` links `/usr/local/bin/bat`. |
| No prompt, empty keybindings view, no terminal notifications | `starship`, `lua` and `notify-send` were missing. | `starship`, `lua5.4` and `libnotify-bin` in `packages.list`. |
| The keybindings cheat sheet logged `xkbcli: not found` every time it opened, and the bar's keyboard-layout label fell back | `xkbcli` is what names Hyprland's XKB keycodes for the cheat sheet and maps the active keymap to its short label; Debian ships the CLI in **`libxkbcommon-tools`**, apart from the library it belongs to. | `libxkbcommon-tools` in `packages.list`; the cheat sheet now lists 235 bindings with a clean stderr. |
| `omarchy transcode` failed on every file | `file` was missing, so the MIME sniff failed before the menu could tell a picture from a video. | `file` in `packages/base.list`; `omarchy-transcode`/`-ascii` are no longer excluded (they only ever needed tools this port installs). |
| `omarchy theme list` printed `find: ~/.config/omarchy/themes/: No such file or directory` before its 23 themes | that directory is where a theme of your own goes, and nothing creates it on a fresh v4 install: upstream's `omarchy-upgrade-to-quattro` does it only for systems coming from v3. | `setup.sh` creates it, which is also the chapter 43 workflow's starting point. |
| The Share menu opened flows that died on `command not found` | every Share row funnels into **LocalSend**, which Debian does not package. | the parent row `trigger.share` is hidden, which takes the submenu with it. A submenu parent has no `action`, so `setup.sh`'s generator now tests the row *id* before it requires an action. |
| `Setup > Input Methods` died on `command not found` | it calls `omarchy-setup-input`, which installs Fcitx5 through `omarchy-pkg-add`. | excluded with the rest of the Arch installers; the key binding stays and does nothing without `fcitx5`. |
| `Update > Channel` died in its floating terminal, and `Update > Time` did nothing but say "Updating time…" | the `Channel` rows call `omarchy-channel-set`, which rewrites pacman's mirrorlist and sources `install/helpers/pacman.sh` (not vendored) — Arch's mirror selection, nothing this port has. `omarchy-update-time` is the mirror-image mistake: `systemctl restart systemd-timesyncd` works here unchanged, but the `omarchy-update*` glob that drops the update machinery took it too, and hid its row. | `omarchy-channel-*` added to `EXCLUDE` (the rows hide with it, and `omarchy-channel-current` had no other reader); `KEEP` names `omarchy-update-time`, which `arch_only()` — the one predicate behind both the PATH farm and the row generator — honours. |

**Verified on the eMMC install, not inferred:**

- **Idle → screensaver → lock.** With the timings temporarily shortened,
  `journalctl` shows the whole chain: `idle-cycle-start` → the screensaver
  process starts (its `ttfx` argv and the rendered frame were captured) →
  `lock-system: lock-timeout` → `session-locked=true`/`secure=true`, and
  `passwordPam:true` throughout. Unlocking with the password returns
  `locked:false`. The screensaver exits early only when something takes the
  keyboard — by design; a cycle whose screensaver is dismissed before the lock
  deadline is cancelled rather than locked.
- **Screenshots.** `omarchy-capture-screenshot fullscreen copy` puts a
  1366×912 PNG on the clipboard, and the interactive overlay (region picker,
  hint bar, key legend) renders and closes on Escape.
- **`check-system.sh`** on the eMMC install: **72 OK, 2 WARN, 0 FAIL**
  (`reports/2026-10-19-emmc-desktop.txt`; the WARNs are the `sbs-8-000b`
  fuel-gauge noise and no suspend recorded in that boot).

**Left as-is, with the reason:**

- **LayerShellQt's Qt plugin.** Debian's `liblayershellqtinterface6` ships the
  library but **no `wayland-shell-integration` plugin**, so Qt cannot select the
  `layer-shell` shell integration and logs
  `Could not load the Qt platform plugin "wayland"` on stderr. omasnap then maps
  its overlay as an ordinary fullscreen window instead of a layer surface. It is
  visually identical here — verified by screenshotting the overlay — and the
  pin/annotation flow is unaffected, so building the missing plugin from the
  LayerShellQt source is not worth a second component. `libqt6widgets6` and
  `libqt6dbus6` are in `packages.list` because the binary needs the Widgets
  stack, which the QML modules do not pull in.
- **Touchpad scroll direction.** Upstream's default is
  `natural_scroll = false`. This machine is used with natural (inverse)
  scrolling, set as a **personal override** in `~/.config/hypr/input.lua` —
  the file Omarchy reserves for that — so the port keeps shipping upstream's
  default. Only that one key is set: `hl.config` merges, so the layout, still
  `us`, and the touchpad defaults survive (checked with `hyprctl getoption`).
  Making it the port's default is a two-line change in `setup.sh` if it should
  apply to every install.
- **`omarchy toggle screensaver` writes a flag that nothing reads.** In this
  pinned revision the screensaver's availability is the configured timeout
  (`idle.screensaver`, 150 s in `shell/shell.qml`), read by
  `shell/plugins/services/idle/Service.qml`; no file under
  `~/.local/state/omarchy/toggles/` is consulted for it, although the toggle
  writes one. That is upstream's, not the port's — the same on Arch — and
  `check-system.sh` checks the renderer and the timers instead of the flag
  rather than patching the shell to honour it.
- **The two key bindings with no tool behind them**, kept bound exactly as
  upstream binds them: `SUPER + CTRL + Q` (`XF86Calculator`) execs **`omacalc`**,
  and `SUPER + I` / `SUPER + SHIFT + I` cycle **Fcitx5**. Both are deferred with
  the rest of the `omarchy-pkgs` set (F8) and their menu rows are gone, so the
  keys are the only trace: they log one line to the compositor's stderr and
  return. Debian does package calculators and Fcitx5, but shipping a *different*
  application behind an upstream binding, and an input-method engine upstream
  configures through its own installer, is F8 work rather than a substitution.

### Package substitutions

| Omarchy (Arch) | Debian (forky) | Why |
|---|---|---|
| (Arch `base` includes **gawk**) | `gawk` | Debian's default `awk` is **mawk**, which has no `RT`. `omarchy-theme-set-templates` keeps each rendered line's terminator in `RT`, so under mawk every generated theme file collapses into a single line and foot rejects its own config. Installing `gawk` also repoints `/usr/bin/awk` (its alternative has the higher priority). |
| `hyprland-guiutils` | `hyprland-qtutils` | Debian's name for the Qt GUI helpers and share picker. |
| `quickshell` | `quickshell` | Present (0.3.2); the pinned shell must run against it, or be trimmed (F4). |
| `hyprland-preview-share-picker` | `hyprland-qtutils` | Ships inside the Qt utils package. |
| `xorg-xwayland` | `xwayland` | Debian's name. Hyprland enables its built-in Xwayland by default (`xwayland:enabled = true`), so X11-only programs (emulators, Wine, some Java/Steam games) need the server binary; nothing else pulls it in. |
| `python-gobject` | `python3-gi` | Debian's name. |
| `nss-mdns` | `libnss-mdns` | Debian's name. |
| `tldr` | `tealdeer` | Debian's tldr client. |
| `evince` | `papers` | GNOME's successor viewer; `evince` is a transitional name in forky. |
| `gpu-screen-recorder` | `wf-recorder` | Not packaged; `omarchy-capture-screenrecording` falls back to wf-recorder. |
| `satty` | `omasnap` (built from source) + `swappy` | Neither `satty` nor omasnap is packaged. The capture key of the pinned tree runs **omasnap**, so the port builds it (see *Layout*); `swappy` stays as Debian's standalone annotator, which the pinned tree itself no longer calls. |
| `ttfx` | `python3-terminaltexteffects` + `files/usr/local/bin/ttfx` | `omarchy-screensaver` paints its logo with **ttfx** — Omarchy's Rust port of terminaltexteffects — and finds *and kills* the effect with `pgrep -x ttfx` / `pkill -x ttfx`. Debian ships the upstream Python original (`tte`), so the shim runs it **in-process** under ttfx's own process name; an `exec` would rename the process and the screensaver would never end. |
| `bat`, `fd` | `batcat`, `fdfind` (plus `/usr/local/bin/bat` → `batcat`) | Debian's packages of the same programs install the binaries under the `-cat`/`-find` names (the bare names belong to unrelated packages). Omarchy's aliases, its `MANPAGER` and the fzf previews call `bat`, so `setup.sh` links the Arch name; the pinned tree never calls `fd`. |
| `ghostty` | `foot` / `alacritty` / `kitty` | Not packaged; the port ships the three terminals Debian has. |
| `docker-buildx` / `docker-compose-v2` | `docker-buildx` / `docker-compose` | Debian's names (only if `docker.io` is wanted). |
| `zram-generator` | `systemd-zram-generator` | The aarch64 addition; `zram-tools` is already in `packages/base.list`. |
| `qemu-user-static-binfmt` | `qemu-user-binfmt` | Debian's name. |
| `woff2-font-awesome` | `fonts-font-awesome` | Debian's name. |
| `ttf-jetbrains-mono-nerd-basic` | `fonts-jetbrains-mono` + `fonts-nerd-symbols` + `fonts-font-awesome` + `fonts-materialdesignicons-legacy` | Debian ships no Nerd-patched Mono face, and `fonts-nerd-symbols` is DFSG-stripped of Font Awesome and Material Design Icons — the same fix this port applies. |
| `ttf-ia-writer` | (dropped) | Not packaged; only vendor it if a theme link needs it. |
| `libvips`, `mariadb-libs`, `postgresql-libs` | `libvips42t64`, `libmariadb3`, `libpq5` | Debian's names. |

### Not needed on Debian

`walker`, `mako` and the v3 `swayosd` stack were Omarchy v3's launcher,
notification daemon and OSD. Omarchy v4's **Quickshell shell** owns the bar,
launcher, notifications and OSD, so none of them are installed. `swayosd` is in
Debian if a fallback OSD is ever wanted.

### Dropped for this milestone

Arch/mise-only tooling (`mise-bin`, `superwhisper-bin`), proprietary or
unpackaged apps (`localsend`, `moonlight-qt`, `obsidian`, `pinta`,
`wl-screenrec`), the **LazyVim configuration of Arch's `omarchy-nvim` package**
(`neovim` is installed and `SUPER + SHIFT + N` / `n` launch it, but it starts
with its own defaults instead of the setup the manual's chapter 16 describes —
upstream ships that as a package of its own, not in the tree this port vendors),
`dotnet-runtime`, and the entire `omarchy-pkgs` application set
(except `omasnap`, which the capture key needs and which is built from source).
They are recorded in `docs/plan-omarchy.md` §4 and deferred to F8 rather than
silently forgotten. `localsend` is the one of them the *menu* reaches: every row
of Share funnels into it, so the whole `trigger.share` submenu is hidden rather
than offered broken (see the second audit below).

## Installed package list

`packages.list` holds 135 Debian names, every one verified to resolve on
`forky`/`arm64`. It does not repeat what `packages/base.list` already provides
(`network-manager`, `wireless-regdb`, `alsa-utils`, `rtkit`, `dosfstools`,
`bash-completion`, `less`). The compositor, Quickshell and its Qt6/QML runtime,
the portals, the terminals, the fonts and the capture/audio/power CLI the shell
and key bindings invoke are all listed there with a comment saying why.

## Status

| Phase (`docs/plan-omarchy.md`) | State |
|---|---|
| F0 recon + pin | done — this README and the plan record it |
| F1 `packages.list` | done — 135 names, all resolved on forky/arm64 |
| F2a vendor the pinned tree (`files/usr/share/omarchy/`, curated) | done — 24 MB, see `PROVENANCE.md` |
| F2b seed `~/.config` + link the `bin/` subset (`setup.sh`) | done — Arch-only commands excluded, rest linked |
| F3 session/login (Hyprland via UWSM under greetd) | done — greetd starts the Omarchy session; the first boot landed on the Hyprland desktop |
| F4 Quickshell shell | imports resolve against Debian's quickshell 0.3.2; the shell runs (bar, launcher, OSD); `Owe.LockFeed` deferred. The desktop audit below fixed the launcher (`gtk-launch`) and the font fallback |
| F5 Hayato quirks (keyd, ALSA UCM, backlight, RAM) | device files + the system subset installed; every Hayato check passes on the first boot |
| F6 build + off-device validation | done — `UI=omarchy` rootfs builds; see the validation notes below |
| F7 hardware validation + release | **first boot 2026-10-18** + desktop audit + the **eMMC install audit 2026-10-19** — see *First boot*, *Desktop audit* and *Second audit* below; the menu trimming and `xwayland` are the last two fixes, and the clean rebuild + re-report are what close it |

The card boots (F7): `reports/2026-10-18-omarchy-desktop.txt` is the first boot of
this UI, on a card written from `commit 85d32fc` (the card's `REVISION` and
`/etc/debian-aarch64-revision` agree).

The same system was then installed to the internal eMMC
(`scripts/install-emmc.sh`, from the running card) and audited there:
`reports/2026-10-19-emmc-desktop.txt` is that report — **72 OK, 2 WARN, 0 FAIL**,
captured with `/` on `/dev/mmcblk0p3` and the kernel partition resolved from the
`kern_guid` in `/proc/cmdline`.

### First boot (2026-10-18)

`check-system.sh` reported **49 OK, 2 WARN, 1 FAIL**. The two WARNs are the
`sbs-8-000b` fuel-gauge noise and "no suspend recorded yet: press the Lock key".
One FAIL and one journal error were real, and both are fixed here:

| Finding | What it actually was | Fix |
|---|---|---|
| `FAIL Hyprland reports configuration errors: [\n\t""\n]` | `hyprctl -j configerrors` answers `[""]` — one **empty** entry — when Hyprland 0.56.2's Lua loader has nothing to report. The check accepted only `[]`/`null`/empty, so an empty string failed it. | `check-system.sh` now drops the brackets and the blank entries and fails only when a real message is left. |
| `foot[..]: config: .../current/theme/foot.ini:1: [colors-dark]: section declaration contains trailing characters` | `omarchy-theme-set-templates` renders every `*.tpl` with `awk`, keeping each line's terminator in gawk's `RT`. Debian's default `awk` is **mawk**, which has no `RT`, so the terminator was dropped and **every generated theme file collapsed into a single line** (`wc -l` 0 on `foot.ini`, `kitty.conf`, `alacritty.toml`, `hyprland.lua`, …). | `gawk` added to `packages.list` (its alternative repoints `/usr/bin/awk`); re-running `omarchy-theme-set` renders multi-line files and `foot -C` accepts the config. |

The off-device validation missed the second one because it checked
`theme.name` (correct) and not the rendered file's contents. `check-system.sh`
now asserts `awk` keeps `RT` **and** that the generated `foot.ini` is multiline,
because the collapse is silent everywhere else: the theme still "applies" and the
colours are still right.

### Desktop audit (2026-10-18, on the booted card)

A full pass over the running session, looking for what Arch provided that Debian
does not. The chain works end to end — `greetd` → `tuigreet` → `omarchy-session`
→ UWSM → **Hyprland 0.56.2**, with the **Quickshell shell** loaded (bar, menu,
dock, OSD, notifications, polkit agent, idle, clipboard, weather) — but the port
was missing several binaries and install steps the desktop assumes.

**Found and fixed here:**

| Symptom | Arch provided | Debian fix |
|---|---|---|
| The launcher menu and the dock opened nothing | `gtk-launch` (in `gtk3`/`gtk4` utilities) | The shell's `AppLibrary` starts an app with `uwsm-app -- gtk-launch <id>.desktop`; `gtk-launch` comes from **`libgtk-3-bin`**, which is not part of the GTK runtime libraries. Added to `packages.list`. |
| **foot** (and kitty, the bar) rendered in a proportional face | the family `JetBrainsMono Nerd Font` as a package | Debian ships `JetBrains Mono` under a different family name, so `fc-match "JetBrainsMono Nerd Font"` fell back to **Noto Sans**. Added `files/etc/fonts/conf.d/50-omarchy-debian-fonts.conf`, which aliases the Nerd Font name to `JetBrains Mono` and keeps the icon fonts in the fallback chain. |
| The weather widget logged "binary could not be found" | `curl` in the base system | Added `curl` to `packages.list`. |
| The dock pinned `omacalc`/`omawrite` (nothing) | n/a — the pins assume `omarchy-pkgs` | `setup.sh` prunes a default dock pin with no `.desktop` anywhere. |
| Omarchy's own apps (X, YouTube, the Google web apps, Discord, Zoom, …) were invisible to the launcher | the packaging step installs `applications/*.desktop` → `/usr/share/applications` and `applications/icons/*` → the icon theme | `setup.sh` installs both, normalising the icon names (`Google Maps.png` → `google-maps.png`, which is what `Icon=` asks for) and refreshing the caches. |
| X11-only programs (emulators, Wine, some Java/Steam games) had no server | `xorg-xwayland`, pulled by the `hyprland` package | Hyprland enables its built-in Xwayland by default, but Debian's `hyprland` does not depend on the server binary. `xwayland` added to `packages.list`; `check-system.sh` warns when `/usr/bin/Xwayland` is missing. |
| Choosing a menu installer row opened a terminal that died on `command not found` | the Arch-only commands the row calls were shipped | `setup.sh` generates `~/.config/omarchy/extensions/omarchy-menu.jsonc` hiding every row whose `action` calls an excluded command (see *Package-manager and installer tooling*). |

**Deliberately NOT installed:** upstream's
`default/fontconfig/conf.avail/50-omarchy.conf`. It assumes the Nerd Font family
exists and, on Debian, its generic-family rules collapse `sans-serif` into the
monospace face and pull `serif` toward Noto Naskh Arabic. The port's own alias
covers the one family the desktop actually names, and leaves the generic families
to Debian. `check-system.sh` now checks where `JetBrainsMono Nerd Font` resolves,
that the application entries are installed, that the theme templates keep their
line breaks, and that `gtk-launch`/`curl` exist, and warns when `/usr/bin/Xwayland`
is missing.

**Found, left as-is (with the reason):**

- `omarchy-provision-first-run` runs from Hyprland's autostart but is **excluded**
  (the `omarchy-provision-*`/`omarchy-install-*` families): it depends on the
  un-vendored `install/` tree, so each login logs one `command not found`, and
  the user-unit/GNOME/speaker first-run steps it would run do not happen. The
  GTK/GNOME end state is nevertheless correct — `omarchy-theme-set` runs
  `omarchy-theme-set-gnome`, and `Adwaita-dark` with `Yaru-magenta` is exactly
  Tokyo Night's intent.
- The shell's menu no longer lists the deferred installers: `setup.sh` hides
  the rows whose action calls an Arch-only command (see *Package-manager and
  installer tooling*), so the boundary F2 draws is visible in the menu instead
  of failing when clicked.
- `Owe.LockFeed` is deferred with `omarchy-pkgs`; the lock screen falls back.
- `Unrecognized pragma "OmarchyLoadPatch"`: the shell uses a custom pragma from
  Omarchy's patched Quickshell, which Debian's stock **0.3.2** does not know, so
  that patch-loading hook is inert. Nothing the port ships depends on it (the
  user menu extension under `~/.config/omarchy/extensions/` loads normally).
- Quickshell/QML warnings (`Binding loop ... "height"` in the network panel,
  `QString::arg: Argument missing` on a few translations, the portal "already
  associated" line) are upstream and cosmetic.

After these fixes the card reports **59 OK, 2 WARN, 0 FAIL** (the WARNs are the
`sbs-8-000b` fuel-gauge noise and no suspend recorded yet). The updated report,
run again on the same card with the checks added here, says **58 OK, 3 WARN,
1 FAIL**: the extra WARN and the FAIL are the new Xwayland probe, and the card
predates `xwayland` in `packages.list`, so a clean `UI=omarchy` rebuild installs
it and closes both. That rebuild, its fresh report and the release are the F7
close-out.

### What was actually validated off-device

`UI=omarchy scripts/build-rootfs.sh` builds the rootfs and its hook runs:

- the vendored tree lands at `/usr/share/omarchy`, the packages resolve, and
  `~/.config` is seeded (`hypr/`, `omarchy/`, `uwsm/`, `environment.d/`, …);
- the hook links **309** commands into `/usr/bin` and leaves the 223 Arch-only
  ones out (verified inside the built rootfs: `omarchy-theme-set` and
  `omarchy-launch-shell` are present, `omarchy-pkg-add` and
  `omarchy-update-available` are absent);
- `omarchy-theme-set "Tokyo Night"` runs headless and leaves
  `~/.local/state/omarchy/current/theme.name` = `tokyo-night`;
- `Hyprland --verify-config` loads `~/.config/hypr/hyprland.lua` and the Omarchy
  defaults through Lua with no config errors (the one line it reported,
  `hl.env(... HYPRLAND_INSTANCE_SIGNATURE)`, only fires when the compositor runs
  outside its own session; the later segfault is the chroot having no `/dev`/DRM).

The compositor, the shell and the hardware paths cannot be judged in a chroot;
that is F7.
