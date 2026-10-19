# Plan: the Omarchy desktop on Debian

> Goal (milestone 1, **shipped as v0.2.0**): bring the **Omarchy v4 desktop** — Hyprland, the
> Quickshell shell, the `omarchy-*` tooling, its themes and its configuration — to the Debian
> arm64 system this repository already builds for the **Google Hayato** (MediaTek MT8192,
> `google-asurada`).
>
> Goal (milestone 2, **v0.3.0**, §8): ship that same desktop as **Debian packages** served from a
> signed apt archive — `apt install omarchy-desktop` on a stock Debian forky — and carry upstream's
> releases into those packages with CI, instead of re-vendoring a tree by hand.
>
> Scope (milestone 1): **the desktop only**. No Arch base: no `pacman`/`yay`, no ISO builder, no
> Omarchy installer, no btrfs/snapper/LUKS provisioning, and no `omarchy-pkgs` applications in
> this first milestone. The distribution stays Debian (`forky`, `arm64`), the boot chain, kernel
> and device support stay the ones already proven here.
>
> Foundation: `main` at `ddf3ed6` (**v0.2.0**), the port that boots from the eMMC and the microSD,
> whose install path (`write-sd.sh`, `install-emmc.sh`, `install-kpart.sh`) is verified on
> hardware, and whose desktop has been validated on a booted card.

---

## 1. What Omarchy v4 is

