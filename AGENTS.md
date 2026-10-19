# AGENTS.md

## Project

Build a **Debian arm64** operating system (suite `forky`) for the **Google Hayato** Chromebook
(MediaTek MT8192, board codename `google-asurada`), reusing Nura's hardware support — kernel,
device tree, patches, modules and boot flow — instead of Alpine Linux.

This repo started empty; the scaffolding below is being created incrementally. Treat anything not
yet present in `scripts/` as not implemented.

## Language convention

- **All versioned artifacts are written in English**: source code, comments, commit messages,
  docs, `AGENTS.md`, scripts.
- Conversation with the maintainer may be Spanish and/or English. Artifacts are English only.
- Everything generated is versioned here (build scripts, kernel packaging, device package,
  installer, docs). Do not leave useful work only in `/tmp`.

## Critical upstream facts

- **Nura is postmarketOS renamed** (rebrand 2026). Old names `postmarketOS`, `pmOS`, `pmaports`,
  `pmbootstrap` refer to the same ecosystem; expect them in sources.
- The live wiki (`wiki.nura.eco`, `wiki.postmarketos.org`) is behind **Anubis** (proof-of-work
  anti-bot): `webfetch` returns a challenge page, not content. Use `git clone` from
  `gitlab.postmarketos.org` (the git protocol is **not** blocked) or the Wayback Machine.
- The `gitlab.com/postmarketOS/*` mirror is **stale**. Always prefer
  `gitlab.postmarketos.org/postmarketOS/*`.

## Target hardware (the install machine)

| Item | Value |
|---|---|
| Model | Google Hayato rev1 (ASUS Chromebook Detachable / Flip CM3 CM3200) |
| SoC | MediaTek MT8192 "Asurada" (4×A76 + 4×A55), Mali-G57 MC5 (Panfrost) |
| RAM | 4 GB |
| Storage | eMMC 58.2 GB (`mmcblk0`) + microSD (`mmcblk1`) |
| WiFi/BT | Realtek RTL8822CE (`rtw88_8822ce` + `rtl_bt`) |
| Input | `cros-ec-keyb` + Elan `04F3:2E70` (i2c-hid) |
| Firmware | stock coreboot/depthcharge, developer mode, vboot2 |

## Boot chain (do not get this wrong)

- Stock ChromeOS firmware (**depthcharge**) loads a **signed FIT "kpart"** from the GPT partition
  whose PARTUUID equals the `kern_guid` in the kernel command line (`p1` in Nura's layout).
- The kpart is built with **`depthchargectl build --board mt8192`** (`depthcharge-tools`) and
  signed with the **vboot developer keys** (`/usr/share/vboot/devkeys`).
- Partitioning uses **`cgpt`** (ChromeOS GPT). The 128 MB kernel partition is required.
- **Never flash the SPI firmware.** Only touch GPT partitions. Write-protect is disabled on this
  device, so a firmware write could brick it.
- Boot from microSD/USB requires `crossystem dev_boot_usb=1 dev_boot_signed_only=0`; the firmware
  then boots the external disk when it is picked in the developer-mode menu (see below).

Nura's proven disk layout (reuse it, and this repository reproduces it): `p1 pmOS_kernel` 128 MB
(kpart), `p2 pmOS_boot` 512 MB (ext2, where `/boot` lives), `p3 pmOS_root` root. It is created in
exactly one place, `scripts/lib-cgpt.sh`, which `write-sd.sh`, `install-emmc.sh` and
`install-kpart.sh` share; the kernel partition flags (`-S 1 -T 5 -P 10`), the partition types
(`kernel`, `efi`, `data`), the labels and the 512 MB boot size are the ones pmbootstrap uses for
ChromeOS (`pmb/install/partition.py`, whose `Config.boot_size` default is 512).

## Repository layout (device-agnostic)

The build is generic on purpose: any device supported by Nura can be ported by adding a
directory, and kernels are shared between devices.

```
devices/<codename>/        one directory per device
  deviceinfo               pmaports-style device description (sourceable shell)
  kernel                   kernel flavor to use (name under kernels/)
  kernel-cmdline.conf      base kernel command line
  modules-initfs           modules forced into the initramfs
  packages.list            device-specific Debian packages
  APKBUILD.reference       upstream device package (reference only)
kernels/<flavor>/          one directory per kernel
  version                  upstream version (e.g. 7.2.7)
  config.aarch64           kernel config (CONFIG_LOCALVERSION gives the release suffix)
  patches/                 *.patch + a `series` file with the apply order
  APKBUILD.reference       upstream kernel package (reference only)
uis/<ui>/                  one directory per graphical shell
  packages.list            UI packages (Debian names)
  files/                   tree overlaid onto the rootfs; `etc/` is copied as
                           root, `home/` is merged into /home/$USERNAME
  setup.sh                 optional; run inside the chroot after files/ is
                           overlaid, for what a plain tree cannot express
                           (seeding ~/.config from a vendored tree, symlink farms)
  version                  optional pins for components the UI builds itself;
                           omarchy/ has `omasnap.version` (the capture overlay
                           has no Debian package, so build-omasnap.sh needs a tag)
  README.md                what the shell ships and how it deviates upstream
packages/                  device-agnostic base package lists (base.list)
scripts/                   lib.sh (device/kernel/UI resolution), lib-cgpt.sh
                           (the ChromeOS GPT layout), lib-dist.sh (what a
                           published artifact must not carry) + build/install
                           scripts, including make-image.sh / make-release.sh
reports/                   check-system.sh output captured on real hardware, kept
                           as evidence for the checks (see reports/README.md)
docs/                      plan-omarchy.md, recon.md, releases/<version>.md (release
                           notes, reused as the tag message and the GitHub
                           release body)
```

Select a device with `DEVICE=<codename> scripts/...`; with a single device it is picked
automatically. Select the graphical shell with `UI=<name>` (default `omarchy`).

### The image carries this repository

`build-rootfs.sh` stages the **committed** tree (`git archive HEAD`, so never an untested working
copy) into the image at `/home/$USERNAME/Dev/<repo directory name>`, next to a `REVISION` file, and
writes the same information to `/etc/debian-aarch64-revision` (commit, device, UI, kernel, date).
It also installs `check-system.sh` as `/usr/local/sbin/check-system.sh`. This is not decoration:
`install-emmc.sh`, `install-kpart.sh` and the package checks in `check-system.sh` are meant to run
**on the device**, they source `scripts/lib.sh`, and the card that installs to the eMMC is the same
system that has to rewrite its own kernel partition later. A copy found on a card can therefore be
told apart from the checkout it came from - check `REVISION` before trusting it. It is a snapshot:
update it by rebuilding, not by editing it in place. The script warns when the working tree has
uncommitted changes, since those do not travel into the image.

## Vendored reference (pinned)

- Upstream: `pmaports` commit `0e458a2417d6f5ed61c7b70621d5632e30136091` (2026-10-15).
- `kernels/mediatek-mt81/` — mainline Linux **7.2.7** from `cdn.kernel.org` + patches + config.
  Built with `make LLVM=1` (clang/lld).
- `devices/google-asurada/` — `deviceinfo`, `kernel-cmdline.conf`, `modules-initfs`.

## Conventions and gotchas

- The shell in this environment is **ash (busybox)**: no brace expansion (`{a,b}`), no `[[ ]]`.
  Write POSIX sh, or call `bash` explicitly.
- Build/run natively on this aarch64 machine; no cross-compiler needed.
- **`/tmp` is a ~1.9 GiB tmpfs** — too small for kernel/rootfs work. Keep large artifacts on
  the real filesystem; the scripts default to `$HOME/.cache/debian-aarch64`
  (`BUILD_ROOT`, `WORK_DIR`, `SRC_DIR`). `/tmp/opencode` is fine only for small scratch files.
- **Never edit a script while it is executing.** The shell re-reads the file as it goes and can
  die with `unexpected EOF while looking for matching '"'`. Write the new version elsewhere and
  `mv` it into place.
- **`pipefail` is set in every script here, so never test the status of `producer | grep -q PAT`**:
  `grep -q` exits on the first match, the producer then dies of SIGPIPE (141) and the pipeline -
  and with it the `if` - reports failure although the pattern *was* found. It depends on how far
  the producer got before the pipe closed, so the same input passes on a fast machine and fails on
  a slow one (`check-system.sh`'s firmware check reported a loaded firmware as missing on the card
  and as present on the host). Capture the output first and use `grep -q PAT <<<"$var"`, or a
  single `grep -rqs PAT <path>`.
- **`cp -a "$src/." "$dst/"` rewrites `$dst` itself, not only its contents**: GNU cp applies the
  source directory's **owner and mode** to the destination directory. Verified with cp 9.x: a
  root-owned 0755 `dst` came out owned by the invoking user and 0775 after copying a user-owned
  `src/.` into it. A build script that copies a staged tree into a rootfs this way silently leaves
  the destination (e.g. `/usr/share` and `/usr/share/applications`) owned and writable by the
  build user. `install-omasnap.sh` installs its files one at a time for exactly this reason, and
  `build-rootfs.sh` `chown -R root:root`s the staged UI tree before `rootfs-setup.sh` copies it.
  `install -Dm<mode>` (which creates the parents as root) is the safe form.

### Host toolchain

- `scripts/00-deps.sh` installs the same tool set from either package manager, because the
  reference machine runs this port (Debian) as well as having built it from Alpine: `apk` is used
  when present, `apt-get` otherwise. The Debian names differ in a few places (`rust-bindgen` ->
  `bindgen`, `elfutils-dev` -> `libelf-dev`, `pahole` -> `dwarves`, `vboot-utils` ->
  `cgpt` + `vboot-kernel-utils`, `dtc` -> `device-tree-compiler`, `gptfdisk` -> `gdisk`,
  `musl-dev` -> glibc via `build-essential`). On Debian the kernel's rust needs (`rustc`,
  `rust-src`, `bindgen`, `libclang-dev`) and BTF (`dwarves`) are part of that list too.
