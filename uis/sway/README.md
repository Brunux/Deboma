# uis/sway — Sway desktop

A UI is a package list plus a file tree:

```
uis/sway/
  packages.list          packages to install (Debian names)
  files/                 tree overlaid onto the rootfs
    etc/...              copied to /            (owned by root)
    home/...             merged into /home/$USERNAME (owned by the user)
```

`scripts/build-rootfs.sh` stages both into the chroot and
`scripts/rootfs-setup.sh` installs them, rewriting `/home/brunux` to the
configured `USERNAME` inside the text files.

This desktop was ported from the maintainer's Nura (postmarketOS) session, so it
keeps the solarized theme, the `Alt` modifier + Search-key launcher, the bemenu
launcher, waybar and the Alacritty terminal.

## Layout

| Path | What it is |
|---|---|
| `etc/sway/config` | System half of the session (replaces Debian's default file). Includes `config.d/*` at the end. |
| `etc/sway/config.d/*` | Drop-ins: logo key, bar, launcher, brightness, waybar, lock, volume, sleep, gestures, screenshots, theme, touchpad. |
| `home/.config/sway/config` | Personal overlay: re-includes `/etc/sway/config`, then adds the keyboard repeat rate and the Search-key launcher binding. |
| `home/.config/waybar/{config.jsonc,style.css}` | Solarized waybar theme. |
| `home/.config/workstyle/config.toml` | Icon map for workstyle (see below). |
| `home/Pictures/Wallpapers/mountains.jpg` | Wallpaper referenced by `etc/sway/config`. |
| `etc/keyd/default.conf` | Chromebook keymap for keyd: F-keys and VT switching (see below). |
| `etc/udev/rules.d/90-brightnessctl.rules` | Gives the `video` group write access to the backlight, so `brightnessctl` works for the unprivileged session (see below). |

## Deviations from the Nura original

* **Fonts.** The theme asks for `AdwaitaMono Nerd Font` / `JetBrainsMono Nerd Font`, which Debian
  does not ship (its `fonts-adwaita` has no Mono variant), so `style.css` and the Pango spans in
  `config.jsonc` use `JetBrains Mono`. The icons come from fontconfig fallback and need two
  packages people usually miss:

  | Glyphs | Package |
  |---|---|
  | Font Awesome, `U+F000`-`U+F2FF` | `fonts-font-awesome-legacy` |
  | Material Design Icons, plane 15 | `fonts-materialdesignicons-legacy` |
  | Octicons, Codicons, Devicons, Powerline | `fonts-nerd-symbols` |

  `fonts-nerd-symbols` alone is not enough: Debian stripped Font Awesome and Material Design
  Icons from it for DFSG reasons, so every waybar icon would render as a tofu box with the hex
  codepoint inside. Nothing else in the configuration changes.
* **workstyle is not installed.** It is not packaged in Debian and the Nura
  build was a cargo binary linked against musl (it cannot run against glibc).
  It renames workspaces to icons; the waybar theme shows workspace numbers, so
  nothing is missing visually. `home/.config/workstyle/config.toml` is kept so
  that enabling it later needs no extra configuration:

  ```sh
  cargo install workstyle
  echo 'exec_always --no-startup-id workstyle' >/etc/sway/config.d/03-workstyle.conf
  ```

* **Bluetooth needs `bluez`, not just the PipeWire plugin.** `libspa-0.2-bluetooth` only gives
  PipeWire a D-Bus client for `org.bluez`; the daemon that actually powers the controller up
  (and provides `bluetoothctl`) is in `bluez`, which is now listed next to it in
  `packages.list` (see `AGENTS.md`).

* **ALSA-only programs need `pipewire-alsa`.** Debian's alsa-lib configuration has no usable
  `default` PCM by itself, so `aplay`/`arecord` without an explicit `-D`, emulators and some
  games fail with *audio open error: No such file or directory* even though PipeWire (and
  therefore PulseAudio clients) works. `pipewire-alsa` is listed in `packages.list`.

* `etc/sway/config.d/01-status-bar.conf` disables swaybar (waybar is used
  instead); the block is kept commented out for reference.

## Brightness, volume and lock keys

The top row is handled by sway: `XF86MonBrightness{Down,Up}` run `brightnessctl`
(`etc/sway/config.d/20-brightness.conf`), `XF86Audio{Raise,Lower}Volume` /
`XF86AudioMute` run `pactl` (`etc/sway/config.d/21-volume.conf`), and the Lock key locks
the screen (`etc/sway/config.d/21-lock-screen.conf`). Some of the pieces are
easy to miss:

* **Backlight permissions.** Debian's `brightnessctl` ships no udev rule and nothing
  else in the system touches `/sys/class/backlight`, so the brightness file stays
  root-only (0644) and `brightnessctl set` fails with *Permission denied* for the
  session user. `etc/udev/rules.d/90-brightnessctl.rules` puts it in the `video` group
  and makes it group-writable (this is the rule upstream brightnessctl installs).
* **A real audio sink.** `pactl` acts on `@DEFAULT_SINK@`. If the MT8192 card's UCM boot
  sequence has not run, the card exposes no sink and WirePlumber falls back to a *Dummy
  Output*, so the volume keys "work" but nothing is audible. The `alsa-utils` package in
  `packages/base.list` fixes this (see `AGENTS.md`).
* **The Lock key sleeps by itself.** The right-most key of the top row emits `KEY_SLEEP`, the
  one key systemd-logind suspends on without consulting polkit or even the session, so
  `etc/keyd/default.conf` deliberately leaves it alone (Nura's keymap maps `sleep = coffee`
  instead, which swallows the key: logind stops seeing `KEY_SLEEP` and nothing consumes
  `KEY_COFFEE`, so the key is dead there — and that remap is what killed suspend on this image
  as soon as keyd was configured). `21-lock-screen.conf` binds `XF86Sleep`, the keysym that
  keycode produces, to `swaylock`: the key locks the screen and the machine sleeps ~0.3 s
  later, with no shortcut and no polkit in the path.
* **Locking and sleeping from the session** is what the two Escape shortcuts in `22-sleep.conf`
  are for — `Alt+Shift+Escape` locks first, `Alt+Ctrl+Escape` only sleeps. Being plain
  commands, they call `loginctl suspend`, a D-Bus method that needs polkitd to allow the active
  session (Debian's stock `org.freedesktop.login1.suspend` policy has `allow_active=yes`) and
  that otherwise fails with *Access denied* — silently. Both go through
  `~/.config/bin/sway-suspend`, which tries `loginctl suspend`, then `sudo -n loginctl suspend`,
  then `echo mem > /sys/power/state`, appends every attempt to `~/.cache/sway-suspend.log` and
  shows a swaynag pointing at that file when all three fail.
* **tuigreet is the original 0.9.1**, not the fork Nura runs, so it has no `--config`: the
  greeter's personalisation lives as flags in `/etc/greetd/config.toml` (theme, greeting,
  time format, padding, F-key menus). The `matrix` background, the custom title and the
  widget positions have no equivalent and are dropped.

## Virtual terminals and the missing F-keys

The hayato device tree (`mt8192-asurada-hayato-r1.dts`) maps the top row to
*action* keys (`KEY_BACK`, `KEY_FORWARD`, `KEY_REFRESH`, `KEY_FULL_SCREEN`,
`KEY_SCALE`, `KEY_BRIGHTNESS{DOWN,UP}`, `KEY_MUTE`, `KEY_VOLUME{DOWN,UP}`), so
this keyboard never emits `F1`-`F10`. That breaks virtual-terminal switching,
which needs a real F-key keycode:

* the kernel maps `Ctrl+Alt+F<n>` to `Console_<n>` (its `defkeymap` has
  `control alt keycode 59 = Console_1`), and
* sway reacts to the `XF86Switch_VT_<n>` keysym, which the default xkb keymap
  produces from that same keycode (`srvr_ctrl(fkey2vt)` puts `XF86Switch_VT_1`
  on `<FK01>` at the `CTRL+ALT` level).

`keyd` supplies the missing F-keys. `etc/keyd/default.conf` is the maintainer's
Nura keymap, moved out of `/tmp` (where it was a symlink target that vanished on
reboot: keyd only reads its configuration at startup, so a config written after
boot is never picked up).

| Combination | Result |
|---|---|
| `Ctrl+Alt` + top row, left to right | `Ctrl+Alt+F1`-`F10` → virtual terminals 1-10 |
| `Search` + top row | `F1`-`F10` |
| top row alone | ChromeOS action keys (back, brightness, volume, ...) |
| `Alt+Backspace` | `Delete` |
| `Ctrl+Scale` / `Ctrl+F5` | `SysRq` |
| `AltGr` + arrows | `Home` / `End` / `PgUp` / `PgDn` |
| Lock key | *not* remapped: systemd-logind suspends on `KEY_SLEEP` |

### Which devices keyd grabs

`[ids]` lists the internal cros-ec keyboard (`k:0000:0000`; keyd matches ids as
prefixes) plus the Google USB keyboards of the original config, and it *excludes*
two devices that share the `0000:0000` id but are not keyboards:

* `cros_ec_buttons` — it carries the power button, the volume buttons and the
  lid and tablet-mode switches. keyd's heuristic counts it as a keyboard because
  it reports `KEY_VOLUMEUP/DOWN`, but keyd's virtual device does not forward
  `EV_SW`, so grabbing it would break suspend-on-lid-close and take the power
  button away from logind.
* the headset jack — same problem with the headphone/microphone insertion
  switches.

Exclusions have to come *before* the `k:0000:0000` line (keyd returns on the
first matching entry) and hold a hash of the device name, key count and abs/rel
masks. If a kernel update ever changes either device, read the ids back with
`keyd.rvaiya monitor`, or with `journalctl -u keyd`, which logs what it matched.

Notes:

* Debian's package installs the daemon as `/usr/bin/keyd.rvaiya` and enables
  `keyd.service` on install; `/etc/keyd/` ships empty, so this file is the only
  config. Reload it with `sudo keyd.rvaiya reload` after editing.
* keyd grabs the keyboard and re-emits everything through a virtual device
  (`kbd_connect()` in the kernel accepts uinput devices, so VT switching works).
  If it is not running the keyboard still works, just without the remapping.
* Emergency exit if a config misbehaves: **`backspace`+`escape`+`enter`** makes
  keyd quit and release the keyboard.
* Without keyd a console is still reachable from a terminal with `chvt 2`
  (`chvt` needs root or a controlling tty on the active VT), and you come back
  with `chvt 7`.