Pinned upstream: [`omacom/omarchy`](https://github.com/omacom/omarchy), branch **`quattro`**,
commit **`da2db1a2fe022089165b9edca3326886ad78dae2`** (2026-10-18), `version` =
**`4.0.0.alpha`**, MIT. (The project was previously hosted as `basecamp/omarchy`; `omacom/omarchy`
is the current home.)

The desktop is:

| Piece | What it is | Where it lives upstream |
|---|---|---|
| **Hyprland** | the Wayland compositor | package |
| **UWSM** | the session manager that starts Hyprland as a systemd user session | package |
| **Quickshell shell** | the desktop shell (bar, launcher, notifications, OSD, lock screen...) written in QML; replaces v3's waybar/mako/walker | `shell/shell.qml`, `shell/Commons`, `shell/Ui`, `shell/plugins`, `shell/services` (281 files) |
| **`omarchy-*` CLI** | 532 commands: theme switching, capture, audio, network, power, updates... | `bin/` |
| **Configuration** | Hyprland, autostart, terminals, btop, git, wireplumber, portals, fcitx5 | `config/` (82 files) |
| **Base filesystem** | systemd units, sysctl, udev, sudoers, xkb | `etc/` (96 files) |
| **Themes** | 30+ colour themes with wallpapers | `themes/` (340 files) |
| **Session defaults** | the seed tree overlaid into `$HOME` on first install | `default/` (585 files) |
| **Applications** | `.desktop` entries and icons | `applications/` (35 files) |
| **Installer** | per-platform package lists + provisioning scripts | `install/` (138 files) |
| **Login** | upstream runs **SDDM**; this port keeps **greetd + tuigreet** | `install/login/` |
| **Upstream apps** | `omawrite`, `omacalc`, `owe`, `herdr`, ... (`omasnap` is built from source: the capture key `exec`s it) | `omarchy-pkgs` (separate, out of scope here) |

Its package set is composed from `install/omarchy-base.packages` (162 packages), plus
`install/omarchy-aarch64.packages` (`zram-generator`, `rtkit`), plus `install/omarchy-other.packages`
(the ISO builder's list: firmware, GPU drivers, laptop-specific packages — most of it is already
handled by this port's kernel/device work or is x86/NVIDIA/Apple-specific and irrelevant here).

**Hyprland configuration is Lua.** Since 0.55 Hyprland reads `hyprland.lua` (loaded through
`hypr/autostart.lua`, `bindings.lua`, `input.lua`, `looknfeel.lua`, `monitors.lua`) instead of the
legacy `hyprland.conf`; the old syntax is deprecated. Debian forky ships **hyprland 0.56.2**, so the
Lua configuration is the one to use — do not port Omarchy v3's `hyprland.conf`.

## 2. Decisions taken for this branch

*(Milestone 1, the `omarchy` branch that became v0.2.0; §8 supersedes the delivery mechanism, not
these decisions.)*

| Question | Decision |
|---|---|
| Branch | `omarchy`, off `main@db676cf`, merged into `main` and released as **v0.2.0** (`ddf3ed6`) |
| Login / session | **keep `greetd` + `tuigreet`**; start **Hyprland through UWSM**. No SDDM port in this milestone. |
| Scope | **desktop shell only**: Hyprland + Quickshell + `config/`, `themes/`, `applications/`, `etc/` + the core `omarchy-*` CLI. Arch-only pieces are substituted or dropped; `omarchy-pkgs` apps are deferred. |
| Upstream pin | `quattro` @ `da2db1a2` (4.0.0.alpha) |
| Themes | **curated subset**: all theme definitions, only the default theme's (**Tokyo Night**) backgrounds, English-only shell translations. The other ~160 MB of backgrounds are fetched from the pinned commit only if wanted (`uis/omarchy/PROVENANCE.md`). |
| Where it plugs in | the existing device-agnostic **`uis/<ui>/`** axis: `uis/omarchy/`, selected with `UI=omarchy` (the only UI shipped; the sway session was dropped once this one booted) |
| Plan location | this file |

The UI axis already does what is needed: `scripts/lib.sh` resolves `UI`, and
`scripts/build-rootfs.sh` / `scripts/rootfs-setup.sh` stage `uis/<ui>/packages.list` and overlay
`uis/<ui>/files/` (`etc/` copied as root, `home/` merged into `/home/$USERNAME`). Nothing in the
kernel, boot chain, GPT layout or installer has to change.

## 3. Deliverable layout

```
uis/omarchy/
  packages.list          # Debian package names (the Arch->Debian map, documented inline)
  PROVENANCE.md          # the pinned commit and what was vendored/excluded
  patches/               # *.patch + series against the pinned tree
  files/                 # overlay: usr/share/omarchy/ (the vendored tree), etc/, home/
  README.md              # what ships and every deliberate deviation from upstream
docs/plan-omarchy.md     # this plan
```

- The vendored tree lives at its **runtime path**, `uis/omarchy/files/usr/share/omarchy/` (upstream's
  `$OMARCHY_PATH` default), so the shell and the `omarchy-*` commands find their files unchanged. It
  is a curated subset of the pinned checkout (`config/`, `shell/`, `applications/`, `etc/`, `bin/`,
  `default/`, `themes/`, `version`): all theme definitions but only Tokyo Night's backgrounds, and
  English-only shell translations. `PROVENANCE.md` records the commit and exactly what was trimmed,
  in the style of the existing reference files here.
- Anything patched is kept as a `*.patch` against the pinned tree with a `series` file, the same
  convention as `kernels/<flavor>/patches/`.
- `uis/omarchy/files/etc/` carries the system-level files (units, sysctl, udev, xkb, sudoers,
  portals, `greetd` session), `uis/omarchy/files/home/` the user-level ones (`.config/hypr`,
  `.config/omarchy`, the shell, `.local/bin` for the CLI).

## 4. Arch → Debian package mapping

Verified against this host's `forky`/`arm64` indexes. `uis/omarchy/packages.list` is the Debian
column; this table is the justification, to be kept in `uis/omarchy/README.md`. *(Milestone 2 turns
this table into `debs/policy/packages.map`, and generates both the README table and the
metapackage's `Depends` from it — §8.5.)*

### Available as-is (or with a rename)

| Omarchy (Arch) | Debian (forky) |
|---|---|
| hyprland | `hyprland` 0.56.2 |
| hyprland-guiutils | `hyprland-qtutils` 0.2.2 |
| quickshell | `quickshell` 0.3.2 (+ `qml6-module-*`, `libqt6qml6`, `libqt6quick6`, `libqt6multimedia6`, `libqt6svg6`, `qt6-svg-plugins`, `qt6-image-formats-plugins`) |
| uwsm | `uwsm` 0.27 |
| xdg-desktop-portal-hyprland | `xdg-desktop-portal-hyprland` 1.4.1 |
| xdg-desktop-portal-gtk | `xdg-desktop-portal-gtk` 1.15.3 |
| hyprpicker, hyprsunset | `hyprpicker` 0.4.7, `hyprsunset` 0.4.0 |
| hyprland-preview-share-picker | `hyprland-qtutils` (picker ships with the Qt utils) |
| chromium | `chromium` 154 |
| foot, kitty, alacritty | `foot` 1.28, `kitty` 0.48, `alacritty` 0.17 |
| nvim / omarchy-nvim | `neovim` 0.12 — the package is installed and `SUPER + SHIFT + N` / the `n` alias launch it, but the **LazyVim configuration** that Arch's `omarchy-nvim` package ships is not: it lives in that package, not in the Omarchy tree this port vendors, so nvim comes up with its own defaults (deferred, see §4 and `uis/omarchy/README.md`) |
| starship, zoxide, eza, bat, fd, ripgrep, fzf, lazygit, btop, fastfetch, jq, less, tmux, gum, man-db, tree-sitter-cli, unzip, vim, whois, inxi, plocate, inotify-tools, socat | same names |
| networkmanager | `network-manager` |
| bluez, bluez-tools, bolt, avahi | `bluez`, `bluez-tools`, `bolt`, `avahi-daemon` |
| python-gobject | `python3-gi` |
| nss-mdns | `libnss-mdns` |
| noto-fonts, noto-fonts-cjk, noto-fonts-emoji | `fonts-noto-core`, `fonts-noto-cjk`, `fonts-noto-color-emoji` |
| ttf-jetbrains-mono-nerd-basic | `fonts-jetbrains-mono` + `fonts-nerd-symbols` (+ `fonts-font-awesome`, `fonts-materialdesignicons-legacy` for the glyphs `fonts-nerd-symbols` is DFSG-stripped of) |
| yaru-icon-theme | `yaru-theme-icon` |
| tldr | `tealdeer` |
| woff2-font-awesome | `fonts-font-awesome` |
| zbar | `zbar-tools` |
| tesseract, tesseract-data-eng | `tesseract-ocr`, `tesseract-ocr-eng` |
| gvfs-mtp/nfs/smb | `gvfs-backends` |
| gnome-disk-utility, nautilus, sushi | `gnome-disk-utility`, `nautilus`, `gnome-sushi` |
| evince | `papers` (GNOME's successor) |
| qt6-base/declarative/multimedia/svg/wayland/imageformats | `libqt6*` + `qml6-module-*` + `qt6-wayland` |
| python-poetry-core | `python3-poetry-core` |
| mariadb-libs, postgresql-libs, libvips, libyaml | `libmariadb3`, `libpq5`, `libvips42t64`, `libyaml-0-2` |
| cups, cups-filters, cups-pk-helper, system-config-printer | same names |
| ffmpeg, ffmpegthumbnailer, imagemagick, mpv, mpv-mpris, imv | same names |
| udiskie, wl-clipboard, wtype, qrencode, yt-dlp, dots... | same names |
| gpu-screen-recorder | `wf-recorder` (substitute) |
| qemu-user-static-binfmt | `qemu-user-binfmt` |
| base-devel, fakeroot | `build-essential`, `fakeroot` |
| zram-generator | `systemd-zram-generator` |

### Not in Debian — decide per item in Phase 1

| Omarchy (Arch) | Disposition |
|---|---|
| walker, mako, swayosd v3 stack | **not needed** — v4's shell (Quickshell) owns the launcher, notifications and OSD |
| satty | substitute `swappy` (screenshot annotation) |
| ghostty | substitute `foot`/`alacritty`/`kitty` |
| hyprland-guiutils (as such) | `hyprland-qtutils` provides the GUI utils |
| fcitx5-module-emoji | drop or substitute another fcitx5 emoji module |
| ttf-ia-writer | drop (vendor the font only if a theme link needs it) |
| docker-buildx / docker-compose-v2 | `docker-buildx` / `docker-compose` |
| dotnet-runtime | drop (not needed for the desktop) |
| mise-bin, ttfx, superwhisper-bin | drop — Arch/mise-tooling; Debian ships the tools directly where needed. `ttfx` is the one exception: `omarchy-screensaver` calls it by name and Debian has only the upstream `python3-terminaltexteffects`, so the port ships a shim under `files/usr/local/bin/ttfx` (see `uis/omarchy/README.md`) |
| localsend, moonray-qt, obsidian, pinta, gpu-screen-recorder, wl-screenrec | drop for the first milestone |
| pacman, yay, pacman-contrib, expac, kernel-modules-hook, initramfs/mkinitcpio hooks, limine, plymouth packages | drop — Debian's own package manager, `initramfs-tools` and this repo's kernel partition flow replace them |
| omacalc, omacut, omawrite, owe, owe-lockfeed, herdr, hype, aether, gliff, monologue, signed, tobi-try, usage, cliamp, disktree-bin | **deferred** — `omarchy-pkgs` applications, out of scope for the first milestone (Phase 8). `omasnap`, listed here originally, is **built from source** instead: the capture key `exec`s it and no Debian package provides it (`scripts/build-omasnap.sh`, pin in `uis/omarchy/omasnap.version`) |
| omarchy-nvim (the LazyVim configuration) | drop for now — it is a package of its own in the Arch repo, not part of the tree this port vendors, so `neovim` (mapped in §3) launches with its own defaults. Reproducing it means vendoring a plugin set that fetches from the network on first run, so it is F8 work like the rest |

### Build from source (only if a core piece needs it)

Deferred to Phase 1/4 decisions; candidates: a newer **Quickshell** than 0.3.2 if the pinned shell
needs QML APIs it lacks, and the few Rust/Qt `omarchy-pkgs` apps that later become in-scope. The
default is to make the pinned shell run on the packaged Quickshell rather than to build one.

## 5. Phases (milestone 1, F0–F7)

Each phase says what verifies it; nothing is "done" because it was written. Milestone 2's phases
are P0–P9, §8.10.

**F0 — Recon and pin (this branch's first commit).**
Freeze the upstream commit, inventory the trees against what the UI axis needs, and land this
plan. *Verify:* this document plus the `recon` output it cites; the pin is a commit hash, not
"latest".

**F1 — `uis/omarchy/packages.list`.**
Turn §4 into the list, one Debian name per line, with the deviations documented in
`uis/omarchy/README.md`. *Verify:* every name resolves on `forky/arm64`; `build-rootfs.sh` installs
the list without `apt` errors; nothing drops out of the base list.

**F2 — The overlay.**
(a) Vendor the pinned trees into `files/usr/share/omarchy/` as a curated subset (definitions + Tokyo
Night backgrounds + English translations), with `PROVENANCE.md` and `patches/`. (b) Lay the
Debian-ised `etc/` and `home/` overlay on top, rewriting Arch paths and package calls. Port the
`bin/` subset the desktop itself needs (theme switching, OSD, capture, audio, network, power,
session, lock) and stub or omit the rest. *Verify:* `sh -n`/`bash -n` on every shipped script; no
shipped script references `pacman`/`yay`/`omarchy-pkg-*` on a code path the desktop reaches.

**F3 — Session and login.**
A Hyprland session through UWSM, selected by `greetd` + `tuigreet` (a `hyprland.desktop` wayland
session; `uwsm start`; the `greetd` session file). Portals and their `hyprland-portals.conf`.
Environment for **Panfrost** (`MOZ_ENABLE_WAYLAND`, Qt/Wayland, EGL/GLES renderer hints,
`WLR_*`/`AQ_*` as needed). *Verify:* `greetd` starts the session on a card; `hyprctl version`,
`hyprctl monitors`, `hyprctl clients` answer.

**F4 — The Quickshell shell.**
Ship the pinned `shell/` plus `config/omarchy/` hooks/extensions and the QML module set; wire
`omarchy-launch-shell`/`omarchy-shell`. Confirm the shell runs on **Quickshell 0.3.2** — if it
needs newer QML API, decide between packaging a newer Quickshell and trimming the shell. *Verify:*
the shell draws the bar on a real session; `qs -c <config>` reports no fatal QML errors; no
unhandled import.

**F5 — Hayato quirks.**
The device-specific half, covering what the earlier sway session had solved: `keyd` exclusions for
`cros_ec_buttons`/jack and the `KEY_SLEEP` lock/suspend behaviour, the missing F-row and the
`Ctrl+Alt`/`Search` VT bindings, the ALSA UCM boot sequence, the backlight udev rule, 4 GB RAM
tuning (zram, animation/idle defaults), Wi-Fi regulatory DB. *Verify:* the same checks
`check-system.sh` already encodes, re-pointed at Omarchy.

**F6 — Build and validate off-device.**
`UI=omarchy scripts/build-rootfs.sh`, then a card via `write-sd.sh`. Headless checks before boot:
Validate Hyprland's config with its own tooling (`hyprctl`/`Hyprland` config
errors), `Quickshell` offline where possible, and every config file
for the tools shipped. *Verify:* the rootfs contains the overlay, the package list is installed,
the staged revision is the branch's commit.

**F7 — Hardware and release.**
Boot the card, run `check-system.sh`, iterate on real findings only, and when the session is
stable cut a release the usual way (`make-release.sh`, notes in `docs/releases/`, `lib-dist.sh`
sanitising the artifact). *Verify:* a report in `reports/` from the booted card, and a release
whose notes do not claim more than that report shows.

**F8 — (deferred) the `omarchy-pkgs` applications.**
`omawrite`, `omacalc`, `owe`, ... built for Debian, once the desktop shell itself is
proven. Not part of this milestone. **`omasnap` left this list during the F7 audit**: the
desktop's capture key runs `exec omasnap` and nothing else provides a capture overlay, so the
port builds it from its own upstream repository at a pinned tag (`scripts/build-omasnap.sh`,
`uis/omarchy/omasnap.version`) rather than waiting for a Debian package that does not exist.

## 6. Risks

- **Hyprland + Quickshell on Panfrost / 4 GB RAM.** The headline unknown. Mali-G57 via Mesa
  (GLES3) should satisfy Hyprland's EGL/DRM needs, but performance and memory headroom on 4 GB with
  a Quickshell QML shell have to be measured, not assumed. Mitigations: keep animations/idle
  defaults modest, confirm the renderer early (F3), treat F4 as a gate.
- **Quickshell version drift.** Pinned shell against Debian's 0.3.2. Resolve by trimming the shell
  or packaging a newer Quickshell; decide in F4 with evidence.
- **Volume of Arch-only tooling.** Of 532 `omarchy-*` commands, the desktop needs a subset; the
  rest are Arch-installer/AUR/update paths. The port's job is a clean subset, not a rewrite — but
  the subset boundary must be explicit and tested (F2).
- **Upstream is `4.0.0.alpha`.** Expect the pinned tree to move under us; the pin and the patch
  series are what make the port reproducible.

## 7. Open questions from milestone 1 (2026-10)

*Milestone 2's open questions are in §8.11; this section stays as the record of what F0–F7 asked
and how it was answered.*

- Which exact subset of `bin/` ships, and how the omitted commands fail (clean "not available" vs
  broken call). **Answered:** the `EXCLUDE` globs in `uis/omarchy/setup.sh` decide it (Arch package
  management, the installer/AUR/web-app/gaming/AI families, the helpers that call `pacman`/`yay` or
  Debian-less systemd units); the commands get no `/usr/bin` link, so a login shell does not find
  them, and the command menu hides the rows whose action calls one of them, so the omitted set fails
  as "not in the menu" rather than broken. (Inside the session Hyprland prepends `$OMARCHY_PATH/bin`
  to `PATH`, upstream's `default/hypr/envs.lua`, so a command reached from the desktop still resolves
  and dies on what it reaches for; the hiding, not the `PATH`, is what keeps the feature unoffered.)
- Whether `greetd` + `tuigreet` is enough to pick the Hyprland/UWSM session, or a small
  `greetd`/session tweak is needed. **Answered:** enough — Debian's `greetd` wants the user
  `_greetd` and `vt = 7`, and the port ships that `config.toml`; the first boot landed on Hyprland.
- `uis/omarchy` carries its own copies of the device files (the sway session's went with it).
  **Answered:** yes — the `keyd`/udev/ALSA files live under `uis/omarchy/files/`.
- The first release number for a released Omarchy UI (likely `v0.2.0`, decided at F7).
  **Answered:** `v0.2.0` (see `docs/releases/v0.2.0.md`).
- Whether to keep upstream's `$OMARCHY_PATH/bin` prepend in the session `PATH`. **Open, low
  priority:** it is upstream's own (`default/hypr/envs.lua`), and it means a command the port leaves
  off the `/usr/bin` farm still *runs* when the desktop reaches it and dies on what it reaches for
  (`pacman`, the un-vendored `install/` tree) rather than not existing. What keeps the feature
  unoffered is the menu-row hiding, so dropping the prepend would make "left off `PATH`" mean the
  same thing in a session as in a login shell, at the price of patching a file the pinned tree owns.
- Where the build root lives (`BUILD_ROOT`, default `~/.cache/debian-aarch64`). **Open:** the default
  is on the eMMC, which is the disk `install-emmc.sh` rewrites with `rsync --delete`, so a build root
  kept there is destroyed by the install that uses it (`/deboma-build` was lost that way). A disk that
  is never installed over is the safer home, chosen with `BUILD_ROOT=<path>` — never with a symlink
  over the default path, which root's `rsync` refuses to follow.

---

## 8. Milestone 2 — the port as Debian packages (v0.3.0)

`apt install omarchy-desktop` on a stock Debian forky must give the desktop the image carries, from
the same bytes, and moving to a new upstream release must be a review rather than a re-vendoring.

### 8.1 Why the current shape does not scale

Measured on the v0.2.0 tree, not estimated:

| Symptom | Measurement |
|---|---|
| Upstream is copied into git | `uis/omarchy/files/usr/share/omarchy/` is **24 MB, 1320 files** (`bin` 532, `shell` 238, `themes` 168 of which 15 MB are backgrounds, `default` 244, `config` 48, `etc` 53, `applications` 33). Every upstream bump is a 1300-file diff nobody can review. |
| The port's decisions live in a script | `uis/omarchy/setup.sh` is **460 lines** running as root in the chroot: 50 `EXCLUDE` globs, one `KEEP` exception, a `HIDE_ROWS` list and a 60-line menu-extension generator. It runs once, for one user, at build time. A Debian user who installs later gets none of it, and a package upgrade cannot re-run it. |
| The port duplicates upstream's system files | **20 of the 24 files** in `uis/omarchy/files/etc/` are verbatim copies of files in the vendored `usr/share/omarchy/etc/` (`sysctl.d/99-omarchy-sysctl.conf`, `udev/rules.d/60-omarchy-io-scheduler.rules`, `xkb/symbols/omarchy`, `profile.d/omarchy.sh`, six `systemd/*.conf.d`, …). Nothing applies upstream's `etc/` tree — its installer does — so these copies are the only carrier of those settings, frozen at the pin: an upstream change to them never reaches an image, silently. |
| Arch-only references are policed by hand | **78 files** in the shipped subset call `pacman`/`yay`/`mkinitcpio`/`limine`/`plymouth`. What keeps the desktop from offering them is the `EXCLUDE` array and a human reading it. |
| Upstream tags releases now | `v4.0.0` … **`v4.0.5`** (2026-10-18). The pin is a *branch* commit (`da2db1a`, 532 commands) **ahead** of the newest tag (449 commands); `quattro` HEAD is 535. Upstream's `version` file says `4.0.0.alpha` at every tag, so the tag is the only truthful version. |
| Upstream ships tests nobody runs here | `test/cli`, `test/shell` (**285** `.sh` files plus QML/Lua fixtures) and `test/acceptance` (in-guest, needs a live session). `test/` is excluded from the vendored tree, so the only regression signal is the maintainer's eye. |
| One delivery vehicle | The image is the only way to get the desktop; "others install it" needs a second vehicle built from the same source of truth. |

### 8.2 The design: upstream is data, the port is policy, CI compiles both

Three rules, and §8.3–8.9 follow from them:

1. **Upstream never lives in this repository.** One pin file (`debs/upstream.pin`: repository, tag
   or commit, `sha256` of the tarball). `scripts/fetch-upstream.sh` downloads it into `$SRC_DIR`
   once and verifies the hash; afterwards the build is offline. The port's delta is `debian/`,
   `debs/policy/` and `debian/patches/` — nothing else.
2. **The port's decisions are data.** Every list that is prose in `AGENTS.md` or an array in
   `setup.sh` becomes a file under `debs/policy/`: which `omarchy-*` commands ship
   (`commands.exclude` + `commands.keep`), which menu rows hide (`menu.hide`), how each Arch
   package maps to Debian (`packages.map`), and what happens to each file of upstream's `etc/`
   (`etc.map`). Each one is read by the **build** (to generate the `/usr/bin` farm, the
   metapackage `Depends` and `/etc`) and by the **audit** (to prove nothing upstream ships is left
   unclassified).
3. **The image is built from the archive.** `build-rootfs.sh` gains `APT_SOURCES`; `uis/omarchy`
   shrinks to a profile whose `packages.list` is `omarchy-desktop`. An image and an `apt install`
   then differ only in what the device adds, and a release is "the archive plus an image built from
   it".

| | **A. Packages + policy (chosen)** | B. One vendored source package | C. Omarchy in Debian proper |
|---|---|---|---|
| Upstream bump | one pin line + an audit report | 1300-file commit, still unreadable | upstream's own cadence, not ours |
| `/etc` drift | impossible (mapping + explicit overrides) | stays | n/a |
| Install on stock Debian | yes | yes | yes, once a Debian maintainer adopts it |
| Arch-only decisions | policy data, audited | by hand, as today | by Debian maintainers |
| CI work | medium, ours | low | high, out of our control |
| Fits this device's kernel | yes | yes | no |

Rejected: **B** optimises the wrong thing (it keeps every symptom of 8.1 except the vendoring
directory); **C** is the right long-term home if upstream ever wants a Debian maintainer and is
worth proposing once this is stable, but it cannot carry a device kernel and is not in our hands.
It is a milestone-3 candidate, not this one.

### 8.3 The package set

| Source package | Binary | Arch | Contents | Version |
|---|---|---|---|---|
| `omarchy` | `omarchy` | all | upstream tree at `/usr/share/omarchy` (curated by manifest, §8.5), `/usr/bin/omarchy-*` links generated from `commands.*`, `applications/` entries and icons, the uwsm `env.d` snippet, the `wayland-sessions` entry | upstream tag: `4.0.5-1` |
| `omarchy-next` | `omarchy-next` | all | the same `debian/`, built from a `quattro` snapshot (`4.0.5+git<date>.<sha>-1`); `Conflicts`/`Replaces` `omarchy` because it owns the same paths, so exactly one channel is installed | snapshot |
| `omarchy-debian` | `omarchy-debian` | all | the port: `/etc` + `/usr/lib` glue (units, udev, sysctl, tmpfiles, xkb, portals/PAM, fontconfig, keyd, logind/oomd), user units, `/usr/libexec/omarchy-debian/` (seeder, menu generator, doctor) | ours |
| `omarchy-debian` | `omarchy-desktop` | all | metapackage: `Depends` on the two above plus the desktop set generated from `packages.map` | ours |
| `omarchy-hayato` | `omarchy-hayato` | all | device glue: the Chromebook `keyd` map (top row to F-keys and VTs), the model-specific backlight/input rules, 4 GB tuning, the `alsa-utils` requirement the UCM boot sequence needs | ours |
| `linux-mt81` | `linux-image-7.2.7-mt81`, `linux-headers-7.2.7-mt81` | arm64 | the kernel this repository builds (`kernels/mediatek-mt81/`), packaged with `make bindeb-pkg` behind a thin `debian/` | kernel |
| `deboma-tools` | `deboma-tools` | all | the scripts that run **on** the device: `check-system.sh`, `install-kpart.sh`, `install-emmc.sh`, and the `zz-kpart` kernel postinst hook that rebuilds the FIT and rewrites the kernel partition | ours |
| `archive-keyring` | `deboma-archive-keyring` | all | the apt archive key plus the `deboma.sources` snippet | key epoch |

Only `omarchy-hayato` and `linux-mt81` are device-specific; everything a generic Debian user needs
is `omarchy`, `omarchy-debian` and `omarchy-desktop`. Names checked against the forky indexes: none
of `omarchy`, `omarchy-desktop`, `omarchy-debian`, `omarchy-hayato`, `deboma-tools` exists in the
archive.

Two policy frictions, decided here so the phases do not rediscover them:

- **`bat`.** Debian's `bat` installs `/usr/bin/batcat`, because `/usr/bin/bat` belongs to
  `bacula-console-qt`, while Omarchy's aliases, `MANPAGER` and fzf previews call `bat`. The v0.2.0
  image ships `/usr/local/bin/bat`, which a package may not do (policy reserves `/usr/local` for
  the administrator). The package carries a **patch** pointing those references at `batcat`, which
  is what a Debian user has anyway; `update-alternatives --install /usr/bin/bat bat /usr/bin/batcat
  20` stays documented as the fallback if the patch grows.
- **The `version` file.** Upstream's tree says `4.0.0.alpha` at every tag, and the About panel reads
  it. The Debian version comes from the tag; a one-line patch writes that tag into the shipped
  `version` file so a package never reports a pre-release that describes no released code.

### 8.4 Layout

```
debs/
  upstream.pin                 # repo, ref, tag/commit, tarball sha256 — the one file a bump touches
  policy/
    commands.exclude           # globs left off PATH (today's EXCLUDE)
    commands.keep              # exceptions (today's KEEP: omarchy-update-time)
    menu.hide                  # rows hidden by id (today's HIDE_ROWS: trigger.share)
    packages.map               # Arch package -> Debian package(s) | drop:<reason> | build:<recipe>
    etc.map                    # upstream etc/ path -> /etc|/usr/lib path | drop | override:<file>
    overrides/                 # only the files that replace an upstream one (PAM, sysctl, …)
  omarchy/debian/              # upstream tree: rules, install manifest, generated links, patches
  omarchy-next/debian/         # the same packaging, snapshot pin (generated from the above)
  omarchy-debian/debian/       # the glue and the metapackage
  omarchy-hayato/debian/
  linux-mt81/debian/
  deboma-tools/debian/
  archive-keyring/debian/
scripts/                       # the existing scripts/ directory, plus:
  fetch-upstream.sh            # pin -> $SRC_DIR, sha256-checked, cached
  audit-upstream.sh            # the port contract (§8.8) — CI and local
  build-debs.sh                # the local equivalent of the CI jobs
  publish-archive.sh           # reprepro/aptly, signing, pruning
```

`uis/omarchy/` stays — the UI axis is what keeps the build device-agnostic — but becomes a profile:
`packages.list` = `omarchy-desktop` (plus `omarchy-hayato` for this device), `files/` empty,
`setup.sh` deleted once the seeder covers it. `verify-rootfs.sh` then checks `dpkg-query` for those
packages and the `/usr/bin` farm instead of a vendored tree.

### 8.5 The policy files are the port

This is what replaces `setup.sh` and makes updates reviewable.

- **`commands.exclude` / `commands.keep`** — the 50 globs and the one exception, verbatim, as the
  single definition of "left off PATH". The build generates `debian/omarchy.links` from them (a
  real, dpkg-owned `/usr/bin` farm, so `apt purge` removes it and the pruning loop disappears); the
  seeder uses the *installed* link set to generate the menu extension, so a hidden row cannot
  disagree with a missing command. The audit proves every file in upstream's `bin/` is either
  linked or excluded, and that every glob still matches something — a stale glob is a bug, not a
  comment.
- **`packages.map`** — one line per Arch package of `install/omarchy-base.packages` plus the
  aarch64 list, with a disposition: Debian name(s) (`1:1`, `1:n` for splits, `n:1` for merges),
  `drop:<reason>` or `build:<recipe>`. The build generates `omarchy-desktop`'s `Depends` from it,
  the audit fails when upstream adds a package the map does not mention, and
  `uis/omarchy/README.md`'s 265-name table is generated from it rather than maintained by hand.
- **`etc.map`** — every path of upstream's `etc/` mapped to where Debian wants it (`/etc/…`,
  `/usr/lib/systemd/system`, `/usr/lib/udev/rules.d`, `/usr/lib/sysctl.d`, `/usr/lib/tmpfiles.d`),
  or `drop:<reason>`, or `override:<file>` pointing into `policy/overrides/`. This is what kills
  the 20 duplicates: the package installs upstream's version, the override carries the port's
  change, and the audit fails if an override has no upstream counterpart, if an upstream file is
  silently skipped, or if a file under `/etc` in this repository has no mapping.
  Two kinds of file are *not* overrides and are listed in the package's own install manifest
  instead: files upstream does not ship at all (`keyd/default.conf`, the fontconfig alias, the
  backlight udev rule), and files this port must change in a vendored tree, which are patches.
- **`menu.hide`** — rows, by id, that need something Debian does not package at all.

Everything the port does to upstream's *code* stays a patch in `debian/patches/` with a `series`
file, the same convention as `kernels/<flavor>/patches/`: `policy/` is for files and decisions,
`patches/` for edited upstream files, and the audit checks the split (an override that is 95%
upstream should be a patch).

### 8.6 Per-user state: the seeder

A package may not write `$HOME`, and that is the one thing today's build does that Debian has no
place for. The replacement is a **user unit**, `omarchy-debian-seed.service`:

```
[Unit]
Description=Seed Omarchy's user configuration (omarchy-debian)
ConditionPathExists=!%h/.local/state/omarchy-debian/seeded
Before=graphical-session.target
[Service]
Type=oneshot
ExecStart=/usr/libexec/omarchy-debian/seed --if-needed
[Install]
WantedBy=graphical-session-pre.target
```

- `graphical-session-pre.target` is the systemd/UWSM hook that runs *before* Hyprland, so the shell
  never starts against an unseeded `~/.config`.
- The seeder is idempotent and **records what it wrote**: it adds missing files, never overwrites
  one it did not write, and re-runs after a package upgrade to add what the new version needs.
  `--reset` re-seeds everything for someone who wants upstream's defaults back.
- It carries today's build-time steps one to one: `~/.config` from `config/` and
  `default/{omarchy,uwsm,environment.d}`, the branding files (`screensaver.txt`, `about.txt`),
  `~/.config/omarchy/themes`, the `default/bashrc` source line appended to Debian's `~/.bashrc`,
  the dock pruning of `.desktop` ids that do not exist, the generated menu extension, the
  natural-scroll block in `~/.config/hypr/input.lua`, and the `first-run-user` marker.
- **Decision (P3):** vendor upstream's `install/user/` (the portable half of `install/`) and let
  `omarchy-provision-user` run for real, patched where it calls `pacman`/`mise`; **or** keep the
  port's seeder. Criterion: the vendored flow must complete in a chroot with no `pacman`, no
  network and no Arch-only unit, and the audit must show its steps map onto files this port ships.
  If it does, prefer upstream's — it removes the "`finalize-user` stays unmarked" wart in
  `AGENTS.md`. If not, the seeder above is the answer and the marker stays.

### 8.7 Build and CI/CD

Toolchain, all present in forky (checked): `debhelper` 14.5, `dpkg-dev` 1.23.11, `lintian` 2.142.0,
`piuparts` 1.6.0, `autopkgtest` 6.0, `sbuild` 0.91.10, `mmdebstrap` 1.5.7, `reprepro` 5.4.6,
`aptly` 1.6.2, `gpg` 2.4.9.

Stages of `release.yml` (tag `v*`) and `ci.yml` (push/PR):

1. **fetch** — `debs/upstream.pin` into `$SRC_DIR`, `sha256` verified, cached; a re-run is offline.
2. **audit** — `scripts/audit-upstream.sh` (§8.8). Red fails the PR before anything is built, with
   the report as the job summary.
3. **build** — one `dpkg-buildpackage -b -us -uc` per source package in a forky chroot
   (`mmdebstrap --variant=apt`; `sbuild` for the strict run), `Rules-Requires-Root: no`,
   `SOURCE_DATE_EPOCH` from the upstream commit date. `ubuntu-24.04-arm` (GitHub-hosted, free for
   public repositories since 2025-08) builds the kernel and the `all` packages, so one image of the
   runner covers everything.
4. **verify** — `lintian --fail-on error`, `piuparts` (install → upgrade → purge), `autopkgtest`
   running upstream's `test/cli` and `test/shell` against the *installed* tree, `hyprland
   --verify-config` on the seeded config, and the seeder in a throw-away `$HOME`.
5. **publish** — `reprepro` (or `aptly`) into `dists/forky/{main,binary-arm64,binary-all}` plus
   `pool/`, signed `Release`/`InRelease`, uploaded to a `gh-pages` branch of a dedicated
   `deboma-apt` repository together with `deboma-archive-keyring`. Two versions kept; budget is
   `omarchy` ≈ 20 MB, `linux-image` ≈ 45 MB (14.9 MB `vmlinuz` + 30 MB modules), the rest small —
   comfortably inside Pages' 1 GB soft limit.
6. **image** — `APT_SOURCES=<the archive> scripts/build-rootfs.sh` → `make-image.sh` →
   `make-release.sh`, so the released image is built from the published debs, not from a checkout.
   `SHA256SUMS` still covers everything a downloader gets.

`upstream-watch.yml` (daily and on demand) opens the update PR; it discovers releases with
`uscan --report` from a `debian/watch` file, so the standard Debian tooling does the polling.

### 8.8 The update machine: an upstream bump is a review

`debs/upstream.pin` is the only file a version bump touches. The watcher compares it to the newest
`v4.*` tag and, when there is one, pushes a branch that changes the pin and runs the audit, whose
Markdown report becomes the PR body:

- **files** added/removed/changed per shipped tree (`bin`, `shell`, `config`, `default`, `etc`,
  `themes`, `applications`, `version`), with counts and the paths of new files;
- **commands**: new/removed `bin/omarchy-*`, each flagged *covered* (matches `commands.exclude`) or
  *unclassified* — the review question becomes one line per new command, not a diff;
- **packages**: Arch names in `install/*.packages` that `packages.map` does not mention, and mapped
  Debian names that no longer resolve on `forky`;
- **`etc/`**: upstream files `etc.map` does not mention, overrides whose upstream file changed (the
  override may be stale), and files this port ships that upstream deleted;
- **config the port appends to** (`hypr/input.lua` for natural scroll, `bashrc`, the menu
  extension): whether the anchor still exists and the append is still last-wins;
- **Arch-only references**: new files reaching for `pacman`/`yay`/`limine`/`mkinitcpio`/`plymouth`
  that no policy line allows;
- **QML surface**: the shell's `import` statements against the `qml6-module-*` set this port
  installs, so a new upstream import that Debian's Quickshell lacks is caught before a boot.

**The contract, in one sentence:** an upstream bump is mergeable when the audit classifies every
file, command, package and `/etc` entry, and CI is green. That is the whole point of this
milestone — it turns "port Omarchy updates into Debian" from a 1320-file exercise into a report.

The audit also keeps this document honest: command counts, unmapped package names and unmapped
`etc/` entries are generated from the same files it reads, so those claims cannot go stale without
a red job.

### 8.9 Verification

- **Without hardware** (CI): `lintian`, `piuparts`, upstream's `test/cli` + `test/shell` (285
  files) against the installed tree, `hyprland --verify-config`, the seeder in a throw-away
  `$HOME`, `dpkg -c` file lists against the manifest, and `verify-rootfs.sh` on an image built from
  the archive.
- **On hardware** (the gate, unchanged): write the card or the released image, boot, and
  `check-system.sh` (now shipped by `deboma-tools`) into `reports/`. Plus the test that proves the
  milestone: a **bare forky** card or VM that has never seen this repository, `apt install
  omarchy-desktop`, and the same report — "others can install it" demonstrated, not asserted.
- The 4 GB/Panfrost risks of §6 do not change: packaging moves bytes, not drivers.

### 8.10 Phases

**P0 — Policy extraction, no behaviour change.**
Move `EXCLUDE`/`KEEP`/`HIDE_ROWS` and the menu generator out of `setup.sh` into `debs/policy/` and
a generator that `setup.sh` calls. *Verify:* on a fresh build the generated menu extension and the
`/usr/bin` farm are byte-identical to v0.2.0's, and `check-system.sh` on the card still reports the
same 74 OK / 2 WARN / 0 FAIL.

**P1 — The pin.**
`debs/upstream.pin` + `scripts/fetch-upstream.sh` + the install manifest reproduce the vendored
tree from the upstream tarball: the pin carries the tarball's `sha256`, the fetch caches in
`$SRC_DIR`, and the manifest is what turns the upstream tree (2083 paths at `v4.0.5`) into the 1320
files this port ships. *Verify:* applying the manifest to the fetched tree yields the same file
list **and** the same hashes as `uis/omarchy/files/usr/share/omarchy/`; the second fetch works
offline.

**P2 — The `omarchy` package.**
`debs/omarchy/debian/` builds from the **v4.0.5 tag** (not the branch pin): manifest trimming,
generated links, applications/icons normalisation, the `bat` and `version` patches. *Verify:*
`dpkg -c` matches P1's tree modulo `/etc`; `lintian` clean; the image installs the deb instead of
the overlay and boots to the same desktop; the audit explains every difference between `da2db1a`
and `v4.0.5` (532 vs 449 commands) or the port patches it.

**P3 — `omarchy-debian`, the seeder, `etc.map`.**
The 24-file `/etc` glue becomes upstream's files plus `overrides/`; the seeder replaces
`setup.sh`'s per-user half; `dh_installsystemd --user` installs the unit; §8.6's `install/user`
decision is taken on the audit's evidence. *Verify:* `piuparts` clean; a chroot test seeds a fresh
`$HOME` to the same tree v0.2.0 produced; `hyprland --verify-config` accepts the seeded config.

**P4 — `omarchy-desktop`, `packages.map`, the image.**
`Depends` generated from the map, `uis/omarchy` shrinks to a profile, `build-rootfs.sh` learns
`APT_SOURCES`. *Verify:* an image built from a **local** archive boots and `check-system.sh`
matches v0.2.0's report; the README mapping table is generated and equals 265 names.

**P5 — The archive.**
Signing key, `deboma-archive-keyring`, `reprepro`, `InRelease`, publishing, pruning, and a migration
note for a v0.2.0 system whose `/usr/share/omarchy` is unpackaged (dpkg refuses to adopt files it
does not own). *Verify:* on a fresh forky chroot, install the keyring deb → `apt update` → `apt
install omarchy-desktop` → `apt purge` leaves nothing; `apt-get download` verifies against
`InRelease`.

**P6 — CI/CD.**
`ci.yml`, `release.yml`, `upstream-watch.yml`, `debs/README.md`. *Verify:* a PR that bumps the pin
gets the audit report and a green matrix; a tag publishes an archive a fresh forky installs from;
the image in that release is built from that archive.

**P7 — The device side.**
`linux-mt81` debs (`make bindeb-pkg` plus a thin `debian/`), the `zz-kpart` postinst hook,
`deboma-tools`, `omarchy-hayato`. *Verify:* on the Hayato, `apt upgrade` from the archive installs
a new kernel, the hook rebuilds the FIT and rewrites p1 (`futility show`), and `uname -r` after
the reboot is the new release.

**P8 — v0.3.0.**
Release notes (`docs/releases/v0.3.0.md`), a README section *Install on your own Debian*, the
bare-forky hardware test on the card, `reports/` evidence. *Verify:* the notes claim only what the
reports show, and the image and the apt user get the same binaries.

**P9 — (stretch, in this order).** Upstream's `test/acceptance` on the Hayato over SSH; `reprotest`
in CI; `omarchy-next` from `quattro` head; trixie backports if the archive ever serves stable; the
`omarchy-pkgs` applications (milestone 1's F8).

### 8.11 Risks and open questions

- **Upstream moves faster than tags.** The tag lags the branch (449 vs 532 commands at the pin), so
  packaging only releases may remove things the desktop relies on. Mitigation: P2's audit decides
  that explicitly, `omarchy-next` exists for the branch, and a needed branch fix arrives as a patch.
- **The seeder is the riskiest new mechanism.** Ordering, never clobbering user edits, and
  re-seeding on upgrade all have failure modes a package cannot undo. Mitigation: the written-file
  manifest, `--if-needed`/`--reset`, a dry-run test in CI, and the image keeping build-time seeding
  as the fallback until the seeder has a hardware cycle behind it.
- **Policy friction.** Handled by the `bat` patch and `etc.map`; every new case the audit finds
  becomes a policy line, not a comment.
- **Trust.** A personal archive means users trust one signing key: keep it offline, sign `InRelease`
  in CI from a dedicated key in secrets, publish the keyring as a hashed deb, document rotation in
  `debs/README.md`.
- **Archive size.** Two kernel versions plus images fit Pages today; if the kernel grows, move the
  `pool` to object storage and keep `dists` on Pages.
- **forky only.** Debian stable's Hyprland/Quickshell are older than the shell needs; the README
  says so rather than pretend a trixie install works.
- **Open:** does `omarchy-desktop` depend on `omarchy` (release) or `omarchy | omarchy-next`
  (either)? Proposed: the release, with `omarchy-next` an explicit install. Decide in P4 with the
  audit's delta in hand.
- **Open:** whether the kernel package or `deboma-tools` owns the `zz-kpart` hook (a kernel-only
  user would then get p1 updates without the doctor). Decide in P7, when the hook is written.
