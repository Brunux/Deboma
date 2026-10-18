# Recon: Google Hayato (`google-asurada`)

Captured from the install machine (running Nura edge) and from upstream sources.

## 1. Hardware

| Item | Value | Source |
|---|---|---|
| Model | Google Hayato rev1 | `/proc/device-tree/model` |
| DT compatible | `google,hayato-rev1 google,hayato mediatek,mt8192` | `/proc/device-tree/compatible` |
| CPU | 8 cores, Cortex-A76 + Cortex-A55 | `/proc/cpuinfo` |
| RAM | 3.7 GiB usable (4 GB) | `free -h` |
| GPU | Mali-G57 MC5, `panfrost` | `/sys/class/drm/card0/device/uevent` |
| WiFi | Realtek RTL8822CE (`rtw88_8822ce`), PCI `10EC:C822` | `/sys/class/net/wlan0/device/uevent` |
| Bluetooth | `hci0` (rtl_bt) | `/sys/class/bluetooth` |
| Input | `cros-ec-keyb`, Elan `04F3:2E70` i2c-hid touchscreen | `/sys/bus/platform/devices` |
| Power | cros_usbpd charger, EC battery `sbs-8-000b` | `/sys/class/power_supply` |

## 2. Storage / partitions

`lsblk`: eMMC `mmcblk0` (58.2 GB), microSD `mmcblk1` (14.8 GB), zram0 (5.6 GB).

GPT layout (pmOS labels):

| Part | Label | Size | FS | Purpose |
|---|---|---|---|---|
| `mmcblk0p1` | `pmOS_kernel` | 128 MB | — | ChromeOS kernel partition (signed FIT kpart) |
| `mmcblk0p2` | `pmOS_boot` | 512 MB | ext2 | `/boot` |
| `mmcblk0p3` | `pmOS_root` | 57.6 GB | ext4 | `/` |

- `kern_guid=55cc863a-b2ef-e64c-8418-a537fd5a58e9` = PARTUUID of `mmcblk0p1`.
- `pmos_boot_uuid=69f071fe-6bd7-4de2-b225-7072a17e1787`, `pmos_root_uuid=2b3fd268-2304-430a-82d3-4175d19efa75`.

## 3. Firmware / boot chain

- Stock Google Hayato coreboot/depthcharge in **developer mode**:
  `mainfw_type=developer`, `fwid=Google_Hayato.13885.175.0`, `vboot2`, `fw_vboot2=1`.
- Bootloader reads a **signed FIT kernel** from the GPT kernel partition selected by `kern_guid`.
- Nura builds/signs it with `depthcharge-tools` (`depthchargectl`) using vboot devkeys in
  `/usr/share/vboot/devkeys`.
- Enable external boot: `crossystem dev_boot_usb=1 dev_boot_signed_only=0`; boot with **Ctrl+U**.

## 4. Software (Nura edge)

- `/etc/os-release`: `ID=nura`, `ID_LIKE=alpine`, `VERSION_ID=edge`.
- Init: OpenRC. UI: Sway (`postmarketos-ui-sway`).
- Kernel: `7.2.7-mt81`, built with Alpine clang 23.1.1, localversion `-mt81`.
- Relevant packages: `device-google-asurada`, `linux-postmarketos-mediatek-mt81`,
  `boot-deploy`, `depthcharge-tools`, `postmarketos-mkinitfs`, `postmarketos-initramfs`,
  `postmarketos-cros-common`, `linux-firmware-{mediatek,rtw88,rtl_bt}`.

## 5. Upstream reference (pinned)

`pmaports` commit `0e458a2417d6f5ed61c7b70621d5632e30136091` (2026-10-15), paths:

- `device/community/device-google-asurada/`
- `device/community/linux-postmarketos-mediatek-mt81/`

Kernel source is **mainline** `linux-7.2.7.tar.xz` from `cdn.kernel.org`, plus patches:

| Patch | Purpose (inferred from name) |
|---|---|
| `mt8183-fix-bluetooth.patch` | Bluetooth fix (MT8183 family) |
| `mt8186-enable-dpi.patch` | Enable DPI display |
| `mt8186-ASoC-hdmi-codec-*.patch` | HDMI audio codec |
| `mt8186-SoC-mediatek-mt8186-correct-the-HDMI-widgets.patch` | HDMI widgets |
| `mt8186-drm-bridge-it6505-Add-audio-support.patch` | IT6505 bridge audio |
| `mt8186-ASoC-mediatek-mt8186-make-FE-nonatomic-and-no_pcm.patch` | Audio FE tweaks |
| `mtk-pmdomain.patch` | MediaTek power domain |

Kernel is built with `make LLVM=1` (clang/lld), `INSTALL_MOD_PATH` under `/usr`,
`INSTALL_DTBS_PATH=/boot/dtbs`.

## 6. Device package facts (`device/google-asurada/`)

- `deviceinfo_dtb="mediatek/mt8192-asurada*"`, `deviceinfo_arch="aarch64"`.
- `deviceinfo_cgpt_kpart="/boot/vmlinuz.kpart"`, start `8192`, size `262144` sectors (128 MB).
- `deviceinfo_depthcharge_board="mt8192"`, compression `lzma`,
  `deviceinfo_generate_depthcharge_image="true"`.

### depthcharge-tools notes (verified on this machine)

- `depthchargectl build --board mt8192` resolves to board `chipset-mt8192`
  (`dt-compatible = mediatek,mt8192`). It has no `image-format` in `boards.ini`, but for
  arm/arm64 the tool defaults to **FIT** (`mkdepthcharge.py`), which is what the firmware needs.
- The `asurada` board would set `image-format = fit` explicitly, but its
  `dt-compatible = google,asurada` — the Hayato DTB does **not** advertise `google,asurada`
  (it has `google,hayato-rev1`, `google,hayato`, `mediatek,mt8192`), so `mt8192` is the right
  choice (this matches the comment in upstream `deviceinfo`).
- Signing uses the vboot devkeys in `/usr/share/vboot/devkeys`
  (`kernel.keyblock`, `kernel_data_key.vbprivk`, `kernel_subkey.vbpubk`) automatically.
- The generated kpart is a ChromeOS vboot 2.2 header wrapping a FIT image
  (verified with `futility show` against the running system's `/boot/vmlinuz.kpart`).
- `modules-initfs`: `anx7625`, `panel-edp`, `hid-generic`, `hid-multitouch`, `i2c-hid-of`,
  `elan-i2c`, `elants-i2c`, `cros-ec-keyb`.
- `kernel-cmdline.conf`: `quiet`, `loglevel=2`.