- The kernel build also needs the **`openssl`** binary (module signing) and **`findutils`** (the
  kernel's initramfs scripts use `find -printf`, which BusyBox find lacks).

### Debian naming

- `deviceinfo_arch` uses distro/Alpine names (`aarch64`), but **debootstrap requires the Debian
  name** (`arm64`). `lib.sh` maps between them; passing `aarch64` yields
  `Invalid Release file, no entry for main/binary-aarch64/Packages`.

### Kernel staging

- `make zinstall` installs the image as **`vmlinuz-<release>`** only; there is no plain `vmlinuz`
  in the staged tree.
- `CONFIG_MMC_MTK`, `CONFIG_DRM_MEDIATEK` and `CONFIG_EXT4_FS` are built-in (`=y`), so the root
  filesystem and the display work without any initramfs module.
- `CONFIG_DRM_PANFROST` (the driver this MT8192 uses) and `CONFIG_DRM_PANTHOR` (newer Mali) are both
  built-in, so every `update-initramfs` prints
  `W: Possible missing firmware /lib/firmware/arm/mali/arch14.8/mali_csffw.bin for built-in driver
  panthor`. It is noise, not a missing piece: initramfs-tools scans built-in modules for firmware
  requirements, and panthor never drives the Mali-G57 here.
- `CONFIG_EXT2_FS` is **not set**, and the `pmOS_boot` partition is formatted ext2 anyway
  (`scripts/lib-cgpt.sh`). That works because `CONFIG_EXT4_USE_FOR_EXT2=y`: the ext4 driver registers
  the `ext2` and `ext3` types, so `mount -t ext2` is served by ext4 and `/proc/filesystems` lists
  ext2/ext3/ext4. Nura's own `/boot` is mounted the same way. Do not "fix" this by enabling
  CONFIG_EXT2_FS.
- Not every `Direct firmware load ... failed` line is a missing firmware. `CONFIG_MTK_SCP=m`, and
  the SCP remoteproc asks for `mediatek/mt8192/scp.img` while only the initramfs exists, so every
  boot logs two `remoteproc remoteproc0: Direct firmware load for mediatek/mt8192/scp.img failed
  with error -2` and one `request_firmware failed: -2`; three seconds later the module is loaded
  from the real root filesystem and the log continues with
  `Booting fw image mediatek/mt8192/scp.img, size 309164` and `SCP is ready. FW version
  asurada_scp_v2.0.20536`. The file is installed (`firmware-mediatek`) and Nura loads the very same
  size, so this is the module being probed after the rootfs, not a missing piece; every function
  this port uses (display, audio, Wi-Fi, Bluetooth, suspend) works with the SCP coming up late.
  `check-system.sh` therefore reports the outcome of the load, not the first attempt.

### Userspace / UI (Debian forky)

- **greetd**: Debian's package creates the **`_greetd`** system user (upstream docs say
  `greetd`), and its unit declares `Conflicts=getty@tty7.service`, i.e. it expects `vt = 7` in
  `/etc/greetd/config.toml`. With the upstream name the service dies with
  `configured default session user 'greetd' not found` and the machine silently falls back to a
  console login on tty1.
- **SSH host keys**: Debian's `sshd-keygen.service` is gated on `ConditionFirstBoot=yes`, i.e. it
  generates keys only when `/etc/machine-id` was *empty at boot*. Every system here is a *copy* of
  an image (`write-sd.sh`, `install-emmc.sh`), and the copy is written from a tree that already
  generated its id, so the condition is never true again, `ssh-keygen` never runs and
  `ssh.service` dies on every boot with `sshd: no hostkeys available -- exiting.` (hit on both the
  card and the eMMC install; the card kept failing for as long as it had been booted).
  `rootfs-setup.sh` therefore drops in
  `/etc/systemd/system/sshd-keygen.service.d/90-run-when-keys-are-missing.conf`, which resets the
  inherited condition list (`ConditionFirstBoot=`) and requires the ed25519 host key to be
  **absent** instead: the unit generates whatever key type is missing on the first boot that lacks
  them and is a single `stat` from then on. `build-rootfs.sh` ships `/etc/machine-id` empty and no
  host keys, and `install-emmc.sh` blanks the id and the keys of the copy, so each card and each
  install gets its own identity instead of sharing one journal, one DHCP identity and one SSH
  host key (`lib-dist.sh` makes the same choice for published artifacts).
