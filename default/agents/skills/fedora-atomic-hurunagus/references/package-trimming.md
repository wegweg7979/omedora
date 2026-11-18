# Trimming packages out of the image

The mirror of *Adding a package*: same evidence-first discipline, one extra
decision (which seam) and one trap that aborts the migration queue on the next
rebase.

## Where the bake set comes from

`build_files/omarchy-base.packages` + `fedora-baseline.packages` (vendored copies
of upstream's Arch-name lists) are resolved through `build_files/fedora.toml` by
`fedora-resolve.py`, then filtered by `EXCLUDED_PACKAGES`, then `EXTRA_PACKAGES`
and the app-install blocks are added. The resolver is the authority on the RPM
names a change must match — run it, never read the list text:

```bash
python3 build_files/fedora-resolve.py --map build_files/fedora.toml \
  build_files/omarchy-base.packages build_files/fedora-baseline.packages
```

**A name you excluded still appears in that output.** `EXCLUDED_PACKAGES` is a
shell-side filter applied *after* the resolver runs, so "the resolver still emits
it" is not evidence the exclusion failed. Verify by emulating the filter (read
the array out of `build.sh`, subtract it from the resolver output) and check the
count moved by exactly the number of names you added.

## Pick the seam by who ADDS the package

| Who adds it | Seam | Why |
|---|---|---|
| nothing at runtime — the bake list is the only source | `EXCLUDED_PACKAGES` in `build_files/build.sh` | one line, matches the resolver's RPM names, keeps the vendored Arch list comparable with upstream |
| a migration, a menu row's installer, or a `setup` command calls `omarchy-pkg-add <name>` | a `source = "skip"` entry in `install/packages/fedora.toml` | an `add` for a skip entry prints the reason and exits **0**; an unmapped, not-baked package answers "bake it into the image build" and exits **1**, which aborts `omarchy-migrate`'s whole `set -e` loop and hides every later migration |

One family can need BOTH seams: the CJK fonts are bake-only, so they go in
`EXCLUDED_PACKAGES`, while the CJK engines are added at runtime by a migration and
by the Input Methods setup command, so they take `skip` entries — one change, two
seams, and picking one seam for the whole family would have broken the migration
queue or left a menu row offering a package that never installs.

Find the runtime adders before choosing:

```bash
grep -rn 'omarchy-pkg-add' migrations/ bin/ install/ | grep -w <arch-name>
```

Probe the runtime behaviour read-only instead of reasoning about it:
`OMARCHY_PKG_DRY_RUN=1 python3 bin/omarchy-ostree/pkg.py add <name>` exits 0 with
`already baked` / `skipping …` and 1 only when a real run would abort the queue.

Whichever seam you pick, keep the image's `build_files/fedora.toml`
**byte-identical** to omedora's `install/packages/fedora.toml` — it is a vendor
copy with no sync job, so edit the canonical file and re-copy.

## Close the user-facing seam too

A row whose command needs the dropped package must hide, not fail: the port's
idiom is a `when` gate on the row, `"when":"omarchy-cmd-present <cmd>"`.
`default/omarchy/omarchy-menu.jsonc` is an upstream file, so the replaced line
needs a byte-identity ALLOW entry — and the value must be **appended into the
existing per-file blob**, because a second `ALLOW["<file>"]=` assignment
overwrites the first (bash assoc arrays) and silently drops every earlier
deletion recorded for that file.

## Find candidates with evidence, not vibes

- Installed size, biggest first: `rpm -qa --qf '%{SIZE}\t%{NAME}\n' | sort -rn`.
- What actually runs: `systemctl list-units`, `pgrep -a <name>`; what nothing
  needs: `rpm -q --whatrequires <pkg>`. "Installed but nothing requires it" is a
  candidate, not a verdict.
- Packages absent from the resolver output arrived as dependencies or weak deps.
  Name the parent before proposing a drop:
  `dnf5 repoquery --installed --whatrecommends <pkg>` (e.g. `nvidia-gpu-firmware`
  ← `linux-firmware`'s Recommends; `ibus` ← `gnome-shell`'s).
- The lever for that class is `--setopt=install_weak_deps=False` on the image's
  dnf calls — a wide hammer that also drops WANTED weak deps (`iw` for the Wi-Fi
  tooling is the standing example). If you take it, add the wanted ones to
  `EXTRA_PACKAGES` explicitly and diff the resulting package set against the
  previous build.
- Locale trap: `glibc-all-langpacks` is a weak dep nothing requires, and no
  `glibc-langpack-*` ships beside it — dropping it alone leaves C-only locale data
  (dates, currency, collation). Swap in a langpack, never just remove it, and pick
the one that carries the host's actual locale: read `localectl status`
  (`LANG=en_GB.UTF-8` here → `glibc-langpack-en` covers it; the per-language split
  is by language, not by territory). The swap is not optional or deferrable:
  `glibc` carries a **hard** `Requires: glibc-langpack = <evr>`, so `remove
glibc-all-langpacks` cannot resolve at all until the replacement is INSTALLED —
  the same change has to add it to `EXTRA_PACKAGES`.
- Read the user's own complaint as the priority signal: something visibly RUNNING
  that they never use (a daemon in btop) beats a big package they never notice.

## Verify a trim without spending a build

Two dry runs, both change nothing. They are the proof that the list is solvable and
that the runtime delta is exactly what you intend:

