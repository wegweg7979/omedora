# Kernel swap into an atomic image + building the Omarchy kernel for Fedora

Two distinct halves of "run a custom kernel on the hurunagus image": the swap
mechanism into the image (proven) and packaging the Omarchy kernel as an RPM
(not yet done on Fedora — genuinely novel).

## Where the user's proven kernel-swap module lives

`hurunagus-silverblue/modules/custom-kernel/` (`module.yml` + `custom-kernel.sh`
+ README) — the working BlueBuild module this user built. It is the reusable
reference for swapping a kernel into a ublue/atomic image at build time.
Port its logic (don't reinvent) when wiring a custom kernel into any image.

Its mechanics, in order (this is the skeleton to re-use):
1. **Disable the kernel-install hooks** so the base-image kernel packages don't
defend themselves during the swap: back up `/usr/lib/kernel/install.d/05-rpmostree.install`
and `50-dracut.install`, replace each with a `/bin/sh`
`exit 0` stub; restore after. (Hook files, not systemctl units — `mv`/stub, no
`systemctl`.)
2. **Remove the stock kernels**: `dnf -y remove kernel kernel-core kernel-modules
 kernel-modules-core kernel-modules-extra kernel-devel kernel-devel-matched || true`
 then `rm -rf /usr/lib/modules/*`.
3. `dnf -y copr enable <owner>/<repo>`, install the custom kernel's
`-core`/`-modules`/`-devel-matched` packages (the module's case table selects
CachyOS variants and their COPRs). `-devel-matched` matters so DKMS/akmods
find the right headers.
4. Restore the hooks, `rm -f /etc/yum.repos.d/*copr*`.
5. Optional scope toggle for later, NOT v1: `initramfs` regeneration
(`dracut --no-hostonly --reproducible --add ostree`), NVIDIA akmod build for
the exact `KERNEL_VERSION`, and Secure-Boot signing (MOK key/cert/password +
first-boot `mok-enroll.service`). Keep these out of a first cut.

`hurunagus-hyprland` is a **ublue-template** repo (Containerfile + `build.sh`),
NOT BlueBuild — so the module can't drop in as a `module.yml`. **It has since
been ported and shipped** (commits `ba703d2` for the swap, `107d504` for the
cleanups) as a `::group:: Swapping in the CachyOS kernel` block that sits **last
in `build_files/build.sh`, immediately before `::group:: Cleaning up`**, so
nothing later can pull the stock kernel back. Live state: `KERNEL_FLAVOR="cachyos"`
(the GCC build) with `kernel-cachyos{,-core,-modules,-devel-matched}` from
`bieszczaders/kernel-cachyos`, a generated initramfs, and a size assertion.

## The port, as shipped

- `KERNEL_FLAVOR` + a case table for the five flavors, so switching flavors is a
  one-line edit. COPR `bieszczaders/kernel-cachyos` is the official CachyOS port
  to Fedora (fedora-44/45 chroots exist). **There is no `-modules-extra`
  subpackage** — CachyOS does not split it the way Fedora does, so never assume a
  Fedora `kernel-modules-extra` driver exists.
- **Secure-Boot signing: SHIPPED since 2026-11** as its own build phase
  (`phase_sign` in `build_files/build.sh`, Containerfile phase 3/4) — the image
  signs the CachyOS kernel with a key it owns, commits the public cert, and ships
  `hurunagus-enroll-secure-boot-key` + a `ujust enroll-hurunagus-kernel-key`
  recipe. Secure Boot stays OFF by default; the signing exists for upstream
  parity (the owner keeps SB off on every box). Full design, traps and the
  OVMF verification rig: `references/secure-boot-signing.md`. Do not describe the
  kernel as unsigned any more.
- **Still not ported:** the NVIDIA/akmods half (Intel iGPU, no out-of-tree
  modules). `-devel-matched` is nevertheless installed, so that stays possible
  later — and if it ever happens, module signing is already covered: the kernel
  signs its own modules with the build-time key baked into the vmlinuz, and our
  cert is a CA, so it can be reused for `sign-file` plus `mokutil --trust-mok`
  (the `.machine` keyring needs `CONFIG_IMA_SECURE_AND_OR_TRUSTED_BOOT`, which
  this config has).
- **`initramfs: true` is MANDATORY here, not optional.** The base image bakes
  `/usr/lib/modules/$kver/initramfs.img` (~240 MB, mode 0600) via the dracut hook
  and the swap *stubs* `50-dracut.install`, so nothing else would create one. The
  image already supplies the right flags from config (`20-atomic-nohostonly.conf`
  → `hostonly=no`; `20-atomic-bootc-ostree.conf` →
  `add_dracutmodules+=" ostree bootc "`, comment: "so the system is actually
  bootable when derived container builds regenerate the initramfs"), which makes
  the module's `--no-hostonly --add ostree` belt-and-braces. Ordering matters for
  anything that must land in the initramfs (e.g. a plymouth theme): `system_files/`
  is copied at ~line 200 and dracut runs at ~line 452, so it already works.
- **Narrow the repo cleanup.** The module ends with
  `rm -f /etc/yum.repos.d/*copr*`, which here **deletes the omedora-4 repo the
  build deliberately keeps enabled**. Use
  `rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:*.repo`.
- **`-devel-matched` costs ~100 MiB, not ~50**: `kernel-cachyos-devel` (88 MiB)
  drags in bison, flex, m4, openssl-devel, zlib-ng-compat-devel,
  elfutils-libelf-devel, libzstd-devel. Removing the stock kernel also removes
  `virtualbox-guest-additions` (it depends on kernel modules).

## Four pitfalls, all hit for real on the first build

1. **`kernel-install add` RUNS during a container build.** The kernel's
   `%posttrans` guards it with `[ ! -e /run/ostree-booted ]`, and a build
   container has no such file — so the un-stubbed hooks (`20-grub`,
   `90-loaderentry`, `90-uki-copy`, `95-set-boot-entry`, `99-grub-mkconfig`)
   write `/boot/vmlinuz-*`, `config-*`, `System.map-*`, `symvers-*.zst` (all
   hardlinks to the module dir) plus a `/boot/loader/` directory into the image.
   bootc lint's **nonempty-boot** then flips pass → warning: `Checks passed`
   12→11, `Warnings` 2→3, with no red text anywhere. **Fix: snapshot `/boot`
   before the transaction and delete only what appeared afterwards** (`comm -13`
   over sorted listings). A snapshot rather than hardcoded paths, so a future base
   image that ships something in `/boot` is not clobbered.
2. **grub2-probe / grub2-editenv errors in the `%posttrans` output are
   cosmetic** (`failed to get canonical path of 'overlay'`, of `/boot/grub2`):
   no `/boot/grub2` in the image, overlay root. They do NOT fail the RPM
   transaction; the swap continues.
3. **dracut logs a failure and still exits 0.**
   `dracut-install: ERROR: installing '/root' to '/root'` — `/root` is a symlink
   to `var/roothome` and that target does not exist in the build container. The
   stock initramfs omits `/root` too (verified against the base image), so it is
   harmless — **but `set -e` cannot catch it**, and a real dracut failure
   returning 0 would ship a kernel that cannot boot. Hence the explicit
   post-dracut assertion (file exists, > 100 MiB) and the
   `initramfs verified: <bytes>` line in the log.
4. **`/var/lib/rpm-state/kernel-cachyos`** is left by the kernel's `%post` and
   shows up in lint's `var-tmpfiles` warning. Add `/var/lib/rpm-state` to the
   cleaning-up `rm -rf` list. With that plus the `/boot` snapshot the image is
   back to `12 passed / 2 warnings` — the exact pre-kernel baseline, whose two
   remaining warnings (`/run/sddm`, `/var/lib/tuned`) are inherited.

## Verification chain (reuse it — all read-only)

1. **Digest match.** The CI push step prints `digest=sha256:…`; `podman pull` +
   `podman images` must show the same digest, proving the registry artifact is
   what CI built rather than a stale tag.
2. **In-image sweep** (root inside the container): `kernel-cachyos*` present and
   `kernel`/`kernel-core` absent · exactly ONE dir under `/usr/lib/modules` ·
   `initramfs.img` present, 0600, ~250 MB, with `lsinitrd` counts proving its
   contents (kernel modules, systemd, plymouth **and the theme's
   `watermark.png`**) · both hooks restored, no `.bak` left · omedora-4 repo still
   present while bieszczaders is gone · `grep CONFIG_…
   /usr/lib/modules/$kver/config` for the flavor's real config (`CC_IS_GCC`,
   `SCHED_BORE`, `HZ=1000`, `PREEMPT_DYNAMIC`). `/usr/lib/modules/$kver/vmlinux`
   is absent in **both** the stock and CachyOS layouts here — not a BTF
   regression (and no BTF consumer is installed anyway).
3. **bootc lint as a comparison, not an absolute.** Totals vary with bootc
   version and applicability, so read them against the previous build's log: the
   count must return to its old value. A pass→warning flip is how a new problem
   appears with nothing red.
4. **A VM boot is the only proof of boot**, and the only way to see the splash.
   Nothing about the image substitutes for it. (Confirmed for this swap: the
   CachyOS kernel booted and the spinner theme + custom watermark rendered.)
5. **Reading a build mid-flight:** the per-job log endpoint 404s
   (`BlobNotFound`) until the job finishes and the browser live view needs a
   signed-in session; the **step-level API** (`/actions/jobs/<id>` → `.steps[]`)
   shows which step is running, and the **run-level archive**
   (`gh api repos/<o>/<r>/actions/runs/<id>/logs > x.zip`) is the post-completion
   source of truth. To rule the base image in or out as a cause, extract each
   run's base-pull layer set from its log — same-day rebuilds sharing every base
   layer means the delta is yours, not the base's.

## The Omarchy kernel (`linux-omarchy`) — what it is and where

- `linux-omarchy` = the Omarchy-custom kernel: **BORE CPU scheduler + ADIOS I/O
  scheduler**, ~170 patches over vanilla `linux-7.2.x`. Patch families: archlinux
  base, bore, tlbpull/smp-preempt/sched-*, mm (zsmalloc/mglru/ksm-rmap), btrfs,
  fuse, drm/i915 + drm/xe (incl. Dell XPS / Panther-Lake panel-replay quirks),
  amd display, sound/ASoC (incl. Dell XPS SOF), media/IPU7/ipu-bridge, HID, USB/
  thunderbolt, PCI/vmd, futex-wait-multiple, crypto/zstd. It also builds an
  optional NVIDIA-open module set in the same recipe.
- Source of truth: `omacom/omarchy-pkgs/pkgbuilds/linux-omarchy/PKGBUILD` (and
  the now-transitional `linux-omarchy-bore` — BORE became `linux-omarchy` itself;
  the namespaces all derive from `pkgbase`). It is **Arch/pacman only**.
- **No Fedora RPM or COPR of `linux-omarchy` exists** (verified — the
  `whelanh/omarchy-fedora` port uses Fedora's stock kernel explicitly because
  "Arch's custom kernels have no direct analog"). So this is a from-scratch
  port, not a repack.
- Versioning note (Arch): `pkgrel` is used to out-rank a same-name meta package;
  when an intermediate PR sets `pkgbase=linux-omarchy-bore` back into
  `linux-omarchy`, edge publishes under `-bore` names while `linux-omarchy`
  lags — always read the CURRENT PKGBUILD's `pkgbase`/`pkgver`/`pkgrel`, don't
  trust the repo listing.

## Building it for Fedora (proposed approach, v1)

The plan shape agreed with the user (plan-only, not yet executed; verify each
step before trusting):
- New COPR project `kernel-omarchy`, **separate from the `omedora-4` stack** — a
  kernel is huge/slow and would clutter the fast Omarchy package builds. Chroot
  `fedora-44-x86_64` only. Same `COPR_API_TOKEN` secret flow as `omedora-4`.
- Build the spec from the **vanilla Fedora `kernel.src.rpm` spec** and graft the
  omarchy patches + `config.x86_64` in (recommended) rather than translating the
  PKGBUILD from scratch — Fedora's spec carries correct `kernel-{core,devel,
  modules*}` subpackage boilerplate and firmware split.
- **Vendor the ~170 `.patch` + `config.x86_64` into the repo** for deterministic
  builds (they live one-per-file in `omarchy-pkgs`); fetching at build time
  risks remote breakage.
- Drop the `-nvidia-open` subpackage for v1 (Arch-specific prebuilt NVIDIA open
  modules); re-add later if wanted.
- **Build cost & risk:** full kernel with this patch set ≈ 1–3+ hrs in COPR
  (COPR timeout is 5 h — the runs already showed `Build timeout: 5 hours`). The
  genuinely uncertain part is the ~170 patches applied to a Fedora tree — most
  apply clean against the matching 7.2.x but DRM/sound/config ones can reject or
  need adaptation, and it's hours per retry. The image-side swap is the proven
  half (silverblue module). Concentrate debugging effort on the spec/patches,
  not the swap.

## Where the user's repos live on disk

All the user's repos are cloned under **`/var/home/user/Documents/GitHub/`**
(hurunagus, hurunagus-hyprland, hurunagus-silverblue, ublue) — NOT at the home
root. A `find ~ -maxdepth 2 -name .git` misses them (they're depth 4 under
Documents); look there first before cloning. The `/var/home/user` siblings
(`hurunagus`, `hurunagus-hyprland`, `omedora-inspect`) are separate worktrees,
and `hurunagus-hyprland.iso` is a 7 GB build artifact, not a repo.
GitHub repo list vs local clones: silverblue/ublue are on GitHub but the stock
`hurunagus` shell repo (umbriel/dank line) may not be cloned locally.
`git clone` from GitHub is NOT rate-limited like the unauthenticated REST API —
use shallow clones to search other repos instead of curl'ing the API.