- `nmtui` lives in the separate **`network-manager-tui`** package (no longer part of
  `network-manager`).
- `wireless-regdb` provides `regulatory.db`; without it cfg80211 logs
  `failed to load regulatory.db` and the WiFi stays on the world regulatory domain. `iw` is in
  `packages/base.list` for `check-system.sh`: without it the wireless interface and the regulatory
  domain are invisible to the report (it SKIPs both checks). The world domain (`country 00`) on its
  own is *not* a failure - it is what remains until NetworkManager or the access point's 802.11d
  country IE sets one (Nura reaches `country MX` from the AP), so the report says so instead of
  warning.
- `zstd` lets initramfs-tools compress the initramfs with zstd; otherwise it warns
  `No zstd in /usr/bin:/sbin:/bin, using gzip`.
- **Bluetooth**: `libspa-0.2-bluetooth` provides PipeWire's BlueZ SPA plugins, but those are
  only a D-Bus client of `org.bluez`. The `bluez` package is what supplies `bluetoothd`,
  `bluetoothctl`/`btmgmt` and the `bluetooth.service` unit; without it the HCI controller
  (`hci0`, bound to `serial0-0` via `hci_uart` in H5 mode, RTL8822CS firmware loaded) is
  never powered up and there is no Bluetooth at all — no scanning, no pairing, and the SPA
  plugins have nothing to talk to, so BT audio silently does not exist. `bluez` is therefore
  in `uis/omarchy/packages.list` alongside the SPA plugin. Debian 5.87 has **no `bluez-utils`**
  (the CLI tools ship in `bluez`; `bluetoothd` is `/usr/libexec/bluetooth/bluetoothd`).
  Verify with `bluetoothctl show` (*Powered: yes*) and `btmgmt info`.
- **Audio (MT8192)**: the card `mt8192_mt6359_rt1015p_rt5682` is only usable once its UCM
  **boot sequence** has run. That sequence (`MediaTek/mt8192/.../init.conf`) connects the
  front-end and back-end DAIs (`I2S3_CH1 DL1_CH1`, …); alsa-lib runs `BootSequence` **only**
  on an explicit `set _boot` — never at open or on a verb set — so something must drive it.
  `/usr/sbin/alsactl` does: on card add `90-alsa-restore.rules` and `alsa-restore.service`
  run `alsactl restore`, which for a card with no saved state falls back to the UCM init.
  Without **`alsa-utils`** the PCMs fail to open with `ASoC: no backend DAIs enabled for
  Playback_*`, ACP marks the `HiFi` profile unsupported, WirePlumber picks profile `off`, and
  the only sink is a **Dummy Output** (volume keys change nothing, no speaker sound).
  `alsa-utils` is therefore in `packages/base.list`. Verify with `pactl list cards` (Active
  Profile `HiFi`) and `wpctl status` (a *Built-in Audio Speaker* sink, not *Dummy Output*).
  Confirmed on hardware: the speaker plays a video.
  The same class of bug will hit any card whose routing lives in a UCM `BootSequence`.
- **ALSA-only applications**: Debian's stock alsa-lib configuration has no usable `default`
  PCM; that device is supplied by **`pipewire-alsa`** (in `uis/omarchy/packages.list`). Without
  it, `aplay`/`arecord` without an explicit `-D`, emulators and some Java/game audio fail
  with *audio open error: No such file or directory* while PipeWire clients (and therefore
  everything using PulseAudio) work fine, which makes the gap easy to overlook.
- **Clock**: Debian enables no NTP client, so a fresh image never synchronises
  (`timedatectl` says *System clock synchronized: no*, *NTP service: n/a*) and only the RTC
  keeps time. `systemd-timesyncd` is in `packages/base.list` for this.
- **Battery gauge**: the fuel gauge (`sbs-battery 8-000b`) registers fine (`battery gas gauge
  device registered`) and its capacity is readable, but it reports `Unknown chemistry: OTC0` and
  the kernel repeatedly logs `power_supply sbs-8-000b: driver failed to report
  'status'/'health'/'time_to_empty_now' property: -5/-6`. This is **upstream, not this port**:
  Nura's own log carries the same messages (1296 of them). What the bar shows is the capacity,
  which works, because it reads `/sys/class/power_supply` directly — `upower` is *not* what
  draws it. `upower` is in `uis/omarchy/packages.list` anyway: WirePlumber asks it for the
  battery percentage, and without the daemon every start logs
  `default: Failed to get percentage from UPower: NameHasNoOwner`.
- **Backlight keys**: `brightnessctl` needs write access to
  `/sys/class/backlight/*/brightness`. Debian's `brightnessctl` ships no udev rule and
  nothing else in the system grants it, so `/sys/class/backlight` stays root-only (0644) and
  the `XF86MonBrightness*` bindings fail with *Permission denied* for the session user.
  `uis/omarchy/files/etc/udev/rules.d/90-brightnessctl.rules` (group `video`, `g+w`) fixes it.
- **Lock key**: the right-most key of the top row emits `KEY_SLEEP`, and that is precisely the
  key systemd-logind turns into a suspend on its own — its button handling consults no polkit and
  no session, which makes it the only suspend path that always works.
  `uis/omarchy/files/etc/keyd/default.conf` therefore leaves the key alone, so logind
  suspends the machine ~0.3 s after the key is pressed; locking is the desktop's own binding.
  Nura instead maps `sleep = coffee` — `KEY_COFFEE`, the kernel's lock/screensaver key, whose
  xkb keysym is `XF86ScreenSaver`. Because keyd grabs the keyboard, logind then never sees
  `KEY_SLEEP`, and since nothing consumes `KEY_COFFEE` either, the Lock key there does
  *nothing* (elogind handles only `KEY_SLEEP`, `KEY_SUSPEND`, `KEY_POWER`, `KEY_POWER2`,
  `KEY_RESTART` and `KEY_ESC`). **That remap is what broke suspend on this image**: the first
  boot suspended on the key, and it stopped the moment keyd started grabbing the keyboard
  (`journalctl` shows `Suspend key pressed short.` in the early boots and not one line of it
  afterwards, while `keyd.rvaiya` logs `DEVICE: match ... (cros_ec)`), so the mapping is left
  out.
  Confirmed on hardware: the first report from a booted card records `5 suspend/resume cycle(s)`.
  Suspending from a session helper goes through `loginctl suspend`, a D-Bus method guarded by
  polkitd (stock `org.freedesktop.login1.suspend` has `allow_active=yes`), which fails with
  *Access denied* from a session logind does not consider active; that needs the daemon (D-Bus
  activated; Debian keeps `systemd-logind` inside the `systemd` package).
  Reading a keymap dump is misleading here: `xkbcli compile-keymap` prints **X** keycodes,
  which are evdev + 8, so `KEY_SLEEP` (evdev 142) shows up as keycode 150 and
  `KEY_BRIGHTNESSDOWN` (evdev 224) as keycode 232.

- **`uis/omarchy/`** is the desktop (Omarchy v4: Hyprland + Quickshell). `rootfs-setup.sh`
  rewrites `/home/brunux` inside the shipped text files to `$USERNAME`, and merges
  `uis/omarchy/files/home/` into that home; `uis/omarchy/README.md` is the reference.
