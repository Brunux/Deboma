# Status — continuing the v0.2.0 build from the internal disk

Snapshot of where the build stands, written 2026-10-18 from the microSD-booted system, so the
work can be finished **from the internal (eMMC) installation** and a new card written from there.
It is a handover note, not documentation: delete it once v0.2.0 is published.

## Where the build stands

| piece | state |
|---|---|
| `HEAD` | `4bd56ce` (the audit's second round: the `Update` menu, in both directions), working tree clean |
| Kernel | **gone with the old build root**: `build-kernel.sh` was restarted by the audit session (`7.2.7-mt81`, mainline 7.2.7 + patches, `make LLVM=1`, ~95 min) |
| Rootfs | rebuilt at `4bd56ce`: Debian `forky/arm64` + the Omarchy v4 desktop, **4550 MiB**, `omasnap` installed, verified off-device (52 OK / 2 WARN / 0 FAIL, `scripts/verify-rootfs.sh`) |
| Image | **not built** for this tree. The finished `google-asurada.img` of the previous build went with `/deboma-build` (see below) |
| Release assets | **missing**: `.img.xz`, `-rootfs.tar.zst`, the standalone `.vmlinuz.kpart` and `SHA256SUMS` — `make-release.sh` was canceled at `2/4 Compressing the image` |
| On-device report | `reports/2026-10-19-emmc-desktop.txt` — **72 OK, 2 WARN, 0 FAIL** on the eMMC install, taken after the audit's fixes were applied to it by hand |

Neither the image nor the stray `.vmlinuz.kpart` of the earlier attempt is on this machine any more:
both lived in `/deboma-build`, and every *published* artifact still has to be built (see *Then:
finish the release*). What the previous build proved — that this port boots, on this hardware, with
these fixes — stands, and `reports/` carries it.

## Update — 2026-10-19, from the internal install

The eMMC install was audited against the Omarchy manual and what it found is fixed on `main`
(`389d321`, "Audit the installed desktop and fix the four silent failures it found"). What that
means for the build below:

- **There is no image any more** (the one in `/deboma-build/work` went with the build root, § below),
  and no kernel stage either. The rootfs, on the other hand, is rebuilt and current: write the card
  with `scripts/write-sd.sh` once a kernel is staged, or run the whole of § *Then: finish the release*.
- `scripts/build.sh` now also runs **`build-omasnap.sh` + `install-omasnap.sh`** (the capture
  overlay, built from the tag in `uis/omarchy/omasnap.version`). That needs the Qt6 build deps
  `scripts/00-deps.sh` installs and adds ~6 minutes before the rootfs step.
- `check-system.sh` gained one check per finding (the screensaver renderer and its seeded art, the
  lock screen's PAM file and the running shell's `passwordPam`, `omasnap`, the shell-environment
  helpers, `xkbcli` and `~/.bashrc` sourcing Omarchy's rc), so the rebuild's report has **nine more
  OKs** than the counts quoted elsewhere in this file. A second round against the command menu added
  three more — the generated row-hiding extension is in place, the `Update > Channel` commands are off
  PATH, and `omarchy-update-time` is on it — so the count under `reports/` is twelve over the first
  report. The same run also caught a check that was
  wrong about itself rather than about the port: `polkitd is active` was a FAIL on an idle desktop,
  because `polkit.service` is static and D-Bus starts it on demand, so it now requires that the
  daemon is activatable.
- `reports/2026-10-19-emmc-desktop.txt` is the audit's report — **72 OK, 2 WARN, 0 FAIL** — taken on
  the eMMC install *after* the fixes were applied by hand, so it documents the hardware and the new
  checks, not the image. The clean-rebuild report of § *Then: close F7* is still what the release
  needs. `docs/releases/v0.2.0.md` now carries the audit; if these fixes should ship as `v0.2.1`
  instead, that paragraph moves with them.
- **`scripts/verify-rootfs.sh` is new**: the build-host counterpart of `check-system.sh`, and
  `make-image.sh` / `write-sd.sh` now run it before they touch a disk. It asserts that the tree is
  *complete* — the mount points `run-init` needs, the overlay files with the modes `uis/<ui>/files`
  ships, the `omarchy-*` PATH subset, the generated menu extension, the staged kernel and `omasnap`,
  every declared package against the rootfs's own `dpkg` status, and the built commit (a WARN when it
  is not `HEAD`). `VERIFY=no` skips it. On the rootfs rebuilt at `4bd56ce` it reports **52 OK,
  2 WARN, 0 FAIL** — the WARNs being the kernel that is not staged yet and this note's uncommitted
  changes.
- The touchpad override below is unchanged: it is still a personal file on this machine and still
  deliberately not in the repository.

## Where it lives

**`/deboma-build` is gone, and that is worth knowing.** The previous build kept its rootfs, kernel
stage and finished 6144 MiB image there — on the eMMC — and `install-emmc.sh` deleted them:
that script rsyncs the *running* system onto `/dev/mmcblk0p3` with **`--delete`**, so anything the
card did not itself carry went with the rest. Keeping the build root on a disk that will later be
installed *over* is the way to lose it.

What is in use now is the default build root, on this machine's eMMC:

| | where |
|---|---|
| build root | `~/.cache/debian-aarch64` (the default; move it with `BUILD_ROOT=<path>`) |
| rootfs | `…/work/rootfs-google-asurada` — rebuilt at `4bd56ce`, `omasnap` installed |
| kernel stage | `…/work/kernel-stage-mediatek-mt81` — being rebuilt by the audit session |
| image | `…/work/release-google-asurada/…` — not built for this tree |
| checkout | `~/Dev/Deboma`, the audit's commits on `main` and pushed |

**Every script needs `BUILD_ROOT=<path>` only when the build root is not the default**, and it
forwards that variable through its own `sudo` re-exec (fix in `5bf3aa0`), so it works as an
environment variable — do **not** point the default path at another disk with a symlink: forky's
`rsync` 3.5.1 runs as root and refuses to follow a symlink owned by another user, which is what
killed the first two release runs.

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

Nothing is ready to write yet, because the kernel stage went with `/deboma-build`:

```sh
scripts/build-kernel.sh            # ~95 min: downloads 7.2.7, patches it, builds it
scripts/install-kernel.sh          # staged kernel -> the rebuilt rootfs, depmod, initramfs
scripts/verify-rootfs.sh           # what write-sd.sh / make-image.sh check first
```

Then two ways, independent of each other:

1. **Card straight from the built rootfs** (no release needed, ~few minutes):
   ```sh
   scripts/write-sd.sh /dev/mmcblk1
   ```
   It verifies the rootfs, partitions the card (p1 kernel 128 MiB / p2 `/boot` ext2 512 MiB / p3
   root), copies the rootfs, writes `/etc/fstab`, builds and signs a kpart for **that** card's
   `root=UUID`, and refuses `mmcblk0` (the internal disk) and the running root. The card is 14.8 GB,
   so p3 takes the whole card; the 6 GiB image below would leave the rest unused.
2. **Card from the release image**, which needs the rest of the release first (§ next):
   ```sh
   scripts/make-release.sh            # -> $WORK_DIR/release-google-asurada/
   xz -dc ~/.cache/debian-aarch64/work/release-google-asurada/google-asurada.img.xz |
       sudo dd of=/dev/mmcblk1 bs=4M conv=fsync
   ```

Boot it from the firmware's developer-mode menu: **internal disk = eMMC, external disk = microSD**.

## Then: finish the release

```sh
cd ~/Dev/Deboma
scripts/build-kernel.sh                               # ~95 min, only if it is not staged yet
scripts/install-kernel.sh                             # staged kernel -> $ROOTFS
scripts/make-release.sh                               # image, xz -T0 -6, tar zstd -T0 -12
```
- `make-release.sh` verifies the rootfs first (`scripts/verify-rootfs.sh`) and refuses to publish a
  tree that does not verify; ~25 min, and it regenerates the image (fresh filesystem UUIDs), so the
  `.img`, its `.xz` and the published `.vmlinuz.kpart` all end up matching each other.
- Needs ~9 GB more than the tree already uses; the eMMC has ~44 GB free.
- The rootfs for this tree is already rebuilt at `4bd56ce` (with `omasnap` in it), so the optional
  `build-rootfs.sh` step is done — but it rebuilds from scratch, so if you run it again,
  `install-kernel.sh` and `install-omasnap.sh` have to follow it.
- Full pipeline in one go: `scripts/build.sh` (kernel + omasnap + rootfs + kernel + omasnap + kpart).

## Then: close F7

1. Boot the new card and run `check-system.sh` as the desktop user — with a checkout it also checks
   every declared package: `check-system.sh ~/Dev/Deboma`. Expect **0 FAIL**.
2. Save it as `reports/<date>-omarchy-rebuild.txt`, mask the Wi-Fi MAC down to its OUI
   (`74:4C:A1:XX:XX:XX`, the one edit `reports/README.md` allows), add a section describing it to
   `reports/README.md`, and update `docs/releases/v0.2.0.md` with its counts (the "Validation"
   section currently describes the *patched* card, not this rebuild).
3. Flip the release pointer (`- **Release:** [`v0.1.1`] …`) to `v0.2.0` in `README.md`.
4. Tag: annotated tag `v0.2.0` whose message is `docs/releases/v0.2.0.md`, then publish the four
   assets + `SHA256SUMS` from `$WORK_DIR/release-google-asurada/`
   (`~/.cache/debian-aarch64/work/release-google-asurada/` by default).

## Not part of this build (do not mistake for a regression)

- **Touchpad scrolling is inverted** on the microSD card only: `~/.config/hypr/input.lua` sets
  `natural_scroll = true`. It is a personal override and is deliberately **not** in the repository,
  so a freshly written card keeps Omarchy's default.
- `omarchy-provision-first-run` retries its first-run steps on every login (its autostart entry is
  excluded by design, but Hyprland prepends `$OMARCHY_PATH/bin` to the session `PATH`, so the call
  resolves anyway), leaving one failed step per line in
  `~/.local/state/omarchy/first-run.log`; `Owe.LockFeed` is deferred with the `omarchy-pkgs` set, and
  stock Quickshell 0.3.2 logs `Unrecognized pragma "OmarchyLoadPatch"`. All documented in the
  release notes.
