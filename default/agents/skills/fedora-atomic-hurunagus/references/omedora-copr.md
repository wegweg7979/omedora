# omedora COPR dependency (Hyprland + Omarchy runtime)

The user's `hurunagus-hyprland2` desktop is assembled almost entirely from the
`agaspar/omedora-4` COPR (`dnf5 -y copr enable agaspar/omedora-4`, then
`dnf5 install -y omedora omedora-settings`). Before advising on removing or
replacing it, know what it actually owns, because the ~61 packages split into
very different replacement-effort classes:

## What the COPR provides (split by replaceability)

**Hyprland binary stack - NOT replaceable without the COPR.**
`hyprland`, `hyprlang`, `hyprutils`, `hyprwayland-scanner`, `aquamarine`,
`hyprcursor`, `hyprgraphics`, `hyprtoolkit`, `hyprland-protocols`,
`xdg-desktop-portal-hyprland`, `hyprsunset`, `hyprpicker`, plus desktop
tools `quickshell`, `kitty`, `gpu-screen-recorder`, `satty`, `hype`,
`lazygit`, `lazydocker`, `starship`, `mise`.

Rule: **Hyprland is not in Fedora's official repos** (only partially/lagged).
An atomic Fedora Hyprland image needs *someone's* COPR for the compositor + its
lib chain. The only COPR-free alternatives are (a) compiling the whole
aquamarine/hyprwayland-scanner/hyprtoolkit chain from source inside the
Containerfile - a multi-hour, fragile build where every layer bumps API in
lockstep - or (b) switching to another maintainer's COPR (`lionheartp/Hyprland`,
`solopasha/hyprland`), which does NOT remove the third-party-repo dependency.

**Omarchy runtime/configs - fully vendorable into `system_files/`.**
`omedora`, `omedora-settings`, `omedora-nerd-fonts` and the Omarchy apps
(`omacut`, `omacalc`, `omasnap`, `omawrite`, `owm`). These ship dotfiles,
the SDDM theme, helper scripts (`omarchy-refresh-sddm`), and first-boot
provisioning - plain files that can live in `system_files/` and be copied in
with `cp -avf /ctx/system_files/. /` (exactly the mechanism the build already
uses to override the SDDM theme and strip omedora session entries).

**XR/vision stack - almost certainly droppable.** `basalt-xreal`,
`monado-xreal`, `wivrn-hypxr`, `xreal-ctl`, and the whole `hypxr*` family
(hypxrcompose / hud / va / voice / paper). Roughly a third of the COPR's
packages the user installs for nothing on a normal desktop.

## Verdict pattern for "can I remove the 3rd-party repo?"

Separate the two layers before answering:
1. **The customizations/settings** -> bake into `system_files/`, fully viable,
   low effort. This is usually the real goal.
2. **The binaries** -> cannot be dropped cleanly; either keep a COPR (ideally
   your own fork of just the ~12 Hyprland specs you use, so nothing comes from
   another person's repo) or compile from source.

Recommended: vendor `omedora-settings` -> drop what you don't use (the XR
family) -> keep a Hyprland packaging source you control. Don't source-compile
Hyprland yourself for a single-user image.

## Enumerating a Copr's packages reliably

The Copr web UI paginates at 25 rows and **ignores `?page=N` when N isn't
divisible by ~25** - both `?page=2` and `?paginate_by=100` return the same
first page. The API (`api_3/package/...`) also rejects the usual param shapes.
Reliable way: curl each page and grep the per-package links, dedupe:

```bash
for p in 1 2 3; do
  curl -sL "https://copr.fedorainfracloud.org/coprs/<owner>/<repo>/packages/?page=$p" \
    -o /tmp/pkg$p.html
done
grep -oE '/coprs/<owner>/<repo>/package/[^"/]+' /tmp/pkg*.html \
  | sed 's#.*/##' | sort -u
```

Counts drift as the maintainer adds/removes packages - re-enumerate before
acting. The project even tags itself as a personal test repo that others
"should not use."

## Publishing from your OWN fork's COPR (self-publish, no third party)

The user's fork `wegweg7979/omedora` ships the full COPR machinery:
`.copr/`, ~41 `*.spec` under `omedora/packaging/copr/`, and a
`.github/workflows/copr-build.yml` that auto-submits on push. To make this
fork the image's Hyprland + command-suite source (dropping `agaspar/omedora-4`):