- **tuigreet**: Debian ships the *original* tuigreet **0.9.1**, which has no `--config`/TOML
  support and no background animations (Nura runs the fork, which has both). The greeter's
  personalisation is therefore expressed as flags in `/etc/greetd/config.toml`; the `matrix`
  backdrop and the `custom_title`/widget positions have no 0.9.1 equivalent. Unknown
  components or colour names in `--theme` are silently ignored (they do not break the
  greeter), and `--remember*` needs `/var/cache/tuigreet` owned by the greeter user.
- **The Chromebook keyboard has no F1-F10**, and that is what breaks virtual terminals:
  `mt8192-asurada-hayato-r1.dts` maps the top row to action keys (`KEY_BACK`, `KEY_FORWARD`,
  `KEY_REFRESH`, `KEY_FULL_SCREEN`, `KEY_SCALE`, brightness, mute, volume). Switching VTs needs a
  real F-key keycode: the kernel maps `Ctrl+Alt+F<n>` to `Console_<n>`, and the compositor
  reacts to the `XF86Switch_VT_<n>` keysym that the same keycode produces (`srvr_ctrl(fkey2vt)`
  is part of the default xkb keymap). `uis/omarchy/files/etc/keyd/default.conf` (package `keyd`)
  supplies them:
  `Ctrl+Alt`+top row = VT 1-10, `Search`+top row = F1-F10. Debian names the binary
  **`/usr/bin/keyd.rvaiya`** (the package enables `keyd.service`, and `/etc/keyd/` ships empty).
  keyd reads its config **only at startup** — `keyd.rvaiya reload` after editing — and
  `backspace+escape+enter` makes it quit and release the keyboard.
- **keyd must not grab `cros_ec_buttons` or the headset jack**: both share the keyboard's
  `0000:0000` id, and keyd counts them as keyboards because they report `KEY_VOLUMEUP/DOWN` (its
  heuristic for laptops whose hotkeys live on a separate node). keyd's virtual device does not
  forward `EV_SW`, so grabbing them would silently kill suspend-on-lid-close, the tablet-mode
  switch and the power button (logind loses it). `default.conf` therefore excludes them; the
  exclusions must precede `k:0000:0000`, because keyd returns on the first matching entry, and
  they are hashes of the device name, its key count and the abs/rel masks (`keyd.rvaiya monitor`
  prints them, and `journalctl -u keyd` logs what got matched).
- **Nerd Fonts**: Debian has no Nerd-patched JetBrains Mono, and the desktop asks for the
  family **`JetBrainsMono Nerd Font`** — which, unresolved, makes fontconfig fall back to a
  proportional face (Noto Sans) and renders the terminals and the bar in the wrong font.
  `uis/omarchy` ships `files/etc/fonts/conf.d/50-omarchy-debian-fonts.conf`, which aliases that
  family to `JetBrains Mono` and keeps the icon fonts in the fallback chain. Beware
  `fonts-nerd-symbols`: it is **DFSG-stripped** and only ships Octicons, Codicons, Devicons,
  Seti and Powerline. It has **no Font Awesome (U+F000-U+F2FF) and no Material Design Icons
  (plane 15)** — which is exactly what the theme's icons are — so on its own every icon renders
  as a *tofu* box with the hex codepoint inside. `fonts-font-awesome-legacy` and
  `fonts-materialdesignicons-legacy` supply those two sets and fontconfig's fallback then
  resolves every glyph, with no change to the configuration. Verify where the family resolves
  with `fc-match "JetBrainsMono Nerd Font"` (it must report `JetBrains Mono`), and render a
  glyph with `pango-view --no-display --font="JetBrains Mono 13" --output=/tmp/i.png <text>`
  (package `pango1.0-tools`).
- **Wi-Fi profiles**: Nura and Debian name the wireless interface differently (Nura: `wlan0`,
  Debian/systemd: `wlp1s0`), so a NetworkManager profile copied verbatim is never activated.
  `scripts/wifi.sh import` drops `interface-name=` to bind the profile to any Wi-Fi device. The
  profiles hold the PSK in clear, so they live in `$WIFI_DIR` (`$BUILD_ROOT/wifi`) and are
  git-ignored; `build-rootfs.sh` imports them automatically when that directory exists.
- **Xwayland**: Hyprland enables its built-in Xwayland by default (`xwayland:enabled = true`),
  so the `xwayland` package (which pulls the 25 X libraries) has to be installed or X11-only
  programs (emulators, Wine, some Java/Steam games) cannot run while everything Wayland-native
  works. It is in `uis/omarchy/packages.list`; `check-system.sh` warns when `/usr/bin/Xwayland`
  is missing.
- `pactl` (the XF86Audio* keys) comes from `pulseaudio-utils`, not from `pipewire-pulse`.
- **Screensaver and lock**: `omarchy-screensaver` paints the logo with **ttfx** (Omarchy's Rust
  port of terminaltexteffects; Debian packages the Python original instead) and it finds *and
  kills* the effect with `pgrep -x ttfx` / `pkill -x ttfx`, so the **process name**, not just a
  renderer, is part of the contract. `uis/omarchy/files/usr/local/bin/ttfx` runs Debian's
  `python3-terminaltexteffects` **in-process** (an `exec` would rename the process and the
  screensaver would never end), and `setup.sh` seeds `~/.config/omarchy/branding/screensaver.txt`
  from the vendored `/usr/share/omarchy/logo.txt` (`icon.txt` → `about.txt` for the About panel).
  Missing either one makes the screensaver exit immediately with no message at all. A cycle whose
  screensaver is dismissed before the lock deadline is cancelled **on purpose** (the "I am back,
  do not lock" path), and a lock that has already engaged is a Wayland session lock: nothing but
  the keyboard/`wtype` in that session can answer it.
- **Lock screen PAM**: Quickshell's lock screen authenticates through the PAM service
  **`omarchy-lock-password`**, i.e. `/etc/pam.d/omarchy-lock-password`. Upstream's
  `omarchy-apply-lock` writes that file from Arch's stack (`system-local-login`,
  `pam_systemd_home.so` which Debian does not ship, `pam_faillock` whose tally directory
  `/var/run/faillock` nothing creates), so it is **excluded** and
  `uis/omarchy/files/etc/pam.d/omarchy-lock-password` ships Debian's stack
  (`auth include common-auth` + `account include common-account`). Without the file the shell
  answers `missing-pam` to `omarchy-shell lock lock`, Super+Ctrl+L does nothing, the *idle* lock
  never engages, and `omarchy-system-sleep-lock` suspends with the session exposed - all of it
  silently. `omarchy-shell lock status` publishes `passwordPam`, which is what `check-system.sh`
  asks.
- **Shell environment**: Debian seeds `~/.bashrc` from `/etc/skel`, and nothing sourced Omarchy's
  `$OMARCHY_PATH/default/bashrc`, so the `ls`→`eza` aliases, the `ff`/`ll` helpers, zoxide/fzf
  initialisation and the starship prompt never loaded. `setup.sh` **appends** the source line
  (upstream replaces the file when it is one of the known defaults; appending keeps Debian's
  history/lesspipe/completion settings) and links `/usr/local/bin/bat` → `/usr/bin/batcat`:
  Debian's package of the Rust `bat` installs the binary as `batcat`, while Omarchy's aliases, its
  `MANPAGER` and the fzf previews call `bat`. `fd-find` needs no such link - the pinned tree never
  calls `fd`. `starship`, `lua5.4` and `libnotify-bin` are in `packages.list`, and each one
  degrades *silently*: no prompt, an empty keybindings view (`omarchy-menu-keybindings` returns
  early when `command -v lua` fails) and no terminal notifications.
