# Status — continuing the v0.2.0 build from the internal disk

Snapshot of where the build stands, written 2026-10-18 from the microSD-booted system, so the
work can be finished **from the internal (eMMC) installation** and a new card written from there.
It is a handover note, not documentation: delete it once v0.2.0 is published.

## Where the build stands

| piece | state |
|---|---|
| `HEAD` | `5bf3aa0` when this was written; the tree is now at `389d321` (see the update below), working tree clean |
| Kernel | built and staged: `7.2.7-mt81`, mainline 7.2.7 + patches, `make LLVM=1 -j3` (95 min) |
| Rootfs | built: Debian `forky/arm64` + the Omarchy v4 desktop, **4607 MiB**, its `/etc/debian-aarch64-revision` says `commit fd3de8c` |
| Image | **complete**: `google-asurada.img`, 6144 MiB, kpart already written into `p1` |
| Release assets | **missing**: `.img.xz`, `-rootfs.tar.zst`, the standalone `.vmlinuz.kpart` and `SHA256SUMS` — `make-release.sh` was canceled at `2/4 Compressing the image` |
| On-device report | **not taken yet** for this rebuild. The release notes still cite the *first* boot of the earlier card (`reports/2026-10-18-omarchy-desktop.txt`, `commit 85d32fc`, 49 OK / 2 WARN / 1 FAIL) |

The image is self-consistent and bootable as it is: the kpart inside `p1` embeds that image's own
`root=UUID`. The `.vmlinuz.kpart` lying in `work/` is from the *earlier* attempt and belongs to a
different root UUID — do not publish it.

## Update — 2026-10-19, from the internal install

The eMMC install was audited against the Omarchy manual and what it found is fixed on `main`
(`389d321`, "Audit the installed desktop and fix the four silent failures it found"). What that
means for the build below:

- **The image already in `/deboma-build/work` is behind the tree.** Write the card with
  `scripts/write-sd.sh` (it takes the current rootfs), or re-run `build-rootfs.sh` +
  `install-kernel.sh` before `make-release.sh`, as in § *Then: finish the release*.
- `scripts/build.sh` now also runs **`build-omasnap.sh` + `install-omasnap.sh`** (the capture
  overlay, built from the tag in `uis/omarchy/omasnap.version`). That needs the Qt6 build deps
  `scripts/00-deps.sh` installs and adds ~6 minutes before the rootfs step.