1. **Re-point the single source of truth** - `bin/omedora-copr` reads
   `OMEDORA_COPR_OWNER` (default set to the fork's owner). Change the default
   there; the build workflow, the install plan gate, and the update checker all
   call this binary, so one edit propagates to every consumer. Set the env var
   only to override for a one-off.
2. **Prune `build-repo.sh`'s `SPECS` array of deleted specs.** After the
   immutable pruning deleted spec files (XR/hypxr*, gaming, openclaw,
   hyprpad), a full COPR build of the stale list FAILS on the now-missing spec
   files. Remove entries AND the descriptive comment blocks in the same pass;
   `grep '^  .*\.spec' build-repo.sh | while read s; do [ -f $s ] || echo MISSING`
   after editing to prove no dangling refs.
3. **Owner-rename ripples beyond the source of truth.** Changing the default
   owner breaks test fixtures and RPM labels that hardcode the old identity:
   the chroot-probe test asserts the default owner and the `--repo-id` string,
   the coexistence-plan test asserts the disclosed COPR name, `quickshell.spec`
   embeds it in a `-DDISTRIBUTOR="omedora COPR (owner/repo)"` string, and the
   workflow header comment names it. Grep the whole tree for the old owner
   (including `.spec` distributor strings and test fixture JSON) before
   committing the rename.
4. **The gateway is a secret, not a config.** `copr-build.yml` writes
   `COPR_API_TOKEN` (the full `[copr-cli]` block) into `~/.config/copr` on the
   runner. There is no working token in this environment - the user generates
   it and adds it as a repo secret. Never handle or request the token value.
   Generating it needs NO copr-cli: the web API page
   (`copr.fedorainfracloud.org/api/`) has a "Create API token" button; clicking
   the resulting row reveals the whole `[copr-cli]` block to copy as the
   secret. If that page shows no button/block and the user just made a Fedora
   account, the cause is almost always "not actually logged into COPR yet"
   (account provisioning lags accounts.fedoraproject.org) - confirm the top-right
   shows their username before assuming a missing feature. Business as usual is:
   create the account -> web page token -> repo secret `COPR_API_TOKEN` -> push.
   `pipx run copr-cli create-token` is the CLI fallback that needs no system
   install.
5. **A fresh account gates the whole path.** Creating/hosting a COPR project
   needs a Fedora/COPR account (`copr-cli create omedora-<major> --chroot
   fedora-44-x86_64,...` ) - confirm the user has one before promising the
   workflow will run. The fork-side code edits do NOT depend on it and can all
   be staged/committed first.
6. **Every new `bin/` helper must be declared in `omedora.spec`'s `%files`, not
   just installed.** When a command-suite change adds files that DON'T match the
   existing globs (`omarchy-*` / `omedora-*` / `fedora/`), rpmbuild aborts with
   "Installed (but unpackaged) file(s) found: /usr/bin/..." and the package
   FAILS on every chroot - the first COPR build of the fork after adding
   `bin/ostree/{pkg.py,update,update-available}` died exactly this way. Any
   new subdirectory (e.g. `bin/ostree/`, and its `/usr/share/omarchy/bin/<dir>`
   symlink-farm twin) needs an explicit `%{_bindir}/<dir>/` + `%{_datadir}/omarchy/bin/<dir>`
   entry. Before committing a helper, confirm nothing under `bin/` escapes the
   globs (`find bin -maxdepth 1 ... grep -vE '^(omarchy|omedora|fedora|\.\.\.'`),
   else the runtime package won't own its own files.
7. **Verify a COPR build on the COPR side, not the GitHub Actions run.** When
   on push the workflow logs "completed / success", that is NOT proof the
   packages built - the job can "succeed" and skip entirely when the secret
   gate is absent, or the SRPM build can fail after dispatch. Check the COPR
   **Builds / Monitor** page (owner/project -> Builds), and to read WHY a
   failure happened pull the per-build log directly:
   `https://download.copr.fedorainfracloud.org/results/<owner>/<proj>/<chroot>/<buildID>-<pkg>/builder-live.log.gz`
   (gzip -dc it). `api_3` does work for build status — `GET /api_3/build/<id>`
       returns `state`, `source_package.url` and `repo_url`; guessing a route shape
       (e.g. `/api_3/package/<id>`) is what returns "Such API endpoint doesn't
       exist". The GH job-log download API needs admin rights, so the monitor page
       + gz buildlog remain the reliable diagnosis path for a failed build. The full
       API-v3 recipe is in `references/copr-app-publishing.md`. The
   srpm-builds stage has the registration/SCM errors; the per-chroot
   `<id>-<pkg>/builder-live.log` tail carries the rpmlint/rpmbuild verdict.

8. **A blank `workflow_dispatch` "packages to build" input builds NOTHING *for the spec set* — do not read that as "it is a no-op".**
   The input's "default: all specs" is misleading in both directions. A dispatch
   sets no `event.before`, so the workflow falls back to `HEAD~1` and submits
   whatever that diff matches — and the diff applies the PAYLOAD globs (`bin/**`,
   `install/**`, `config/**`, `shell/**`, `migrations/**`, …) as well as changed
   `.spec` files. A tip whose last commit touched `bin/**` therefore submits
   `omedora-settings omedora` from that tip, and only a tip whose diff matches
   neither rule prints "Packages to build: <none>" and exits success having
   submitted nothing. Full rule: §"Which commit a build actually carries".
   To force a full-stack build you MUST
   paste the explicit list of every spec name into the input. Extract it from
   `build-repo.sh` without counting by hand:
   ```bash
   awk '/^  [a-zA-Z0-9.-]+\.spec/ {for(i=1;i<=NF;i++) print $i}' \
     omedora/packaging/copr/build-repo.sh | sed 's/\.spec$//' | tr '\n' ' '
   ```
   (the awk prints each space-separated spec token; this is the entire
   `build-repo.sh` SPECS array, minus the pruned XR/openclaw/hyprpad).
9. **A freshly created fork COPR is EMPTY — a push that changes only the
   self-sourced trio leaves the whole Hyprland stack unpublished.** Pointing
   the image at it then fails the container build with
   "nothing provides mise / uwsm / hyprland-no-session needed by omedora …".
   The workflow's changed-spec / self-source logic only rebuilds what shifted;
   it does not seed the ~36-package stack a new project starts without. After
   creating a fork COPR, run the explicit full-list dispatch (item 8) ONCE so
   the compositor + its lib chain + `uwsm` + `mise` + the vendored CLIs + the
   runtime trio are all published before retrying any image build. The full
   stack then appears on the COPR Builds tab as a batch (importing → running →
   finished), not one per push.

The change to the image is minimal once the COPR lives: flip one `copr enable
<owner>/<repo>` line in `build_files/build.sh`, sync the vendored resolve files
from the fork, and delete the hand-vendored `system_files/usr/bin/fedora/update-
available` override so the fork's own `bin/ostree/update-available` owns the
check (no split-brain between two checkers).

## Syncing the vendored resolve files to the image (exact boundary)

The image vendors three files from the fork checkout (paths relative to the
fork root; verify line-count drift before copying):

- `install/packages/fedora.toml`            -> `build_files/fedora.toml`
- `install/omarchy-base.packages`           -> `build_files/omarchy-base.packages`
- `omedora/install/fedora-baseline.packages`-> `build_files/fedora-baseline.packages`

**Do NOT touch `build_files/fedora-resolve.py`** - it is a build-ONLY resolver
(reads `--map/--copr-out` args) that the fork does NOT ship; the fork's only
related module is the runtime `bin/fedora/package_map.py`, which is a DIFFERENT
file. Copying `package_map.py` over `fedora-resolve.py` (or vice-versa) breaks
one side. The three files above frequently differ by nothing but the inert
`[sunshine]` skip entry, so after a sync that removes no other content it is
normal for `git diff --stat` to show only `fedora.toml` changed.

A `just sync-omedora` recipe (or a fork checked out as a dir adjacent to the
build repo, referenced by relative path) keeps the copy repeatable - match the
Justfile's existing `#!/usr/bin/env bash` + `[group(...)]` recipe style.

**Prove a map edit by its EFFECT on the resolved list, not the map text** — the resolver's output is
what the build actually installs, and a `source="skip"` → `source="dnf" names=[…]` change is invisible
until it does. From the image repo, before pushing:

```bash
python3 build_files/fedora-resolve.py --map build_files/fedora.toml \
  --fedora-version "$(rpm -E %fedora)" --copr-out <scratch>/copr-out \
  build_files/omarchy-base.packages build_files/fedora-baseline.packages | grep -n <name>
```

A hit proves the name reaches the bake set with nothing installed and no image build; a miss means the
entry's `source`/`names` keys are wrong, which is far cheaper to find here than in a 20-30 minute CI run.


<!-- absorbed from SKILL.md 2026-11-12 -->

## COPR ownership (2026-11)

The fork serves its own COPR now, not agaspar: `bin/omedora-copr` default owner is `wegweg7979` (was agaspar), project `omedora-4`. The repo's `.github/workflows/copr-build.yml` auto-registers/submits on push to `omedora-4` using the `COPR_API_TOKEN` repo secret (full `[copr-cli]` block from the COPR API page). `hurunagus-hyprland/build_files/build.sh` flips `dnf copr enable agaspar/omedora-4` -> `wegweg7979/omedora-4` (done — an enabled repo on a running host is the proof, not the file's text). `build-repo.sh` SPECS has XR (hypxr*/basalt/monado/wivrn/xreal), openclaw, hyprpad pruned.


