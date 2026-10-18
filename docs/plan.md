# Plan: Debian for Google Hayato (MT8192 / `google-asurada`)

> Goal: build a **Debian arm64** OS that boots on this machine by reusing Nura's hardware support
> (kernel, device tree, patches, modules and boot flow). Phase 1: boot from **microSD** (Ctrl+U).
> Phase 2: install to **eMMC** with our own installer equivalent to
> `pmbootstrap install --disk=/dev/mmcblk0`.

---

## 1. Recon (done)

See [`recon.md`](recon.md) for the full capture. Summary:

| Item | Value |
|---|---|
| Model | Google **Hayato rev1** (ASUS Chromebook Detachable CM3 / Flip CM3 CM3200) |
| SoC | MediaTek **MT8192 "Asurada"** — 4×A76 + 4×A55, Mali-G57 MC5 (Panfrost) |
| DT compatible | `google,hayato-rev1` / `google,hayato` / `mediatek,mt8192` |
| RAM | 4 GB (3.7 GiB) |
| Storage | eMMC 58.2 GB (`mmcblk0`), microSD (`mmcblk1`) |
| WiFi/BT | Realtek **RTL8822CE** over PCIe (`rtw88_8822ce` + `rtl_bt`) |
| Input | `cros-ec-keyb` + Elan touchscreen `04F3:2E70` (i2c-hid) |
| Firmware | stock coreboot/depthcharge, **developer mode**, vboot2 |
| Kernel | mainline **7.2.7** (`linux-postmarketos-mediatek-mt81`) |

## 2. Nura install flow (what we reproduce)

Documented on the `Category:ChromeOS` wiki page (read via Wayback):

1. Developer mode enabled (already done).
2. `crossystem dev_boot_usb=1 dev_boot_signed_only=0` → boot from SD/USB with **Ctrl+U**.
3. Write the prebuilt Nura image (`images.nura.eco/bpo/edge/google-asurada/sway/<date>/*.img.xz`) to SD.
4. Boot from SD, `apk add pmbootstrap`, `pmbootstrap init`, then
   `pmbootstrap install --disk=/dev/mmcblk0`.

Nura builds the kpart with `depthcharge-tools` + `boot-deploy` and signs it with the vboot devkeys.

## 3. pmOS → Debian equivalence

| Nura (Alpine/apk) | Debian (forky) |
|---|---|
| `device-google-asurada` (APKBUILD + deviceinfo) | our `device/google-asurada/` package |
| `linux-postmarketos-mediatek-mt81` | kernel `.deb` from the same source + config |
| `postmarketos-mkinitfs` + `postmarketos-initramfs` | `initramfs-tools` |
| `boot-deploy` | our kernel hook/script |
| `depthcharge-tools`, `cgpt`, `futility` | `depthcharge-tools`, `vboot-utils` |
| `generate-kernel-cmdline` | `/etc/kernel/cmdline` + hook |
| `pmbootstrap install --disk` | our installer (`cgpt` + `dd` + kpart signing) |
| `postmarketos-cros-common` (keyd keymap) | manual equivalent (keyd / keyboard map) |

## 4. Phases

**F0 — Safety and reference**
- ChromeOS recovery USB stick (second computer + USB-C available).
- Back up working artifacts: `/boot/config`, `/boot/vmlinuz`,
  `/boot/dtbs/mediatek/mt8192-asurada-hayato-r1.dtb`, `/boot/vmlinuz.kpart`,
  `/usr/share/deviceinfo/*`, initramfs module list, firmware list.

**F1 — Prepare the microSD**
- Repurpose the SD (currently swap); real swap remains via zram.

**F2 — Debian rootfs**
- `mmdebstrap --architectures=arm64` from `deb.debian.org` (suite `forky`),
  `main` + `non-free-firmware`; `firmware-realtek`, `firmware-mediatek`, NetworkManager, user, sudo.

**F3 — Kernel (port from Nura)**
- Source: `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.xz` + 7 patches
  (`kernels/mediatek-mt81/patches/`, order in `series`) +
  `kernels/mediatek-mt81/config.aarch64`.
- Build with `make LLVM=1` (clang/lld); the release string (`7.2.7-mt81`) is derived from
  `CONFIG_LOCALVERSION`.

**F4 — Initramfs**
- `initramfs-tools` with modules: `panfrost`, `rtw88_8822ce`, `rtl_bt`, `cros-ec-keyb`,
  `hid-multitouch`, `i2c-hid-of`, `elan-i2c`/`elants-i2c`, `anx7625`, `panel-edp`.
- Root via `root=UUID=<root> rootwait rw`. No FDE in v1.

**F5 — depthcharge boot + SD image**
- Partition with `cgpt` (KERN 128 MB + boot + root); build the signed FIT with
  `depthchargectl build --board mt8192`; compose `.img` and compress to `.img.xz`.

**F6 — Boot from SD and iterate**
- `crossystem dev_boot_usb=1 dev_boot_signed_only=0`, insert SD, **Ctrl+U**.
- Validation matrix vs Nura: display/GPU, WiFi, BT, audio, touchscreen, keyboard, USB, charging, suspend.

**F7 — Installer to eMMC** (same as Nura, without pmbootstrap)
- From the SD-booted system: `cgpt` creates the GPT on `mmcblk0`, writes the signed kpart to p1,
  `/boot` to p2, rootfs to p3, sets `root=UUID` and the KERN partition priority.

**F8 — Reproducibility**
- Versioned `scripts/`: `build-kernel.sh`, `build-rootfs.sh`, `build-image.sh`, `write-sd.sh`,
  `install-emmc.sh`.

## 5. Risks and mitigations

- **Do not flash the SPI**: write-protect disabled → only write GPT partitions.
- **vboot signing**: use exact devkeys; verify the kpart with `futility show`.
- **4 GB RAM**: limit compile jobs; the kernel already builds on this machine.
- **In-place install is impossible**: always build/boot from SD before touching eMMC.

## 6. Open data to confirm

1. Filesystem for `/boot` (Nura uses ext2; Debian defaults to ext4) and for root (ext4).
2. Whether Debian forky's `depthcharge-tools` signs with the same devkeys and produces a compatible kpart.