- **`file` and `ping`**: `omarchy-transcode`/`-ascii` sniff a MIME type with `file` before the
  menu can tell a picture from a video - without it the rows were excluded outright. `file` is in
  `packages/base.list` now and the two commands are back on PATH. `omarchy-debug` reaches the
  network with `ping`, which Arch's base provides and Debian's does not (`iputils-ping`).
- **`xkbcli`**: Debian splits the CLI out of libxkbcommon into **`libxkbcommon-tools`**, and the
  pinned tree calls it twice: the bar's keyboard-layout widget (`xkbcli list --load-exotic`, to
  label the active keymap) and the keybindings view (`xkbcli compile-keymap`, to name the XKB
  keycodes `hyprctl binds` reports as `code:`). Both fall back, so a missing xkbcli is a coarser
  label plus `xkbcli: not found` on stderr every time the cheat sheet opens, not a dead key; it is
  in `packages.list` all the same. Related: `omarchy theme list` runs `find ~/.config/omarchy/themes`
  unconditionally, so a system where the user never installed a theme prints a `find` error before
  the 23 packaged ones - `setup.sh` creates that directory (upstream's
  `omarchy-upgrade-to-quattro` creates it only on systems upgraded from v3).
- **omasnap**: `omarchy-capture-screenshot` ends in `exec omasnap`, so Print and Super+Shift+S do
  nothing without the binary, and Debian packages neither omasnap nor satty. The port builds
  upstream's own tool from `omacom/omasnap` at the tag pinned in `uis/omarchy/omasnap.version`
  (`scripts/build-omasnap.sh` → `scripts/install-omasnap.sh`, the same stage/install split as the
  kernel). Its run-time libraries (`libqt6widgets6`, `libqt6dbus6`,
  `liblayershellqtinterface6`) are in `packages.list`, because the shell's QML modules do not
  pull the Widgets stack in. Debian's `liblayershellqtinterface6` ships **no
  `wayland-shell-integration` plugin**, so Qt cannot select the `layer-shell` integration and
  logs `Could not load the Qt platform plugin "wayland"` while omasnap maps its overlay as an
  ordinary fullscreen window instead of a layer surface - visually identical here (verified by
  screenshotting the overlay), so the plugin is not rebuilt from source.