<!-- absorbed from SKILL.md 2026-11-12 -->

## COPR build gotchas: fresh-project seed + Hyprland order-dependence (2026-11)

Two traps hit while seeding `wegweg7979/omedora-4` empty and building the full stack:

1. **Blank `workflow_dispatch` on `copr-build.yml` builds NOTHING, not "all specs".**
   The input description says "default: all specs", but that's only true when you provide an explicit space-separated list. A blank dispatch makes `github.event.before` empty, the workflow falls back to `HEAD~1`, diffs `.spec` files between those two commits, and if none changed it prints `Packages to build: <none>`   and exits success having submitted nothing (looks green, did nothing). **To seed a fresh/empty COPR project with the whole stack, paste the explicit full `build-repo.sh` spec list into the input** (36 names, deduped) — never rely on the blank default.

   **ALSO: `copr-build.yml`'s `on.push.paths:` list hard-codes the packages' payload dirs and does NOT include `etc/**`.** A push that touches ONLY `etc/fastfetch/config.jsonc` (which ships inside `omedora-settings` via its spec) matches no path → the workflow never runs → no COPR build, and you only notice later when the repo query still shows the old NEVRA. This is why the fastfetch config fix (commit that changed only `etc/`) didn't build after a normal push. If a push that should change a package builds nothing: check `git diff --name-only HEAD~1` against the `paths:` list FIRST; for `etc/` payloads either add `etc/**` to `paths` or dispatch the workflow manually with an explicit package list (`omedora omedora-settings`).