- **On the running host** (its package set is the image's): `dnf5 remove -y --assumeno <names>`
  prints the whole transaction, including `Removing dependent packages:` and
  `Removing unused dependencies:`. A real trim of 15 names resolved to 15 + 3 dependents
  (`python3-boto3`, `python3-s3transfer`, `python3-ibus`) + 8 orphaned `*-devel`
  (~24 MB) with no solver failure — those two extra groups are what grepping cannot predict.
- **In build order, inside the cached base** (already local, 6.1 GB): a removal that is
  only solvable once something else is INSTALLED can never show up on the host, because
  `remove` never adds a package.
  ```bash
  podman run --rm ghcr.io/ublue-os/base-main:latest bash -lc \
    'dnf5 -y install <dep> >/dev/null && dnf5 remove -y --assumeno <names>'
  ```
  This is what caught `glibc`'s **hard** `Requires: glibc-langpack = <evr>`: with no
  langpack installed, `remove glibc-all-langpacks` fails to resolve ("The operation would
  result in broken dependencies … installed package glibc requires glibc-langpack"), and it
  only resolves once the replacement is installed first — so the swap must be an
  `EXTRA_PACKAGES` addition in the same change, not a note for later.

Ground truth for "base-inherited or image-added": the cached base lists its own packages
— `podman run --rm ghcr.io/ublue-os/base-main:latest rpm -qa` (1 358 names). Anything
absent there, absent from the resolver output and absent from `EXTRA_PACKAGES` arrived as a
dependency, and `--whatrecommends` / `--whatrequires` names its parent. Order the removal
block **last** in `build.sh` (just before the cleanup section) so a later omedora refresh
cannot pull a removed package's dependency back in.

**Then verify the BUILT image, not the resolver output — the filter cannot see two whole
classes of package.** `EXCLUDED_PACKAGES` prunes the build's own resolved list only:

- **base-inherited**: already in `ghcr.io/ublue-os/base-main`, so filtering the name drops
  this build's copy while the base's survives (the F44→F45 upgrade even refreshes its NEVRA,
  so its install time reads as "added by this change"). Worked examples here:
  `google-noto-sans-cjk-fonts` (124.6 MiB) and `qemu-user-static` (~175 MiB, deliberately
  kept — but it is the same trap).
- **dependency-pulled by a base package**: never on the resolved list, so there is no line to
  filter. `google-noto-{sans,serif,sans-mono}-cjk-vf-fonts` (116 MiB) arrive as `Requires` of
  `default-fonts-cjk-{sans,serif,mono}`, which are themselves in the base — so the removal
  block must name the metas as well, or the fonts come straight back.

Both classes are invisible to the two dry runs above: the resolver, `--assumeno` and the
cached-base simulation all reason about the build's list, and they all agreed a 241 MiB CJK
font stack was gone while it shipped. The only real check is on the artifact:

```bash
rpm -qa --qf '%{NAME} %{SIZE}\n' | grep -i <family> | sort -k2 -nr   # on the box after the rebase
podman run --rm <built-image> rpm -q <names>                          # or on the image itself
```

## What a trim does NOT do

- It does not uninstall from the running host: a baked RPM cannot be
  `omarchy-pkg-drop`ped, and a `system-flatpaks.list` edit only affects NEW
  installs — an already-installed flatpak needs `flatpak uninstall --system <id>`.
  Say that plainly instead of implying the box changed.
- It does not shrink the current deployment: the effect lands on the next image
  build plus rebase.

## Keep-list (do not trim these)

- `herdr` — deliberately kept: its server runs inside the graphical session so
  panes inherit `WAYLAND_DISPLAY`, which is what lets a remote `ssh` login read the
  clipboard. It is a real feature, not an idle daemon that merely shows up in btop.
- `fcitx5` + `fcitx5-gtk` + `fcitx5-qt` (the framework: layout switching and
  XCompose) even when the CJK engines go; the non-CJK Noto fonts.
- `podman` — the image's own recipes use it.
- `qemu-user-static` (~175 MB) — foreign-architecture emulation for `--arch` containers and
  foreign binaries (31 live `binfmt` registrations in `/proc/sys/fs/binfmt_misc`), **not**
  VM tooling. `containers-common-extra` (a 0-byte podman package) is what pins the aarch64
  subpackage, so dropping the set means dropping that too. The user keeps it.
- `qemu-guest-agent`, `spice-vdagent`, `spice-webdavd`, `osinfo-db`, `libosinfo` — 6.9 MB of
  guest-side agents; they make the image's own VM boot tests nicer.
- `gcc`, `gcc-c++`, `kernel-cachyos-devel` — needed to build modules against the running
  kernel; deliberately kept by the kernel-swap module (`*-devel-matched`).
- **Brave**: the `brave-origin` RPM is the browser (already the session default), and the
  Flathub `com.brave.Browser` was removed from `system-flatpaks.list` for NEW installs only —
  the user explicitly keeps the flatpak on the boxes that already have it.
- **There is no RPM virt stack to de-duplicate** on this box: `virt-manager` plus its Qemu
  *extension* flatpak (both declared in `system-flatpaks.list`) are the entire virtualisation
  stack — no host `libvirt`, `qemu-kvm`, `virt-manager` or `edk2-ovmf` RPMs exist and `virsh`
  is not installed. Don't go looking for a duplication that isn't there.