- **Menu rows that are submenus**: the
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` generator in `setup.sh` hides a row by
  matching its `action` against the `EXCLUDE` globs, but a *submenu parent* has no `action` at all
  and has to be named by id in `HIDE_ROWS`. `trigger.share` is the one that matters: every row
  under it funnels into LocalSend, which Debian does not package, so the whole submenu is hidden
  (a submenu left with no visible row disappears with it).
- **`arch_only()` is the single definition of "left off PATH"**: `setup.sh` uses it for both the
  `/usr/bin` symlink farm and the menu-row generator, and it consults `KEEP` before `EXCLUDE`, so a
  command a glob over-reaches can be named back. That is `omarchy-update-time` — the `omarchy-update*`
  glob drops the update machinery, but this one is `systemctl restart systemd-timesyncd`, and hiding
  its row hid the only UI for the NTP client `packages/base.list` adds on purpose. The mirror image
  is `omarchy-channel-*`: the `Update > Channel` rows called `omarchy-channel-set`, which rewrites
  pacman's mirrorlist and sources `install/helpers/pacman.sh` (not vendored), so the rows died in a
  floating terminal while the command stayed on PATH. Both directions are checks in
  `check-system.sh`, which reads the `/usr/bin` link — **not** `command -v`: Hyprland prepends
  `$OMARCHY_PATH/bin` to the session PATH itself (`default/hypr/envs.lua`), so inside the session
  every vendored command resolves whether or not it has a link, and only a login shell (`bash -lc`)
  sees the farm alone.
- **The symlink farm is pruned, not just grown**: `setup.sh` removes `/usr/bin/omarchy-*` links that
  point into `$OMARCHY_PATH/bin` and match the current `EXCLUDE`/`KEEP`. Without it, adding a pattern
  later left the command reachable forever (the farm only ever added), which is exactly how the
  `Channel` rows above came to be audited with the command still on PATH. Checking the *link* rather
  than a name is what makes the regression check honest.
- **`$OMARCHY_PATH/bin` is on the *session* PATH, and that is upstream's own doing**:
  `default/hypr/envs.lua` prepends it, so an excluded command still **runs** when the desktop reaches
  it (the floating terminal included — `xdg-terminal-exec -e bash -c`, which inherits the session
  environment) and dies on what it reaches for — `pacman`, LocalSend, the un-vendored `install/`
  tree — not on its own name. `omarchy-provision-first-run` retries its first-run steps at every
  login for exactly this reason, appending one attempt per boot to
  `~/.local/state/omarchy/first-run.log` (the hook steps exit 1, the user-unit/GNOME/GTK/speaker
  steps 127) and never marking the flag; the `omarchy-provision-user` it calls first stops the same
  way at `source $OMARCHY_INSTALL/user/all.sh`, so that marker is never written either and its
  idempotent prefix (agent-skill symlinks, xdg user dirs, GTK bookmarks) re-runs each login. Nothing
  of it reaches the journal or the screen. What the
  farm decides is what a *login* shell (SSH, a TTY) sees; what keeps the desktop from *offering* the
  feature is the generated row hiding.

### ChromeOS GPT (`cgpt`)

- **Do not pass `-z` to `cgpt create`**: it zeroes the GPT areas *after* writing them, so the
  following `cgpt add` fails with `GptSanityCheck() returned 2: GPT_ERROR_INVALID_HEADERS`.
- **`cgpt` does not write a protective MBR**, and the Linux kernel refuses to parse a GPT without
  one (`0xAA55` signature plus a `0xEE` entry). Run `parted -s <dev> mktable gpt` first — this is
  why pmbootstrap does it too — then `cgpt create` / `cgpt add` on top of it.
- After writing the table, refresh the kernel's view with `partx -d` + `partx -a`
  (`blockdev --rereadpt` returns `EBUSY` on this microSD card).
- `lsblk -nro PATH <disk>` lists the **disk first**, then its partitions: skip the first line when
  resolving `p1`/`p2`/`p3`. A wrong index here formats the whole disk instead of a partition.
- The tools needed **on the device** are three separate Debian packages and it is easy to install
  the wrong one: `cgpt` provides `cgpt`, **`vboot-kernel-utils`** provides `futility` (the
  similarly named `vboot-utils` ships `crossystem` and symlinks to `futility` but not `futility`
  itself), and `depthcharge-tools` provides `depthchargectl`/`mkdepthcharge`. All three are in
  `devices/google-asurada/packages.list`, together with `rsync`, which `install-emmc.sh` needs.
- **`depthcharge-tools`' system hooks are disabled in the image** by
  `/etc/depthcharge-tools/config` (`[depthchargectl/write] enable-system-hooks = False`, written by
  `rootfs-setup.sh`). The package ships `/etc/kernel/postinst.d/zz-depthcharge-tools` and
  `/etc/initramfs/post-update.d/depthcharge-tools`, which build a depthcharge image and write it to
  a kernel partition on every kernel or initramfs change. They know nothing about this port (the
  board `mt8192` and the command line come from our `deviceinfo`, applied by `make-kpart.sh`, and
  the write is `install-kpart.sh`), and enabled they also break the **build**: `update-initramfs`
  runs in the chroot, where `/proc/cmdline` is the host's — Nura's, which contains `cros_secure` —
  so the hook thinks it is on a depthcharge system, finds no kernel partition and exits 1, and
  `run-parts` then fails `install-kernel.sh`. The `enable-system-hooks` check reads section
  `depthchargectl/write`, not the `[depthcharge-tools]` section the package's own `config.ini` uses.
- A kernel that boots from a ChromeOS kernel partition lives **inside** that partition, so
  installing a new kernel is not finished until p1 is rewritten: `scripts/install-kpart.sh` does
  that (the Debian counterpart of boot-deploy's `flash_updated_depthcharge_kernel`, which reads
  `kern_guid` from `/proc/cmdline`, resolves `findfs PARTUUID=<guid>`, checks the image fits the
  partition and `dd`s it). On the installed system the sequence is
  `scripts/install-kernel.sh /` (staged kernel into the running rootfs) followed by
  `scripts/install-kpart.sh`; without the second step the machine keeps booting the old kernel
  while `/boot` and `/lib/modules` move on.
  Its chroot guard must keep `stat -L` **and** the comparison in that sense: without `-L`, `stat`
  reports the procfs symlink itself (device `0:28`), which can never equal `/`, so the guard passed
  silently; and *equal* is the state of a real system (this root is PID 1's root), so a chroot is when
  the two **differ**. As it was written the guard never fired, and a chroot would have rewritten the
  *host's* kernel partition from the host's `kern_guid`. Both sides are now read before refusing, so a
  system where `/proc` hides PID 1 is not mistaken for a chroot.

### pmbootstrap parity (the install method that is known to boot here)

`scripts/lib-cgpt.sh` reproduces pmbootstrap's ChromeOS install path part by part, because that
method is the one proven on this Chromebook. Read the upstream before changing it:
`pmb/install/partition.py` (`partition_cgpt`, `sanity_check_boot_size`), `pmb/install/format.py`
(`format_partition_with_filesystem`, `format_and_mount_*`), `pmb/install/_install.py`
(`create_fstab`, `copy_files_from_chroot`, `write_cgpt_kpart`, `partprobe`), `pmb/install/blockdevice.py`
(`mount_disk`) and `boot-deploy-functions.sh` (`create_depthcharge_kernel_image`,
`flash_updated_depthcharge_kernel`, `is_in_chroot`, `check_image_size`). Verified on a loop device:
the resulting geometry is identical (`p1 8192+262144`, `p2 270336+1048576`, `p3 1318912+rest-33`,
PMBR present, kernel/efi/data types, `pmOS_*` labels, `-S 1 -T 5 -P 10`).

- The **root partition size is `dev_size - root_start - 33`**, not `- 2048`: those 33 sectors are
  the secondary GPT (32) plus its header, and pmbootstrap sizes the partition so the backup table
  survives. `partprobe` runs after the `cgpt add`s, as in `install_system_image()`.
- **`mkfs.ext2 -F -q -L pmOS_boot` and `mkfs.ext4 -F -q -L pmOS_root`**, the lines
  `format_partition_with_filesystem()` builds for this device (its schema default for
  `boot_filesystem` is ext2, so `BOOT_FS=ext2` is compliance, not a quirk).
- **`/etc/fstab` options are pmbootstrap's**: `defaults` for the root and `nodev,nosuid,noexec` for
  `/boot` — which is also how the running Nura mounts its `/boot`. Do not "improve" them without a
  reason; the `pmos_rootfsopts`-equivalent a pmOS user would see comes from that column.
- **`disk_release` refuses when a partition of the target is mounted**, like `mount_disk()`, rather
  than unmounting it silently. Active swap is turned off (pmbootstrap does not check it, but `mkfs`
  on a live swap partition fails) and no `wipefs` is done: parted writes both GPT tables and
  `mkfs -F` overwrites signatures anyway.
- **`mountpoint -q <device>` does not test whether a device is mounted** — it answers whether that
  *path* is a mount point, which a device node never is. It answered "no" for a mounted partition, so
  the old release step never unmounted anything and the new refusal would never have fired. Test with
  `findmnt -rn -S <device>` (or `/proc/mounts`), never with `mountpoint`, when the argument is a
  device; `mountpoint -q <directory>` (as in `disk_layout_umount`) is fine.
- **Partitions are resolved by number, never by their position in `lsblk`.** `lsblk` lists a disk's
  partitions in the order the kernel handed out their minors, and the `partx -d`/`-a` round that
  `disk_layout_create()` runs to make the kernel re-read the table it was just given reorders them.
  Measured over 16 attaches of a 2048 MiB loop: 3 came back as `3 1 2` or `2 1 3` with no line
  missing, so the positional code would format `p2` as the root filesystem and write the kpart into
  `p3` — a card written wrong a fifth of the time, silently. It is not `partprobe`: in an A/B of 8
  attaches each, the order drifted once with it and twice without it. `disk_layout_parts()` uses
  `PATH,PARTN` and asserts the three `pmOS_*` labels, so a wrong resolution dies instead of touching
  the wrong partition: 16 of 16 attach correctly, including the two that came back reordered.

Intentional deviations, all of them at the line that makes them: the GPT areas are zeroed before
`parted` (pmbootstrap leaves it to parted; it costs nothing and makes `cgpt create` immune to a stale
header), `mkfs` does not get `-i 8192` (that is for pmbootstrap's image builds; our images are 6 GiB
with ~90k files), the fstab pass column is `0 1`/`0 2` instead of `0 0` (systemd-fsck orders them),
the kernel command line carries `root=UUID=... rootwait rw` instead of pmOS's `pmos_root_uuid=...`
(Debian resolves its root from `root=`), and `install-emmc.sh` copies `/home` with the rest of the
running system instead of seeding it from `/etc/skel`, because the point of that script is to clone
the card that has already been tested.

### depthcharge FIT

- Build with `deviceinfo_depthcharge_board="mt8192"` (not `asurada`: the hayato DTB has no
  `google,asurada` compatible). `mkdepthcharge` prepends `kern_guid=%U` by itself, so the cmdline
  passed to `depthchargectl` must not add it again.
- Verify with `futility show <kpart>`: expect a dev-signed key block, preamble 2.2 and
  `Body verification succeeded`.
- The FIT carries one config per DTB. With `--board mt8192` no config matches by `compatible`, so
  depthcharge falls back to the **default config, which is the first DTB**: hayato must stay
  first (the alphabetical order of `deviceinfo_dtb="mediatek/mt8192-asurada*"` does that).
- The output is silent by design (`quiet loglevel=2`). For a verbose boot without touching
  `kernel-cmdline.conf`:
  `KERNEL_CMDLINE_OVERRIDE="console=tty0 ignore_loglevel loglevel=7" scripts/make-kpart.sh`
  and write the resulting kpart to the kernel partition (or `scripts/install-kpart.sh` on the
  running system). Expect the `sbs-8-000b` gauge spam on screen while verbose. Never append a
  bare `debug`: initramfs-tools then redirects its own script output to
  `/run/initramfs/initramfs.debug` (a file *inside* the initramfs) instead of the console, so the
  messages that identify a boot failure (`run-init: ...`, `Target filesystem doesn't have ...`,
  `ALERT! ...`) never reach the screen. `fbcon` is built into this kernel, which is what makes
  `console=tty0` useful here.