2. **COPR builds the whole requested set in PARALLEL → deep intra-stack BuildRequires race.
   `hyprland.spec` BuildRequires `pkgconfig(aquamarine)`, `hyprcursor >= 0.1.13`, `hyprwire` — those were still compiling when hyprland started, so it failed with "No match for argument: pkgconfig(...)" in under a minute (fast-fail, not a compile error). A fresh project has none of the stack prebuilt, so the first full build always races the deep chain** (glaze→protocols→utils→scanner→lang→graphics→wire→cursor→aquamarine→toolkit→hyprland→…). Fix is a **re-dispatch of only the failed leaves, in dependency order, after their `-devel` deps are green** (e.g. `hyprtoolkit hyprland hyprland-guiutils`, then `hyprland-guiutils` alone once toolkit lands). Also: `hyprland-no-session` is NOT a separate package — it's a subpackage of `hyprland.spec`, so building hyprland satisfies the image's `omedora` Requires. Confirm each package's LATEST build is green (old race-attempt failures linger in the Builds list and inflate the failed count).

3. **Don't name an RPM-owned helper dir after a real system binary.** The fork first shipped the immutable siblings as `bin/ostree/`, which installs a DIRECTORY at `/usr/bin/ostree` — but the system `ostree` RPM owns `/usr/bin/ostree` as a FILE (the ostree CLI), so installing `omedora` failed with "file /usr/bin/ostree ... conflicts with file from package ostree-...". COPR's mock build never reports it: it compiles the RPM in an isolated chroot WITHOUT the real ostree installed, so a dir named `ostree/` looks fine there.
   **Rule:** name immutable/dispatch sibling dirs to avoid real binaries. Renamed to `bin/omarchy-ostree/` (no `/usr/bin/omarchy-ostree` exists; matches the omarchy-* naming). `bin/fedora/` is safe (no system `/usr/bin/fedora`). Any dir that lives under `%{_bindir}` where a system binary shares its name is a latent file/dir conflict — only surfaces at image-install time, not in mock.

4. **"Same commit, different build" image drift WILL masquerade as a checker bug — check the baked payload, not the tag string.** The immutable image depends on the mutable omedora COPR. If the COPR is rebuilt between two image builds of the SAME git commit, the two images get the same tag (`latest.2026XXXX-<sha>`) but DIFFERENT content (different digest, different `omedora` NEVRA). A host booted on the older of the two keeps the OLD checker/payload even though the version string looks current. Symptom: user reboots to "the newest image" yet behavior doesn't change — because they booted the pre-rebuild content. **Diagnose by inspecting the baked payload, not the tag:** `podman run --rm <img> sh -c 'rpm -q omedora'` (read-only, safe) or compare layer-set hashes between advertised content.
   **Related ordering race: the image build and the COPR rebuild are two INDEPENDENT pipelines.** A push triggers a COPR rebuild; the image build (a separate job) bakes whatever `omedora` NEVRA was published when ITS `dnf install` ran — which can be an EARLIER commit if the image build started before the COPR rebuild finished. So "image build green" does NOT mean the image has the newest fork fix. **Before rebasing a host, confirm the freshly-built image's baked `omedora` NEVRA ends in the exact commit you intended** (`podman run --rm <img> sh -c 'rpm -q omedora'`), and if it shows an earlier `…git<oldsha>`, re-run the image build now that the COPR is green — but ONLY a `--no-cache` build will pick the fix up (see 6). Optionally verify the baked script's BEHAVIOR too (e.g. `grep -c 'select(.staged==true)' .../update-available` for the fix present, and its absence of the old skopeo poll), since an intermediate commit can carry one fix but not the final one.
