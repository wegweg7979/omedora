# PLAN — omedora 4.5 delta (0.2.0-beta.9 → 0.3.0-beta.1)

Status: **draft, nothing executed.** Written 2026-11-11 against the measured inventory of the
fork `wegweg7979/omedora` (`omedora-4`, HEAD `2c68f335`) and upstream `AndrewGaspar/omedora`
tag `v0.3.0-beta.1` (`5ecb9a6`).

## Baseline (measured)

| | fork | upstream target |
|---|---|---|
| version | 0.2.0-beta.9 | **0.3.0-beta.1** |
| base-version | 4.0.6 | **4.5.0** |
| commit | `2c68f335` | tag `v0.3.0-beta.1` = `5ecb9a6` |

Fork point `f0020448` (2026-08-14). Since then: upstream moved **4993 files** in 1713 commits;
the fork moved 938 files in 436 commits; **828 files were touched by both**, carrying 63,563
lines of fork-side churn.

A plain `git merge` of the tag into the fork produces **179 conflicts** (85 both-modified,
43 both-created, 42 fork-deleted, 9 upstream-deleted). Cherry-picking the fork's 9
"pure-fork" commits onto the tag applies **2 of 9** cleanly (the rest are modify/delete, i.e.
files upstream does not have at all).

**Therefore: re-port as a thin delta on top of the tag. Do not merge.** The delta is a file
set (~10 `bin/` files plus payload) and a transform (migration guards), not a commit range.

## Method

One branch off the tag (`omedora-4.5`), six phases, each phase its own commit series and its
own verification. `main`/`omedora-4` is not touched until Phase 7 passes. Upstream's file wins
wherever the two sides rewrote the same file; the fork's change is re-applied on top by hand.

---

## Phase 1 — the immutable layer (10 files, the actual delta)

| file | what / why |
|---|---|
| `bin/omarchy-ostree/update` | the bootc/`rpm-ostree` apply step + migrations + "reboot to apply"; upstream has no equivalent |
| `bin/omarchy-ostree/update-available` | checker keyed off rpm-ostree's own `.staged`; never polls skopeo (deliberate) |
| `bin/omarchy-ostree/pkg.py` | read-only RPM/Flatpak query; Flatpak-only add/drop; refuses to "install" an RPM that must be baked |
| `bin/omarchy-distro` | **shared file — take upstream's, re-add only the third token `fedora-ostree`** (`/run/ostree-booted` marker; unset marker must still mean mutable `fedora`) |
| `bin/fedora/voxtype-install-pkg` | bake-path helper for voxtype — see the voxtype decision below |
| `bin/omarchy-system-{logout,reboot,shutdown}` | upstream **retired** these; the fork keeps them, and 6 files reference `omarchy-system-reboot` (including `bin/omarchy-ostree/update`) |
| `bin/omarchy-voxtype-{install,remove,status}` | the fork's voxtype shims |
| `install/user/first-run/install-voxtype.hook`, `default/hypr/bindings/voxtype.lua`, `shell/plugins/bar/indicators/Dictation.qml` | the rest of the fork's voxtype stack |

Copy these files; do not cherry-pick their commits (7 of 9 collide as modify/delete).

## Phase 2 — the `fedora-ostree` token and the command case-dispatch

Shared files, small hand edits, same shape as the existing port: anywhere a command's Fedora
branch runs on this image, `fedora` must also match `fedora-ostree`.

- `bin/omarchy-distro` — the marker seam (Phase 1).
- `bin/omarchy-version`, `bin/omarchy-version-channel` — the two commands already caught by this
  (`pacman -Q` fallback / mirrorlist grep). Re-check both against upstream's current bodies.
- Any `case "${OMARCHY_DISTRO}" in fedora) …` or `[[ "$(omarchy-distro)" == fedora ]]` in
  upstream's new code — grep the whole `bin/` + `default/` for `fedora`, not just what we ported
  last time. Upstream added a lot of Fedora-awareness in 4.5; most of it will be correct for
  `fedora-ostree` too, but each site needs one look.
- `bin/omarchy-provision-owner` + the first-boot units (`Before=display-manager.service`).

## Phase 3 — migration gating (the biggest hand-work item)

143 migrations are new upstream, 68 more were changed by both sides.

| bucket | count | action |
|---|---|---|
| new, already carry a distro guard | 35 | nothing |
| **new, call `omarchy-pkg-add`** | **20** | each is a bootc trap: a missing package aborts the migration chain. Bake the package (map + `EXCLUDED_PACKAGES`) **or** add the `fedora-ostree` guard |
| new, no boot/kernel/pkg work | 88 | spot-check only |
| shared, mechanical gate (≤6 lines, mentions `fedora-ostree`/`ostree-booted`) | 24 | re-apply the same one-line transform |
| shared, needs a real look | 44 | upstream rewrote these; take upstream's body, re-apply the guard |