- `check-system.sh` gained one check per finding (the screensaver renderer and its seeded art, the
  lock screen's PAM file and the running shell's `passwordPam`, `omasnap`, the shell-environment
  helpers, `~/.bashrc` sourcing Omarchy's rc), so the rebuild's report has **eight more OKs** than
  the counts quoted elsewhere in this file.
- `reports/2026-10-19-emmc-desktop.txt` is the audit's report — **68 OK, 2 WARN, 0 FAIL** — taken on
  the eMMC install *after* the fixes were applied by hand, so it documents the hardware and the new
  checks, not the image. The clean-rebuild report of § *Then: close F7* is still what the release
  needs. `docs/releases/v0.2.0.md` now carries the audit; if these fixes should ship as `v0.2.1`
  instead, that paragraph moves with them.
- The touchpad override below is unchanged: it is still a personal file on this machine and still
  deliberately not in the repository.

## Where it lives

The build root is on the eMMC, which is why the internal install is the right place to continue.

| | from the microSD (now) | from the internal disk |
|---|---|---|
| build root | `/mnt/emmc/deboma-build` | `/deboma-build` |
| rootfs | `…/work/rootfs-google-asurada` | `/deboma-build/work/rootfs-google-asurada` |
| kernel stage | `…/work/kernel-stage-mediatek-mt81` | `/deboma-build/work/kernel-stage-mediatek-mt81` |
| image | `…/work/release-google-asurada/google-asurada.img` | `/deboma-build/work/release-google-asurada/…` |
| build logs | `~/.cache/deboma-buildlogs/*.log` (microSD only) | — |
| checkout | `~/Dev/Deboma` | `~/Dev/Deboma` (staged: `5bf3aa0`) |
| one-shot runner | `~/.cache/run-deboma-build.sh` | `~/.cache/run-deboma-build.sh` (staged, `BUILD_ROOT=/deboma-build`) |

**Every script needs `BUILD_ROOT=/deboma-build` when run from the internal install**, because the
build root is not at the default `$HOME/.cache/debian-aarch64`. The scripts forward that variable
through their own `sudo` re-exec (fix in `5bf3aa0`), so it works as an environment variable — do
**not** point the default path at the eMMC with a symlink: forky's `rsync` 3.5.1 runs as root and
refuses to follow a symlink owned by another user, which is what killed the first two release runs.

The old `~/.cache/omarchybook` (7.2 GB) and `~/.cache/debian-aarch64` (13 GB) trees on the eMMC are
stale build products from earlier work; deleting them frees ~20 GB if space gets tight.

## Three things that broke, and are fixed in `5bf3aa0` / `fd3de8c`

- **The image no longer fits the rootfs.** 4607 MiB of rootfs against p3 = `IMAGE_SIZE_MIB − 640 MiB`:
  at the old `4096` the copy died with a bare `rsync: write failed … No space left on device`.
  `IMAGE_SIZE_MIB` now defaults to **6144**, and `make-image.sh` measures the rootfs and refuses an
  image that cannot hold it, naming the value that would work.
- **The build root travelled through a symlink**, which `rsync` (as root) refuses. All scripts that
  re-exec through `sudo` now forward `BUILD_ROOT`/`WORK_DIR`/`SRC_DIR` and their own inputs, so the
  build root is chosen with `BUILD_ROOT=<path>`, with no symlink.
- **`make -j`** is sized from `MemAvailable` (`scripts/build-kernel.sh`), so a quiet machine gets all
  8 cores and a loaded one does not swap itself to death.

## Continue here: write the new card

The internal install has every tool needed (`cgpt`, `futility`, `depthchargectl`, `rsync`, `xz`,
`zstd` — verified). The microSD **cannot** write itself: `write-sd.sh` refuses the running root
device, which is exactly the card it would be writing.

Two ways, and they are independent:

1. **Card straight from the built rootfs** (no release needed, ~few minutes):
   ```sh
   BUILD_ROOT=/deboma-build scripts/write-sd.sh /dev/mmcblk1
   ```
   It partitions the card (p1 kernel 128 MiB / p2 `/boot` ext2 512 MiB / p3 root), copies the rootfs,
   writes `/etc/fstab`, builds and signs a kpart for **that** card's `root=UUID`, and refuses
   `mmcblk0` (the internal disk) and the running root. The card is 14.8 GB, so p3 takes the whole
   card; the 6 GiB image below would leave the rest unused.
2. **Card from the release image**, which needs the rest of the release first (§ next):
   ```sh
   xz -dc /deboma-build/work/release-google-asurada/google-asurada.img.xz |
       sudo dd of=/dev/mmcblk1 bs=4M conv=fsync
   ```

Boot it from the firmware's developer-mode menu: **internal disk = eMMC, external disk = microSD**.

## Then: finish the release

```sh
cd ~/Dev/Deboma
BUILD_ROOT=/deboma-build scripts/make-release.sh      # rebuilds the image, xz -T0 -6, tar zstd -T0 -12
```
- ~25 min, and it regenerates the image (fresh filesystem UUIDs), so the `.img`, its `.xz` and the
  published `.vmlinuz.kpart` all end up matching each other.
- Needs ~9 GB more than the tree already uses; the eMMC has ~19 GB free.
- Optional: re-run `scripts/build-rootfs.sh` (7 min) before it, so the repo snapshot *inside* the
  image carries `5bf3aa0` instead of `fd3de8c` and `/etc/debian-aarch64-revision` matches the tag.
  It rebuilds the rootfs from scratch, so `install-kernel.sh` has to run again afterwards.
- Full pipeline in one go (only if the kernel is to be rebuilt too, ~1.5 h): `~/.cache/run-deboma-build.sh`.

## Then: close F7

1. Boot the new card and run `check-system.sh` as the desktop user — with a checkout it also checks
   every declared package: `check-system.sh ~/Dev/Deboma`. Expect **0 FAIL**.
2. Save it as `reports/<date>-omarchy-rebuild.txt`, mask the Wi-Fi MAC down to its OUI
   (`74:4C:A1:XX:XX:XX`, the one edit `reports/README.md` allows), add a section describing it to
   `reports/README.md`, and update `docs/releases/v0.2.0.md` with its counts (the "Validation"
   section currently describes the *patched* card, not this rebuild).
3. Flip the release pointer (`- **Release:** [`v0.1.1`] …`) to `v0.2.0` in `README.md`.
4. Tag: annotated tag `v0.2.0` whose message is `docs/releases/v0.2.0.md`, then publish the four
   assets + `SHA256SUMS` from `/deboma-build/work/release-google-asurada/`.

## Not part of this build (do not mistake for a regression)

- **Touchpad scrolling is inverted** on the microSD card only: `~/.config/hypr/input.lua` sets
  `natural_scroll = true`. It is a personal override and is deliberately **not** in the repository,
  so a freshly written card keeps Omarchy's default.
- `omarchy-provision-first-run` logs one `command not found` per login (its autostart entry is
  excluded by design), `Owe.LockFeed` is deferred with the `omarchy-pkgs` set, and stock Quickshell
  0.3.2 logs `Unrecognized pragma "OmarchyLoadPatch"`. All documented in the release notes.