5. **On immutable, the update CHECKER must defer to the OS's own staging state — never re-derive "is there an update" from a skopeo/registry digest poll.** The registry `latest` tag MOVES whenever the same git commit is rebuilt (a common occurrence since the COPR mutates between image builds), so comparing the booted digest against the moving tag reports a spurious "update available" that bootc/rpm-ostree correctly see as nothing-to-apply. The OS already answers "is there something to reboot into": a deployment with `.staged==true` in `rpm-ostree status --json` (booted=false + staged=true = pending). Key the checker off `.staged` (numeric `-gt` timestamp fallback only for hosts lacking the field) and do NOT poll skopeo for the digest. Then the checker can never disagree with bootc/rpm-ostree, because it reads the same deployment set they reconcile. Symptom of the wrong design: "omarchy update available says update, but bootc and rpm-ostree report no update available." — that asymmetry is the skopeo-poll giveaway.
6. **podman's layer cache will bake STALE COPR content no matter how many times you rebuild the same commit — force `--no-cache` when the image depends on a mutable external repo.** The Containerfile's main `RUN … /ctx/build.sh` is a single cached layer keyed on the RUN *instruction* + base image, NOT on the bind-mounted `build.sh` content or COPR state. If `build.sh`'s text is unchanged, podman replays that layer from cache and `dnf install omedora` NEVER re-runs — `--pull=newer` only refreshes base layers, so it does not help. Symptom: you push a fork fix, the COPR builds it green, the image rebuild "succeeds", but the baked `rpm -q omedora` is still the old NEVRA. Fix in this repo: a `NO_CACHE` env toggle in the Justfile `build` recipe appends `--no-cache` to the podman args, and the workflow's Build Image step sets `NO_CACHE=1` so image builds always re-resolve the COPR. General rule: any image build that installs packages from a mutable repo (COPR, etc.) needs a cache-bust (no-cache or a changing build-arg) or it silently bakes whatever the cache holds, not what the repo currently serves. The durable form of that bust is a dedicated always-invalidated phase that re-resolves just the volatile package, not `--no-cache` for the whole build — see `references/build-times-and-layer-cache.md`.
7. **"Why is the image so big / why is X installed?" — decompose the source, don't guess.** First, baseline vs. stock base: `podman run --rm <base> sh -c 'rpm -qa | wc -l'` vs the built image. For hurunagus the STOCK `ghcr.io/ublue-os/base-main:latest` already carries ~1,360 RPMs and the built image ~1,940, so only ~580 are ours (the 136-package Omarchy list + EXTRA_PACKAGES + deps) — the bulk of a "~1900 package list" is the Fedora/ublue base, NOT an over-install. To see what YOUR build actually requests, reproduce the resolve step locally (read-only): `python3 build_files/fedora-resolve.py --map build_files/fedora.toml --fedora-version <ver> --copr-out /tmp/c ≥ build_files/omarchy-base.packages build_files/fedora-baseline.packages` — the direct list is small, and most "overhead" is dependency closure. To find where ONE package enters: `podman run --rm <img> sh -c 'rpm -q <pkg>; rpm -q --whatrequires <pkg>'`. A package can be BUILT on the COPR yet NOT installed in the image (`omedora` repo's `kitty.spec` builds a newer kitty but the image only installs `foot`; kitty is referenced in menus/config as a non-default option) — a COPR build and an image install are two different things. Only packages that are a HARD line in `omarchy-base.packages` (like `starship`, the default shell prompt), in `EXTRA_PACKAGES`, or pulled as deps are actually baked; trimming image size means editing `omarchy-base.packages` and adding names to the build's `EXCLUDED_PACKAGES` array, not removing COPR specs.
8. **Migrations with `[[ "$(omarchy-distro)" == "fedora" ]] && exit 0` guards run their ARCH BODY on a bootc host.** `omarchy-distro` returns `fedora-ostree` (not `fedora`), so the skip is FALSE and boot/limine/mkinitcpio/pacman/systemctl Arch work fires on the immutable image — the most dangerous migration bug. Fix PER-MIGRATION, never blanket: for Arch boot/kernel/pacman/machine-image work (limine-mkinitcpio, mkinitcpio.conf, limine-entry-tool, Omarchy-kernel, quickshell-git swap, Kvantum removal, Snapper, zram sysctl, satty/nvim-Fedora-ownership) extend the guard to `fedora OR fedora-ostree` (skip both). For genuine user/system hardening whose body writes only `/etc` (mutable+persistent under bootc) or idempotent systemctl (wifi power-save, systemd-oomd, rfkill bluetooth, lid-gate fingerprint, lock-screen PAM, SSH dropped-conn, wpa unmask, SSH PAM PATH) LEAVE the `== fedora` guard — it already skips only mutable Fedora, so fedora-ostree runs them — and add an explicit "runs on immutable too" comment so an upstream merge can't silently revert it. Watch for INVERTED guards (`== "fedora" ]] || exit 0`, i.e. run-ON-Fedora) — those need `fedora-ostree` ADDED to run too. Always end with a full `bash -n` sweep of every migration.
9. **A migration that `omarchy-pkg-add`s a package that is NOT actually baked aborts the WHOLE migration chain on bootc — one failure stops every migration after it.** `omarchy-migrate` runs each migration under `bash -euo pipefail` and the runner is `set -e`, so a single nonzero exit kills the rest (symptom: "omarchies only the first one ran"). The immutable `pkg.py add` exits 1 with "not in the image… bake it into the image build and rebase" when the package is missing. **Getting the package INTO the image is a build.sh `$EXCLUDED_PACKAGES` concern, not a migration concern**: a name in `omarchy-base.packages` is still silently stripped before install if it's in the `EXCLUDED_PACKAGES` filter, so its pkg-add migration then fails on the immut adjustable host. **Fix the image bake, don't gate the migration**: remove the name from `EXCLUDED_PACKAGES` and rebuild; the migration then no-ops (`present`=true → "already baked"). Diagnostic shortcut: check the baked set read-only by running the helper inside the image — `podman run --rm <img> sh -c 'python3 /usr/share/omarchy/bin/fedora/pkg.py present <name>'` — and remember the map RENAMES Arch→Fedora names (`libvips`=baked-`vips-tools`, `qt6-imageformats`=baked-`qt6-qtimageformats`), so a "not in packages.txt" grep against Arch names is a false alarm; check the mapped Fedora name. Always scan ALL migrations' `pkg-add` targets against the true baked set up front, not just the failing one, to avoid hitting the next abort on the following reboot.