The 20 `omarchy-pkg-add` migrations, with what they add:

| migration | adds |
|---|---|
| `1787133200.sh` | `qt6-imageformats` → mapped to `qt6-qtimageformats` |
| `1787589206.sh` | `[omarchy]` repo key migration — **Arch only** |
| `1787815267.sh` | `cups-browsed` group/user handling |
| `1788112314.sh` | `pacman-rc.conf` `[omarchy]` edge repo — **Arch only** |
| `1788129995.sh` | NoDisplay launcher override |
| `1788596255.sh` | `vi` |
| `1789444024.sh` | kernel migration (fresh-ISO case) |
| `1789764927.sh` | TTY-update enables the next graphical login |
| `1790539857.sh`, `1790542069.sh`, `1791708587.sh` | `preinstalls-removed` cleanup |
| `1790702362.sh` | omarchy-app agent skill (Hype/Monologue/Omacut) |
| `1790973240.sh` | ASUS ProArt P14 speakers helper — **hardware-specific** |
| `1790984500.sh` | x86_64 memory stack on N1x |
| `1791345484.sh` | `disktree-bin` |
| `1791367434.sh` | fcitx5 mozc/hangul/chinese/chewing |
| `1791403310.sh` | `omarchy-hyprland-titlebars` — **not on Fedora (4.5 changelog)** |
| `1791542175.sh` | Gliff — **no aarch64 build** |
| `1792041364.sh` | `omarchy-hw-aarch64` branch |
| `1793512402.sh` | `xorg-xsetroot` — **X11 only** |

Recommendation: script the guard transform (idempotent + `--dry-run`) rather than hand-editing
92 files; hand-review only the 20 above and the 44 review list.

## Phase 4 — re-assert the prune

118 files the fork deleted outright: `bin/` 83, `install/` 26, `test/` 4, `migrations/` 2,
`default/` 2, `etc/` 1. Re-delete them after taking upstream's tree, from an explicit list (the
existing branch already knows them: `git diff --diff-filter=D --name-only f0020448..2c68f335`).

COPR side: keep the pruned `SPECS` list in `omedora/packaging/copr/build-repo.sh` (XR:
hypxrland/monado-xreal/basalt-xreal/xreal-ctl, plus openclaw and hyprpad). Upstream keeps
updating XR; keeping it pruned means carrying a difference, dropping it means more COPR work.

## Phase 5 — packaging

- `install/packages/fedora.toml`: the tag's version is 837 lines / ~337 entries; the fork's is
  516 lines / ~197 entries and needs +323/−2 to match. **Take upstream's file, then re-apply the
  fork's extra entries** (and confirm each is still needed — some may now be upstream's).
- New 4.5 app RPMs: `omasnap`, `owe`, `hype`, `monologue`, `signed`, `disktree` — upstream
  publishes them for f44 **and** f45; decide whether to consume `agaspar/omedora-4` for them or
  build them in `wegweg7979/omedora-4`.
- Voxtype: 4.5 makes voxtype the default dictation backend and **retires the install shims** —
  see the decision table.
- 4.5 drop-ins to fold in: mise, XKB, the ten-minute sudo timeout, WirePlumber camera drop-in,
  the docker-group change (installs no longer join it).

## Phase 6 — identity and payload (fork-only files)

`themes/` 87, `test/` 76, `shell/` 3, `install/` 3 (`fix-powerprofilesctl-shebang.sh`,
`user/git.sh`), `applications/` 2 (`Disk Usage.desktop`, `Docker.desktop`),
`default/` 2 (`hypr/apps/qemu.lua`, `hypr/bindings/voxtype.lua`), `config/` 1
(`xournalpp/settings.xml`), `docs/` 2 (`AUDIO-TUNING.md`, `migrations.md`), plus the hurunagus
payload already in the image repo. These have nothing to merge against — carry them, and drop
the ones that are dead weight (the two `.desktop` files and `xournalpp/settings.xml` are the
first candidates).

## Phase 7 — verification gates (all must pass before `omedora-4` moves)

1. Upstream's test suite green on the branch (the `Test` workflow).
2. The fork's own gates green: `test/shell.d/ostree-update-available-test.sh`,
   `migration-gating-test.sh`, `distro-test.sh`, `menu-guard-fedora-test.sh`,
   `copr-chroot-probe-test.sh`.