## Commands

All scripts live in `scripts/` and read shared config from `scripts/lib.sh`.
Large artifacts go to `$HOME/.cache/debian-aarch64` (`WORK_DIR`, `SRC_DIR`).

```sh
scripts/00-deps.sh          # install host build deps (apk or apt), re-execs via sudo
scripts/build-kernel.sh     # mainline 7.2.7 + patches + config  -> $WORK_DIR/kernel-stage
scripts/build-rootfs.sh     # debootstrap Debian forky rootfs    -> $WORK_DIR/rootfs
scripts/install-kernel.sh   # copy staged kernel into the rootfs, depmod, initramfs
scripts/build-omasnap.sh    # omasnap (the capture overlay) from its pinned tag
                            #                                 -> $WORK_DIR/omasnap-stage
scripts/install-omasnap.sh  # copy staged omasnap into a rootfs
scripts/make-kpart.sh       # signed depthcharge FIT kpart       -> $WORK_DIR/vmlinuz.kpart
scripts/write-sd.sh [dev]   # partition+populate a microSD/USB (default /dev/mmcblk1)
scripts/make-image.sh       # distributable disk image from the rootfs (no card needed)
scripts/make-release.sh     # every release asset + SHA256SUMS -> $WORK_DIR/release-<device>
scripts/install-emmc.sh     # install the running system onto /dev/mmcblk0 (CONFIRM=yes)
scripts/install-kpart.sh    # rewrite the kernel partition this system booted from
scripts/backup-system.sh    # kernel partition + GPT + /boot + rootfs tars into a directory
scripts/restore-system.sh   # put such a backup back onto a disk (root only, from the live SD)
scripts/wifi.sh export      # saved NetworkManager Wi-Fi profiles -> $WIFI_DIR
scripts/wifi.sh import      # $WIFI_DIR -> a rootfs (drops interface-name=)
scripts/check-system.sh     # (on the booted image) hardware + configuration report
scripts/verify-rootfs.sh    # (on the build host) is the built rootfs complete?
                            #   runs before make-image.sh / write-sd.sh and
                            #   refuses a tree that does not verify (VERIFY=no)

scripts/build.sh            # full pipeline (kernel + omasnap + rootfs + kernel + omasnap + kpart)
```

`scripts/build-kernel.sh` chooses its own `make -j` count rather than using bare `nproc`: this
machine has **8 cores and 4 GiB of RAM**, so the default is capped by what the kernel believes it
can hand out (`MemAvailable` minus a 768 MiB reserve for the desktop, divided by 192 MiB per clang
job, floor 2, ceiling `nproc`). A quiet machine gets all 8 cores; the same build next to a loaded
desktop gets 3 or 4 instead of swapping until the OOM killer takes a compiler and the build with
it. `JOBS=<n>` overrides the choice, and the `Building kernel <release> (N jobs)` line records it.

`scripts/build-omasnap.sh` does the same for the Qt build it is (8 cores, 4 GiB, one clang-grade
translation unit at a time) with a 700 MiB-per-job peak and a 1 GiB reserve, stages a tree under
`$WORK_DIR/omasnap-stage` (from the tag in `uis/omarchy/omasnap.version`), and
`scripts/install-omasnap.sh` copies it into a rootfs the way `install-kernel.sh` does for the
kernel. It is a separate step because omasnap is not packaged in Debian and the desktop's capture
commands `exec` it (see *Userspace / UI*).

`scripts/lib-cgpt.sh` holds the one copy of the ChromeOS GPT layout, used by `write-sd.sh`,
`install-emmc.sh`, `install-kpart.sh`, `make-image.sh` and `make-release.sh`; `BOOT_SIZE_MIB` (512)
and `BOOT_FS` (ext2) override its boot partition.

`scripts/make-image.sh` reuses that layout on a loop device, so an image is built exactly like a
card is written, with one difference: its size is an argument (`IMAGE_SIZE_MIB`, default 6144)
instead of the device's, and the copy it publishes is sanitized. The size is not cosmetic: p1 and
p2 come off the top, so p3 is `IMAGE_SIZE_MIB - 640 MiB`, and the Omarchy rootfs is ~4.6 GiB — at
the old 4096 default the copy died with a bare `rsync: write failed ... No space left on device`
twenty minutes in, which is why the script now measures the rootfs and refuses an image that cannot
hold it (with the `IMAGE_SIZE_MIB=` value that would) before it touches anything. `scripts/lib-dist.sh`
is the only place that decides what a published artifact may contain, and `dist_assert_clean` refuses the
artifact while anything is left; the release rule is:

- **Never publish an artifact straight out of `$ROOTFS`.** The build rootfs carries the
  maintainer's Wi-Fi profiles (PSKs in clear, imported from `$WIFI_DIR`), the SSH host keys and
  the machine id. `make-image.sh` and `make-release.sh` sanitize a copy and assert it clean;
  anything that publishes a rootfs has to go through `lib-dist.sh` too.
- The released image therefore comes up with no known Wi-Fi network, `ssh` host keys are generated
  on first boot (`sshd-keygen.service`) and `systemd` gets a fresh `machine-id`.
- A release is: `scripts/make-release.sh`, notes in `docs/releases/<version>.md` (committed, and
  reused as the annotated tag message and the GitHub release body), and the assets attached to the
  tag. `docs/releases/v0.1.0.md` is the first one and shows the shape.

`scripts/backup-system.sh` is the counterpart of `install-emmc.sh`: it writes the kernel partition
the system booted from (resolved from `kern_guid`, like `install-kpart.sh`), the GPT, `/boot` and
the root filesystem into a directory, the filesystems as gzip tars with owners, ACLs and xattrs
preserved, plus a `README.md` with the restore steps and a `SHA256SUMS`. The destination is
normally a removable disk with **exFAT**, the one filesystem both macOS and Linux read; exFAT
cannot hold a Linux root filesystem by itself, which is why the trees travel as tars. Caches,
build directories and the agent's session data are excluded by pattern (`EXCLUDES`), and nothing
in the backup needs them: they are downloaded or rebuilt again.

`scripts/restore-system.sh <backup-directory> [disk]` is its other half, and the one script that
insists on being run as root: it does not re-exec through sudo, because silently escalating to
rewrite a disk is the wrong default. It refuses to run from the disk it would overwrite (that is
the "live SD" requirement), refuses a disk of a different size than the backup came from (the raw
GPT dumps are exact byte copies, and the same eMMC is the case that matters), checks SHA256SUMS
before writing anything, and takes the filesystem UUIDs from the archive's own `/etc/fstab`, so the
restored system boots with the fstab and kernel command line it had. `CONFIRM=yes` is required;
`VERIFY=no` skips the checksums and `DEEP=yes` adds a full `tar -d` comparison afterwards.