10. **Verifying a forked-package COPR actually serves your new commit — distinguish BUILD state, PUBLISH state, and STALE-METADATA read.** The three are not the same and each needs its own probe, and checking the wrong one gives a false "not ready"/"not built":
    - **Build state** (has COPR started/finished a build for the new commit?): read the project builds page `https://copr.fedorainfracloud.org/coprs/<owner>/<project>/builds/?page=1`, regex out `build/<id>/`, then curl one build page and grep its `Status:` line (`running`/`succeeded`/`failed`). The builds page shows the id hotspots but its status badge is often empty on the listing — you MUST open the individual build URL for a real status.
    - **Publish state** (is the built RPM visible in repo metadata?): query the repo direct `dnf5 -y repoquery --noplugins --refresh --repofrompath=omz,https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-<ver>-x86_64/ --repoid=omz '<pkg>' | grep -v src | sort | tail -1` — the NEVRA's `…git<sha>` suffix is the exact commit marker. **Publish lags the build by minutes**, so `succeeded` build ≠ metadata updated yet; key the all-clear off the NEVRA suffix, not the build status.
    - **Stale-metadata false alarm — pass `--refresh`, always.** A fresh `--setopt=cachedir=<scratch>` does NOT imply fresh metadata: a brand-new scratch cachedir with no `--refresh` served the OLD NEVRA for both packages minutes after their builds read `succeeded`, while the same command with `--refresh` (and `copr-verify-payload.sh`, which resolves the newest itself) already showed the new `git<sha>`. So `--refresh --latest-limit=1` is the fixed shape, and a read taken without `--refresh` proves nothing in either direction. If `--refresh` still serves the old NEVRA while the build page says `succeeded`, wait a few minutes and re-query rather than concluding the build failed.
    - **A push that built nothing shows up as NO new workflow run** because `on.push.paths:` silently filters it — and that filter applies to PUSH events ONLY. **A MANUAL `workflow_dispatch` IGNORES `on.push.paths` and always triggers** (verified 2026-11: an `etc/fastfetch/config.jsonc`-only push auto-built nothing, then a manual dispatch with an explicit `omedora omedora-settings` list ran and published it). So when an `etc/`-only push doesn't auto-build, the reliable escape hatch is a manual dispatch with the explicit package list — it WILL run. The dispatch's own failure mode is a BLANK input building nothing (empty spec diff, gotcha #1), NOT failing to trigger. After ANY push that should change a package, confirm a workflow run exists for that sha (`https://api.github.com/repos/<owner>/<repo>/actions/workflows/copr-build.yml/runs`) before waiting on build/publish; if only non-`etc` payload paths changed it should auto-fire, if only `etc/` changed dispatch it manually.
    - **Polling the GitHub Actions API unauthenticated to watch a build RAMPS INTO the 60/hour rate limit fast — switch the watcher to registry probes once the run is confirmed running.** A background watcher sleeping only 45-90s between `curl https://api.github.com/repos/<owner>/<repo>/actions/runs?...` calls exhausts the unauthenticated limit (60 /hr) within minutes; the API then returns `{"message":"API rate limit exceeded ..."}` (note: the JSON also carries an inner parse-breaking control char, so a naive `json.loads` throws "Invalid control character" and you can mistake it for a malformed payload). The build is what matters, not the API — once the workflow run is in_progress, verify via the registry instead: `skopeo inspect --no-tags docker://ghcr.io/<owner>/<repo>:latest | jq -r .Digest` to confirm a NEW digest landed, then `podman run --rm <img> sh -c 'rpm -q <pkg>'` for the `…git<sha>` NEVRA / `grep` the baked config. The GitHub API is only needed to *discover* a run exists; the registry is the reliable completion signal and costs no rate budget.

## Which commit a build actually carries (and how to read a submission)

- **A COPR build can only carry a commit that EXISTS ON THE REMOTE.** The workflow registers each package with `--commit "${{ github.sha }}"`, and the self-sourced trio is built by `git archive` of that ref. A fix sitting in an unpushed local commit therefore cannot be built — not by a push (nothing new to trigger) and not by `workflow_dispatch` (it defaults to the remote branch tip). So "trigger the build for my fix" MEANS pushing the ref first: say that plainly, push, and prove it with `git ls-remote origin refs/heads/<branch>` returning your sha rather than the old tip. Chasing this the other way round (dispatching first, reading the log after) yields a green run and two builds from a tree that does not contain the fix.
- **A blank `packages` dispatch input does not build "nothing" — it builds the diff of `HEAD~1` against the tip**, and that diff applies BOTH rules: changed `.spec` files AND the payload globs (`bin/**`, `install/**`, `config/**`, `default/**`, `themes/**`, `shell/**`, `migrations/**`, `applications/**`, `omedora/install/**`, `omedora/install-4.sh`, `omedora/boot.sh`, `version`, `omedora/version` → the self-sourced trio, settings first). A dispatch from a tip whose last commit touched `bin/**` submits `omedora-settings omedora` from THAT tip. Pass an explicit space-separated list whenever you mean a specific package set.
- **Read the submission, not the badge:** `gh run view <run-id> --log` then grep the `Packages to build:` line plus the `==> building <pkg>` / `Created builds: <id>` lines for the build IDs. The ORDER is part of the contract — `omedora-settings` is submitted first because `omedora` Requires it; a reordering is a real finding, not cosmetics. The job can exit `success` in ~30 s while having submitted nothing (token gate absent, or an empty list), so the badge alone proves nothing.
- **Poll build state without copr-cli** (it is not installed here, and an immutable host is not the place to install it) — the token file already on the box works as a bearer for API v3: `curl -s -H "Authorization: Bearer $(grep -oP '^token\s*=\s*\K.*' ~/.config/copr)" 'https://copr.fedorainfracloud.org/api_3/build/list?ownername=<owner>&projectname=<project>&limit=4'` → per build `id`, `state`, `chroots`, `source_package.version`. `api_3/project?ownername=…&projectname=…` answers project existence, chroots, repo URL and `auto_prune`. **Payload shape — normalize it before looping, it is not what you would guess:** the list response is `{"items": [ … ], "meta": …}`, and per build `chroots` yields chroot-name STRINGS (`fedora-44-x86_64`, `fedora-45-x86_64`) when iterated — it is not a list of chroot objects, so `for c in b["chroots"]: c["name"]` raises `TypeError: string indices must be integers, not 'str'` and kills the poll loop mid-flight while every other field looks fine. Do not try to settle the exact shape from the error: normalize once (`names = list(ch) if isinstance(ch, dict) else ch`) and read `id`, `state`, `source_package.{name,version}` and `ended_on` (epoch) directly. `source_package.version` reads `0.3.0~beta.1-1.202611161751git8422056`: the stamp is the build time and the `git<sha>` suffix is the commit the build carried, so one `build/list?…&limit=5` answers "is the repo serving my push, and did the whole package set (`omedora` + `omedora-settings`) reach `succeeded`" without copr-cli or the builds web page. Never echo the token. **Query the API instead of repeating a recorded status** — a note saying a project "does not exist yet" can be stale while the project is live with green builds, and the read costs one call.
- **A payload-only fix needs NO Release bump.** The spec keeps `Release: 1%{?dist}`, yet published packages read `0.3.0~beta.1-1.<date><time>git<sha>` — the source sha is appended at SRPM time, so `rpm -q omedora` on the host distinguishes builds and the NEVRA suffix is the commit marker. Do not invent a version/changelog bump to make two builds distinguishable; do use that suffix (or the built RPM's own payload) when you need to say WHICH commit a deployed host is running.
- **Final proof is the artifact, not the state field.** Three steps, and the middle one has a trap:
  1. Resolve the NEWEST PUBLISHED NEVRA, letting dnf order newness for you — the EVR carries the source sha (`…-1.<stamp>git<sha>`), so the newest line is the newest commit:
     ```bash
     dnf5 --setopt=cachedir=<scratch>/cache \
       --repofrompath=coprverify,https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-<N>-x86_64/ \
       --repo=coprverify repoquery --available --latest-limit=1 \
       --qf '%{name} %{evr} %{location}\n' <pkg> | grep -v '\.src\.rpm$'
     ```
     **Never hand-pick the newest out of `primary.xml`.** A COPR repo accumulates EVERY build of a package, so primary lists many versions and the first `<location>` match is usually an old one (regex scanning it silently "proves" a stale payload while the repo already serves the new one). `--latest-limit=1` + `%{location}` is the fixed shape.
  2. Extract ONLY the file you care about — the omedora payload is ~250 MB, so do not unpack it: `rpm2cpio <rpm> | cpio -i --to-stdout --quiet ./usr/bin/<path>` (normalise a bare path to `./`). Redirect stderr; a missing member prints noise and yields an empty file, which is the failure signal to test for (`[[ -s ]]`), not cpio's exit code.
  3. `diff -u` the shipped file against the committed one (or the built RPM's `rpm -qp --qf` EVR against the sha you pushed) before telling the user the fix is published.
  Probe for all three, stateless and re-runnable: `bash scripts/copr-verify-payload.sh <owner>/<project> <chroot> <pkg> <path-in-rpm> [local-file]`.
  **Pass the member as `./usr/bin/...` (or any form — the script now normalises a
  leading `/`): a bare leading-slash path used to make `cpio` match nothing and
  print a false `MISSING` for a file the package really carries** (measured on
  `omedora` / `./usr/bin/omarchy-theme-set-gnome`). Treat `MISSING` as "check the
  member form and the owning package before believing it".
- **Know which RPM ships a path before verifying it, or the probe prints `MISSING` on a good build** — the self-sourced pair splits by payload, and not the way the names suggest. **`omedora` carries `bin/**`** (so `/usr/bin/omarchy-theme-set-gnome`; the `/usr/share/omarchy/bin/*` twin is a symlink) **and `install/**`** (`%{_datadir}/omarchy/install/` is a directory entry of that same package, so `install/packages/fedora.toml` ships there too); `omedora-settings` carries the settings/theme/first-run payload. Verifying `install/packages/fedora.toml` against `omedora-settings` reports `MISSING`. When unsure, `rpm -qpl <rpm> | grep <basename>` instead of guessing the owner.
- **`dnf5 repoquery` without `--refresh` can serve the PREVIOUS NEVRA for minutes after a build reads `succeeded`, even with a brand-new `--setopt=cachedir`** (measured: `git793fd28` from a fresh cache dir while the API and the published RPM both said `git8422056`). Pass `--refresh` on any query that gates a decision — a stale read here skips a rebuild that was already published.
- **Name the OWNING package before probing — a `MISSING` verdict from the probe means the wrong pair, not a stale build.**
  The payload splits by top-level dir: `bin/**` and everything under `install/**` ship in the
  **`omedora`** package (`omedora.spec`'s `%files` carries `%{_datadir}/omarchy/install/`, which is what
  makes `/usr/share/omarchy/install/packages/fedora.toml` an `omedora` member), while `default/**`,
  `etc/**` and the provisioning files ship in **`omedora-settings`** — probing a map file against
  `omedora-settings` reports it absent from a perfectly good build. Resolve the owner from the spec's
  `%files` (or `rpm -qpl <downloaded>.rpm \| grep <member>`) and pass THAT package. Both packages carry
  the SAME `git<sha>` NEVRA, so a green NEVRA does not vouch for the file: a change spanning both dirs
  needs one `copr-verify-payload.sh` run per package.
- The same shape applies to the image: `podman run --rm <img> rpm -q omedora` and grep the baked script.
- **A `podman run --rm ghcr.io/…:latest …` inspection reads the LOCAL copy first and will happily show you the PREVIOUS build's NEVRA** (0.3 s runtime is the tell — a real pull takes minutes). That reads as "the image CI baked the stale package" when the registry actually has the new one. Before believing a "the fix is not in the image" result, check `podman images --format '{{.Repository}}:{{.Tag}} {{.Created}}'`, then `podman pull ghcr.io/…:latest` (or `--pull=always`) and re-inspect; compare the pulled `.Digest` against `skopeo inspect --no-tags` and the `.Created` timestamp against the CI run. Image digests for the same tag move on every rebuild, so a stale local tag is the normal case on a host that boots the image series.