3. `just`/COPR spec check: `build-repo.sh` builds the pruned set for f44 + f45.
4. COPR publishes `omedora 0.3.0~beta.1` from `wegweg7979/omedora-4`.
5. Image build (hurunagus-hyprland) → `podman run --rm <img> rpm -q omedora` shows the new
   NEVRA, and `grep -c 'select(.staged==true)'` in the baked `update-available`.
6. VM boot before any real machine; then rebase a non-primary box (mini or lounge), not
   studiobox2.

## Decisions needed

| # | decision | recommendation |
|---|---|---|
| 1 | `omarchy-system-{logout,reboot,shutdown}`: keep the fork's 3 files, or adopt upstream's removal and retarget the 6 call sites (incl. `bin/omarchy-ostree/update`)? | keep for now — smallest change, and the menu references them; revisit once the delta is stable |
| 2 | voxtype: keep the fork's shims + `voxtype-install-pkg`, or adopt 4.5's default-backend path and retire them? | adopt 4.5's path, keep only the bake-path helper if it is still needed |
| 3 | XR/COPR prune: keep it, or re-adopt upstream's XR specs? | keep pruned |
| 4 | 4.5 app RPMs: consume `agaspar/omedora-4`, or build in `wegweg7979/omedora-4`? | build in your own COPR (already the case for everything else) |
| 5 | branch name and whether `PLAN-immutable-adaptation.md` stays as-is | `omedora-4.5`; leave the old plan file, add this one |

## Not in this plan

Merging the 436-commit fork into the tag (179 conflicts to protect 9 commits); carrying the
118 pruned files back; touching `native/`, `host/` or the image repos.

---

## Phase results so far (branch `omedora-4.5`)

| commit | phase | what landed |
|---|---|---|
| `3d0515658` | 1 | the immutable layer carried; `fedora-ostree` token + dispatch arms merged into upstream's 4.5 bodies |
| `41d93c637` | 2 | every non-migration dispatch site decided: 9 arms extended, 3 new refusals, 7 comparisons extended |
| `ee6841ca3` | 3 | 60 migration gates made pattern-compares (`== fedora*`) |

Branch delta vs the tag: **91 files, +648/−79.** Nothing pushed; `omedora-4` untouched.

### Phase 3 outcome: the 20 unguarded `omarchy-pkg-add` migrations

Checked empirically with `OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <pkgs>` under
`OMARCHY_DISTRO=fedora-ostree` (the helper exits 0 when the package is baked, a
satisfying flatpak exists, or the map skips it; exits 1 with "bake it" otherwise).

**Already satisfied — no action (4):** `1787133200` (qt6-imageformats),
`1787815267` (cups-pk-helper), `1788596255` (vi), `1790984500` (rtkit,
zram-generator). `1789444024` calls no pkg-add.

**Needs a map entry or a bake (12) — this is phase 5 work, not code:**

| migration | package(s) | recommended disposition |
|---|---|---|
| `1788129995` | omasnap | bake — 4.5 base app, upstream has it in the COPR for f44+f45 |
| `1789764927` | owe, owe-lockfeed | bake — same |
| `1790539857` | monologue | bake — same |
| `1790542069` | hype | bake — same |
| `1791708587` | signed | bake — same |
| `1791345484` | disktree-bin | bake — same |
| `1791367434` | fcitx5-mozc/hangul/chinese/chewing | map — Fedora has these names in its repos |
| `1790702362` | base-devel, qt6-* (omarchy-app agent skill build deps) | map — Fedora equivalents exist; decide whether the image wants the build toolchain |
| `1793512402` | xorg-xsetroot | bake (tiny) or map to skip — X11-only, this image is Wayland |
| `1791403310` | omarchy-hyprland-titlebars | skip-map — 4.5 changelog says it is not available on Fedora yet |
| `1791542175`, `1792041364` | gliff | skip-map — same reason |
| `1790973240` | asus-proart-p14-speaker-firmware | skip-map — hardware the fleet does not have |

The two pacman-repo migrations in the same bucket (`1787589206`, `1788112314`)
self-guard on `/etc/pacman.conf` / the mirrorlist existing, so they no-op on the
image — no gate needed.

### Phase 2 leftovers to revisit

- `bin/omarchy-update-status`: upstream's 4.5 version only clears the indicator; the
  fork's version refreshed it from `update-available`. Kept upstream's — check on the
  bar if the badge goes stale after a staged update.
- `bin/omarchy-update` line 77 and `omarchy-update-confirm` / `-restart`: the Arch
  pipeline, unreachable on the image because the dispatch arm execs the sibling first.
  Worth a look only if the menu exposes `omarchy update restart` on bootc.
- `bin/omarchy`'s ~80 lines of group-description pruning: belongs to phase 4.