`build-rootfs.sh` installs `$WIFI_DIR` into the image when that directory exists, so the machine
comes up already knowing the Wi-Fi networks (see `scripts/wifi.sh`).

Its rootfs inputs are environment variables: `TARGET_HOSTNAME`, `USERNAME`, `USERPASS`,
`LOCALE` (default `en_US.UTF-8`) and `TIMEZONE` (default `America/Mexico_City`, e.g.
`TIMEZONE=UTC`). The script re-execs itself through `sudo`, which does not preserve
the environment, so it forwards every resolved input explicitly — anything not forwarded is
silently replaced by its default. A locale that is not an entry of `/etc/locale.gen`, or a
timezone that is not under `/usr/share/zoneinfo`, is reported and replaced by the default.

**Every script that re-execs itself through `sudo` forwards the resolved build root**
(`BUILD_ROOT`, `WORK_DIR`, `SRC_DIR`) and its own inputs (`ROOTFS`, `KERNEL_STAGE`, `BOOT_SIZE_MIB`,
`CONFIRM`, …), not just `build-rootfs.sh`: without that, `BUILD_ROOT=/mnt/emmc/deboma-build` would
build half of the system at the default `~/.cache/debian-aarch64` and half somewhere else, and
`CONFIRM`-style guards could never pass. Moving the build root to another disk is therefore
`BUILD_ROOT=<path> scripts/...` — **do not** point the default path at the disk with a symlink:
forky's `rsync` 3.5.1 refuses to follow a symlink owned by another user when it runs as root
(Debian's `syscall_explain_untrusted_symlink_refusal.patch`, which only explains the bare
`Too many levels of symbolic links` it used to print), so `make-image.sh` and `make-release.sh` die
on their exclude file — and on the source or destination — if a symlinked build root is owned by the
invoking user instead of root.

`write-sd.sh` and `install-emmc.sh` are destructive to block devices and refuse to touch the
internal eMMC from `write-sd.sh` or the running root from either. Both build the same three
partitions (see `scripts/lib-cgpt.sh`) and both write a signed kpart into p1;
`install-emmc.sh` copies the **running** system (rsync) instead of `$ROOTFS`, which is why it
needs the card to be a system worth cloning. That copy excludes the *contents* of `/proc`,
`/sys`, `/dev`, `/run`, `/mnt`, `/media`, `/tmp`, `/var/cache` and `/var/log/journal` — but
`rsync` also drops the excluded directories themselves, and a root filesystem needs them: they
are mount points, and the initramfs's `run-init` moves its own `devtmpfs` `/dev` (plus `/proc`
and `/sys`) into them before handing over to systemd. A copy without them boots the kernel,
mounts the root filesystem read-write and then stops at `run-init: opening console: No such file
or directory` / `Target filesystem doesn't have requested /sbin/init` / `No init found. Try
passing init= bootarg.`; with `quiet` on the command line that is a black screen, and since the
kpart and its payload are byte-identical to the card's it reads as a firmware or kernel problem.
The script now recreates `dev:755 proc:555 sys:555 run:755 mnt:755 media:755` after the copy and
refuses to write p1 unless `/dev` exists and `/sbin/init` resolves.

`install-kpart.sh` is the third one: it does not partition anything, it only rewrites the kernel
partition the running system was booted from (resolved from `kern_guid` in `/proc/cmdline`), so
that a kernel update does not leave p1 behind. It backs up what it replaces to
`$WORK_DIR/kpart-backup-<timestamp>.img` and requires `CONFIRM=yes`.

`check-system.sh` is their counterpart: it runs **on the booted image**, not on the build host, so
it sources nothing and changes nothing, and the image also ships it as
`/usr/local/sbin/check-system.sh` so no checkout is needed to run it. With a checkout it also
verifies that every package declared in `packages/*.list`, `devices/*/packages.list` and
the **running UI's** `uis/<ui>/packages.list` is installed (`check-system.sh ~/Dev/<repo>`); the
UI comes from `/etc/debian-aarch64-revision`, so the other desktop's list is never checked against
this system. Run it as the desktop user;
from a root shell it re-executes
itself as that user, and the privileged reads go through `sudo -n`. Every check maps to a bug this
port has already hit — keyd swallowing `KEY_SLEEP`, greetd's `vt`/user, the UCM boot sequence, ALSA's
missing `default` PCM, the backlight udev rule, the font fallback, `interface-name=` in the Wi-Fi
profiles, the clock, the `fstab` UUID, the kernel partition holding a signed FIT, the screensaver's
`ttfx` and its branding file, the lock screen's PAM file (and the running shell's `passwordPam`),
`omasnap`, the shell-environment helpers, `xkbcli`, the generated menu extension and both ends of the
`Update` row audit (`Channel` off PATH, `Time` on it), and `~/.bashrc` sourcing Omarchy's rc — so a FAIL
there is a regression, not a hypothetical. It also has to be *right* about the state it asserts: the
`polkitd is active` check was a FAIL on an idle desktop, because `polkit.service` is a static unit
that D-Bus starts on demand and lets exit again, so what it now requires is that the daemon is
activatable. It
exits non-zero when something FAILs.

`verify-rootfs.sh` is the other half of that pair, on the *build host*: it takes `$ROOTFS` (or an
argument) and asserts that the tree a card would be written from is **complete** before anything
touches a disk — the mount points `run-init` needs, the overlay files with the modes `uis/<ui>/files`
ships, the commands `setup.sh` puts on PATH (`/usr/bin/omarchy-*` links pointing into
`$OMARCHY_PATH`), the generated menu extension, the staged kernel and omasnap, every declared
package against the rootfs's own `dpkg` status, and the revision (a WARN when the tree was not built
from `HEAD`). It reads the lists from the repository copy *the image ships*, not from the checkout,
needs no root and changes nothing. `make-image.sh` and `write-sd.sh` run it first and refuse a tree
that does not verify (`VERIFY=no` skips it), because "the rootfs is one commit or one `apt install`
behind" is this port's most repeated mistake and the one that costs a flash to discover. What it
cannot check is the reason `check-system.sh` exists: the firmware, the drivers and the boot chain.

### Boot from microSD

1. `crossystem dev_boot_usb=1 dev_boot_signed_only=0` (from ChromeOS developer mode; already set
   on this machine).
2. `scripts/write-sd.sh /dev/mmcblk1`
3. Insert the card, power on and pick **external disk** in the firmware menu.

### The firmware menu (this machine)

In developer mode the stock firmware on this Chromebook does not wait for the Ctrl+D / Ctrl+U
screens the older documentation describes: it presents a **menu** on its own. Its entries were
verified on hardware: **internal disk = the eMMC, external disk = the microSD**. That is the
mechanism to boot the eMMC after `install-emmc.sh`; the microSD stays the rescue system (the card
is untouched by an eMMC install, so it can always be selected again).

Default credentials of the built image: user `brunux` / password `debian`, passwordless sudo.

