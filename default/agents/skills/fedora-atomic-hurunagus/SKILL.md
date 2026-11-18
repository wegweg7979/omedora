---
name: fedora-atomic-hurunagus
description: "Build Fedora atomic desktops: ublue, bluebuild, hyprland"
version: 0.1.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [fedora, atomic, bootc, rpm-ostree, ublue, bluebuild, hyprland, just, github-actions]
    related_skills: [hyprland-config]
---

# Fedora Atomic Desktop Builder Skill

This skill covers the user's (wegweg7979 / hurunagus) workflow:

1. Building declarative, atomic, immutable Fedora desktop images
2. Configuring Hyprland with Omarchy or DMS
3. Automating builds with Just + GitHub Actions
4. Producing bootable disk images with bootc-image-builder

## When to Use

Use this skill when the user asks to:
- Build a Fedora atomic/immutable desktop image with ublue or bluebuild
- Configure Hyprland with Omarchy or DMS
- Set up `ujust`/`just` build automation and GitHub Actions CI
- Replace the Arch/pacman Omarchy updater on Fedora (see `references/omarchy-update.sh`)
- Capture the user's own desktop config off a running box and ship it as a user-invoked reapply command ("like `omarchy-reinstall-configs` but for hurunagus settings") — see `references/user-config-delta-capture.md`
- Rebrand a forked third-party app (`wegweg7979/<app>`) and bake it into the image — see `references/rebranding-a-forked-app.md`
- Make a doc or agent skill the image SHIPS to coding agents correct for the immutable Fedora base ("the omarchy skill should ship modified for hurunagus") — see `references/agent-skill-payload.md`
- Rebase an atomic Fedora image to a new build

## References

**Body vs references (keep this ratio).** This body carries only the always-on orientation, workflow and rules; topic depth lives in `references/`. When a body section grows past ~2-3 KB — or whenever you learn something long while working — move the whole section into the matching reference (or a new `references/<topic>.md`), leave a one-line `→ Moved to …` stub in its place, and add/extend the bullet here. Never leave long material in the body and never drop it.

- `references/pitfalls.md` — **load before touching tests, migrations, kernels, packages or the distro token**: the long half of the pitfalls summary (items 9-15) with exact commands, measured numbers and reasoning; SKILL.md keeps the one-line rules 1-8 plus an index.
- `references/omarchy-update.sh` — custom `omarchy-update` script (the RUNNER) for Fedora/rpm-ostree (runs `ujust update` instead of the Arch pacman flow)
- `references/update-notification.md` — reworking the bar's update NOTIFICATION (the CHECKER: `omarchy-update-available` / `fedora/update-available`) for immutable bootc — staged-deployment / skopeo digest checks vs the mutable dnf check Also absorbs SKILL.md's *Omarchy updater override* section.
- `references/copr-app-publishing.md` — publishing a standalone app (the user's own repo, not the omedora fork) to its own COPR: API-v3 auth, project/SCM/package/build endpoints, the webhook, the RPM URL from repodata, and the spec's container-build verification.
- `references/rebranding-a-forked-app.md` — **load before planning any "rebrand/app-ify this fork" task**: the read-only recon (fork-vs-upstream compare, upstream `distro/fedora/*.spec` as a spec to derive from, upstream COPR as proof the path works), the two option-killing traps (baked third-party OAuth credentials are NOT licensed for forks; never rename the app's config/data/state namespace when the user's db/keyring already live there), the token census + rename tiers, the app-naming convention (flat `Name=/Exec=/Icon=<app>.desktop`, airgraph precedent), the delivery options with their real Qt-ABI cost, the daemon/autostart/menu seams, and the Dux Labs stack anatomy (Go daemon + `go:embed` QML + dlopen'd `libdux-qt-base.so.0` Quickshell fork + `dux-repo` specs).
- `references/omedora-copr.md` — what the `agaspar/omedora-4` COPR owns (Hyprland binaries vs vendorable Omarchy configs vs droppable XR stack) and how to answer "can I remove the 3rd-party repo?" Defines the split: settings bake into `system_files/`, Hyprland binaries cannot be dropped without sourcing from a COPR you control. Also absorbs SKILL.md's *COPR ownership* and *COPR build gotchas* sections, and carries **which commit a build can actually carry** (only one that exists on the remote) plus how to read a submission and poll build state without copr-cli. Probe: `bash scripts/copr-verify-payload.sh`.
- `references/project-map.md` — **load this first on any hurunagus/omedora task**: what omedora vs hurunagus vs hurubase mean, the disk layout of the four working checkouts, the `/usr`-is-read-only editing rule, the ssh-alias host inventory (workstation = this host, monitor layout, the remote-reboot block), the `wegweg7979/omedora-4` COPR ownership/dispatch rules, and hurubase's address-as-interface + controlling-terminal requirement.
- `references/omedora-immutable-port.md` — porting the Omedora/Omarchy command SUITE itself to immutable bootc: the `fedora-ostree` third-distro-token design, the `${VAR+x}`-vs-`:-` empty-flag trap, the ostree dev-host test trap, thematically pruning the menu when deleting commands, and the CLI metadata gate churn after deletions Also absorbs SKILL.md's *omedora fork == immutable* section.
- `references/justfile-recipes.md` — key Just build recipes
- `references/byte-identity-audit.md` — **load before touching an upstream-owned omedora file, or when asking "is the port still additive-only?"**: the audit SKIPS with an `ok` when the pin tag is absent (the tag lives in the PARENT repo, so a normal clone AND the L1 CI job both skip it — a green run proves nothing), the read-only `git fetch --depth=1` that makes it real, why `OMEDORA_BASE_TAG=HEAD` is the fast loop and what it cannot tell you (it diffs your change against your own last commit), the measured state (128 files with undocumented deletions: 118 pruned command families + 10 edited in place), and the ALLOW-vs-CARRIED authoring rules with the exact-line and quoting traps. Also covers retiring an upstream FILE as a documented divergence.
- `references/gtk-dark-theming-fedora.md` — **load when the user reports light dialog boxes / light GTK apps on a hurunagus box**: omedora's `omarchy-theme-set-gnome` sets dconf `gtk-theme=Adwaita-dark`, which GTK 3.24 cannot resolve as a theme name (it derives `Adwaita-dark-dark` and silently falls back to LIGHT Adwaita) while GTK4/libadwaita stays dark; dconf's key overrides the `gtk-3.0/settings.ini` value, reading `gtk-theme-name` off `Gtk.Settings` proves nothing, and the same name leaks into Flatpaks via xdg-desktop-portal-gtk and into Qt via `QT_QPA_PLATFORMTHEME=gtk3`. Carries the offscreen-pixel verification probe, the `theme-set.d` hook that re-asserts `Adwaita` + `prefer-dark` after every theme switch (theme hooks run AFTER `omarchy-theme-set-gnome`), and the repo-side fix for a future image build.
- `references/agents-skills-shipping.md` — **load before editing anything under an omedora checkout's `default/agents/skills/`**: those files ship via the `omedora-settings` RPM and `omarchy-provision-user` symlinks them into six agent skill dirs on every hurunagus host, so the skill text is what agents actually follow; the byte-identity additive-only rule for upstream files (and how to generate the `ALLOW` blob from `git diff` when the pin tag is absent and the audit self-skips), why a wrong upstream line must be replaced in place rather than corrected in an appended section, the three per-distro commands an Arch-only skill always gets wrong, and the static L1 gate + explicit CI step pattern that stops a rebase from reverting it.
- `references/github-actions.md` — GitHub Actions CI/CD workflow patterns: the image repos' two-workflow split, plus CI for a repo that is NOT an image build (lint + test jobs, action SHA pinning, running shellcheck locally before CI sees it) Also absorbs SKILL.md's *GitHub Actions patterns* section.
- `references/kernel-swap-and-omarchy-kernel.md` — swapping a custom kernel into an atomic image (the proven silverblue custom-kernel module mechanics to port into build.sh) + building the Omarchy `linux-omarchy` kernel for Fedora (Arch-only source, no existing Fedora RPM, COPR spec/plan) + where the user's repos live on disk.
- `references/secure-boot-signing.md` — **load before signing a custom kernel, promising Secure Boot support, or verifying a signed kernel**: what the chain actually requires on this image family (measured: shim is MS-signed and embeds `fedoraca`, Fedora's grub is dual-signed incl. a `fedoraca` signature, grub carries the `shim_lock` verifier, the CachyOS vmlinuz had no signature table, modules are already signed by the kernel's build-time key), the own-key + committed-cert + enroll-helper design, the traps (a build secret is invisible to the layer cache so signing needs its own layer; secrets vs build args; `podman run --secret` syntax differs from build's; SELinux blocks `$HOME` bind mounts), the per-machine MOK enrollment order, and the OVMF mini-rig that proves accept/refuse without hardware. Probes: `scripts/sb-rig-mk-esp.sh`, `scripts/sb-rig-run-vm.sh`.
- `references/user-config-delta-capture.md` — capturing the user's OWN look-and-feel/shell changes off a live box into a reapplyable image payload: baselines to diff against, the classification traps (upstream version drift, theme-generated files in `~/.config`, "absent from `/etc/skel`" ≠ "not a setting"), the agreed delivery shape, and **keeping the payload current across upstream major bumps** (migrations rewrite only the `$HOME` copy; replay only ever writes and never deletes). Probe: `scripts/config-delta.py`. Also absorbs SKILL.md's *Harvesting the user's own config onto the image* and *Hurunagus look-and-feel payload* sections.
- `references/btrfs-maintenance.md` — scheduled btrfs maintenance IN the image: why `btrfsmaintenance`'s stock defaults silently no-op on a composefs root, the `/etc/default/` override seam, how the job timers' schedules get generated (and how to switch a job off), and the post-deploy checks. Never ship the package without the override file.
- `references/build-times-and-layer-cache.md` — where a 20-30 minute image build's minutes actually go (the per-step timing command, ublue vs bluebuild anatomy), why `just ostree-rechunk` is ~10 minutes of optional work, the volatility-staged Containerfile + phased `build.sh` pattern with per-stage ARG cache-busts, the CI-cache caveat, and the checks that prove a restructure without a full build. Also absorbs SKILL.md's *Build time: measure, then stage the layers* section.
- `references/omedora-upstream-sync.md` — keeping the fork current: the read-only survey procedure, the measurement traps (a display-captured `git diff --name-only` listing TRUNCATES and silently undercounts — the both-sides figure is 828, not 357; never fan parallel git calls at one clone, they race on `index.lock`), the merge-vs-re-port decision rule with the measured 4.5 numbers (179 conflicts / 2-of-9 clean cherry-picks), the per-phase re-port procedure, per-file porting rules, the **dispatch sweep** (every `case … fedora)` arm that falls through to pacman, every `== "fedora"` check that silently skips Fedora-isms, with route-vs-refuse verdicts), the resume point of the `omedora-4.5` branch, and the side-branch push check (which workflows fire on a branch that is not `omedora-4`, and which of them have live side effects). Probes: `scripts/upstream-delta-report.py`, `scripts/distro-dispatch-sweep.py`.
- `references/hurubase.md` — the `hurubase` cross-DE/DM rebase helper as a shipped tool: the interactive checklist, `/var/lib/hurubase/state`, the prompt / `HURUBASE_ANSWERS` mechanics, and the mock+real test seam.
- `references/rclone-cloud-mounts.md` — cloud drives in Nautilus: why GNOME Online Accounts can no longer do Google Drive (no `gvfsd-google`, no `libgdata` in F45) and never could do iCloud, the plain-Fedora `rclone` package + image block, the extract-the-RPM-and-run-it proof (remote + `Type=notify` mount verified before any image build), the verified systemd user units and `gtk-3.0/bookmarks` sidebar pin, the shared-Google-client_id retirement and the iCloud trust-token login, and how to diagnose a past "rclone didn't work" attempt from shell history. Load this when the user asks to mount cloud storage on the desktop.
- `references/icloud-suite-port.md` — porting **icloud-for-omarchy** (the Rust/GTK4/Qt6 iCloud suite: Drive sync, Photos app, shared sign-in) to Fedora: why it beats the rclone mounts it sits beside, the phase-0 container compile proof and the crate-name trap, the Arch→Fedora dependency adaptations (`org.freedesktop.secrets` → `gnome-keyring`; system SQLite, not the bundled amalgamation), the measured no-op of `%global debug_package %{nil}` on Rust, the four-package spec layout, the `dnf5 builddep` verification recipe, and the COPR settings incl. `enable_net: true`. Load this when touching the iCloud suite, its packaging repo or its COPR.
- `references/zig-app-packaging.md` — **load before porting/packaging any Zig app** (hyprglaze and friends): the verified Fedora 45 container build recipe, the `zig 0.16-vs-0.17` toolchain gap that forces shipping the compiler, the devel-package equivalences (`libglvnd-devel` also covers EGL+GLESv2, no `mesa-libGLES-devel` in F45, `stb-devel` path, `hyprland-bin` vs the nonexistent `hyprland` package), `%{_userunitdir}` for user units, and the Lua-watcher / omarchy.background-layer integration checks. Also carries the app's **enable/disable contract** (the injected Lua watcher is dropped only by a config reload, and the wallpaper revert is pixel-exact because the daemon draws *over* Omarchy's own background surface) and its **settings surface** — one optional TOML that hot-reloads, whose `effect`/`music` keys have no upstream writer. Load it before building anything that toggles or configures such an app. Probe: `scripts/hyprland-ipc-events.py`.
- `references/huru-calendar.md` — the user's iCloud calendar stack (`~/huru-calendar`, fork of Dux Calendar) as **headless Go daemon + Omarchy bar widget**, not a repackaged app: why the engine is reused and the UI replaced, the verified IPC/JSON surface (incl. `subscribe` topics and `tasks.*` for iCloud Reminders), the rebrand conventions that must NOT change (`dankcal` namespace, `DANKCAL_*`, module path), the OAuth-credentials licence trap that forces blanking them, the word-boundary rewrite rule for `dcal` → `hcal`, the podman verification recipe, and the remaining spec/COPR/plugin/image phases.
- `references/cloud-storage-mounts.md` — **load before promising a cloud drive in the file manager** ("can I mount Google Drive / iCloud in Nautilus?"): the probe that shows which cloud backends this gvfs/GOA build actually ships (Google Drive is NOT one of them — no `gvfsd-google`, no `libgdata` in any repo; iCloud never had a provider and has no file-level WebDAV), rclone as the delivery route (Fedora-repo package, backends verified by extracting the RPM, `drive` + `iclouddrive` confirmed present), the per-user systemd-unit + Nautilus-bookmark shape, the hard secrets rule for `rclone.conf`, the failure modes visible in the user's own shell history, and the `git log -S` false positive that hides where a removed package really lived.
- `references/agent-skill-payload.md` — **load before editing any doc or agent skill the image delivers** (`/usr/share/omarchy/default/agents/skills/*`): the provenance chain (omedora `default/agents/skills/<name>/` → the `omedora-settings` RPM → `omarchy-provision-user` symlinks into ~/.agents, ~/.claude, ~/.codex, ~/.pi/agent, ~/.gemini/config and ~/.hermes/skills, so this agent's own `omarchy` skill IS the installed copy), the single edit location, the two constraints that shape the edit (the same RPM also serves mutable Fedora hosts, so write an `omarchy-distro` delta; byte-identity is additive-only with per-file ALLOW entries), the live route probes that beat reading the fork's intent (`OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <pkg>`, `omarchy commands --json`, `omarchy-distro`, `rpm -q`), the claim classes the fork's shipped skill gets wrong on the immutable base, and the COPR-gated delivery cost.
- `references/package-trimming.md` — **load before dropping anything from the bake set**: the seam decision (`EXCLUDED_PACKAGES` vs a `fedora.toml` `skip` entry, and why the wrong one aborts the migration queue), verifying against the RESOLVER output instead of the list text, keeping the vendored `build_files/fedora.toml` byte-identical, gating the menu row and appending into the SAME byte-identity ALLOW blob, size / `--whatrecommends` evidence for candidates, the `install_weak_deps=False` hammer with its `iw` and `glibc-langpack-en` caveats, what a trim does NOT do (no live uninstall), and the keep-list (`herdr`, fcitx5 core, podman).

## The user's 7 repos

| Repo | Purpose |
|------|---------|
| hurunagus-silverblue | Fedora Silverblue + Niri + DMS (BlueBuild template). **Carries the reusable kernel-swap module** (`modules/custom-kernel/`) — the proven pattern for swapping kernels into an atomic image. |
| hurunagus-ublue | Fedora U_blue + Niri + DMS (ublue-os/image-template) |
| hurunagus-hyprland | THE active Hyprland + Omarchy bootc image. TWO clones exist on disk: the working copy is `~/hurunagus-hyprland` (remote `github.com/wegweg7979/hurunagus-hyprland.git`); `~/Documents/GitHub/hurunagus-hyprland` is an OLDER clone of remote `hurunagus-hyprland2.git` with a dirty tree — do not edit it by accident. Confirm with `git -C <dir> remote -v` and let the user name the folder before starting; API/URL queries against `...hurunagus-hyprland2` return empty. Fastest confirmation of all: match `git -C <dir> log -1 --format=%h` against the running host's booted deployment tag (`rpm-ostree status` reports `latest.<date>-<sha>`) — the checkout whose HEAD sha equals that tag built this box. This repo intentionally has NO agent-instructions file (the original scaffolding note was deleted as out of date): conventions live in THIS skill, not in the repo. |
| hurunagus-hyprland-dms | Hyprland + DMS + Lua dynamic modules |
| hurunagus-umbriel | Hyprland variant (Just-based) |
| hurunagus-dank | Shell scripts repo |

## Build infrastructure: ublue vs bluebuild

### ublue-os/image-template

- **Structure:** `Containerfile` + `Justfile` + `image-template.env`
- **Containerfile:** Uses multi-stage build with `FROM scratch AS ctx` to mount `build_files/` and `system_files/` into the image context. Runs `build.sh` as the main build script.
- **Justfile:** Contains recipes for building images, disk images, ISOs, and VMs. Key recipes:
  - `build` - builds the container image with proper OCI labels
  - `build-qcow2` / `build-raw` / `build-iso` - builds disk images via bootc-image-builder
  - `rebuild-qcow2` / `rebuild-raw` / `rebuild-iso` - rebuilds disk images
  - `run-vm-qcow2` / `run-vm-raw` / `run-vm-iso` - runs VMs in podman
  - `ostree-rechunk` / `rechunk` - creates smaller delta updates
  - `tag-images` - tags the image with multiple tags
  - `lint` / `format` - shellcheck and shfmt for bash scripts
- **image-template.env:** Defines environment variables used by the Justfile:
  - `IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC`, `IMAGE_KEYWORDS`, `IMAGE_LOGO_URL`, `DEFAULT_TAG`, `BIB_IMAGE`
- **disk_config/:** Contains TOML configs for bootc-image-builder:
  - `disk.toml` - for qcow2/raw disk images
  - `iso-gnome.toml` - for ISO builds
  - `iso-kde.toml` - for KDE ISOs
- **Build process:**
  1. `just build` - podman builds the container image from Containerfile
  2. `just _build-bib` - podman runs bootc-image-builder with the image and disk config
  3. Output goes to `output/` directory

### blue-build/template

- **Structure:** `recipe.yml` + `modules/` + `files/` + `recipes/`
- **recipe.yml:** YAML-based build definition:
  - `base-image: ghcr.io/ublue-os/silverblue-main` - the base image
  - `image-version` - Fedora version (e.g., 44)
  - `modules:` - ordered modules that modify the image:
    - `type: fonts` - installs custom fonts (google-fonts, etc.)
    - `type: gnome-extensions` - installs GNOME extensions
    - `type: files` - copies files into the image root
    - `type: dnf` - installs RPM packages from repos/coprs
    - `type: gschema-overrides` - applies GSettings overrides
    - `type: default-flatpaks` - installs Flatpak packages (system and user)
    - `type: signing` - sets up signature policies for signed images
    - `type: script` - runs custom scripts during build
    - `type: os-release` - customizes /usr/lib/os-release
- **modules/:** Directory for custom modules (empty by default, uses built-in modules)
- **files/:** Contains files to copy into the image:
  - `files/system/etc/` - system config files
  - `files/system/usr/` - system files
- **recipes/:** Contains recipe.yml template
- **Rebase commands:**
  ```bash
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/blue-build/template:latest
  systemctl reboot
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/blue-build/template:latest
  systemctl reboot
  ```

## Build time: measure, then stage the layers

→ Moved to `references/build-times-and-layer-cache.md` — where the 20-30 min build actually goes, the volatility-staged Containerfile + phased `build.sh` pattern, and the checks that prove a restructure without a full build. Load that file when working on this.

## bootc-image-builder (BIB)

- **What it does:** Converts a container image into a bootable disk image (qcow2, raw, iso, vmdk)
- **Usage in user repos:**
  - `just _build-bib <target_image> <tag> <type> <config>`
  - Runs as `podman run --rm --privileged --net=host` with:
    - Config mounted as `/config.toml`
    - Output mounted as `/output`
    - Host storage mounted: `-v /var/lib/containers/storage:/var/lib/containers/storage`
  - Args: `--type <type> --use-librepo=True --rootfs=btrfs`
- **disk_config/ files:**
  - `disk.toml` - qcow2/raw disk image config (mountpoint, minsize, kickstart)
  - `iso-gnome.toml` - ISO config
  - `iso-kde.toml` - KDE ISO config
- **Rebuilding:** Use `just rebuild-qcow2` etc. which combines `build` and `_build-bib`

## rpm-ostree and atomic updates

- **Concept:** Fedora atomic desktops use rpm-ostree for immutable OS updates
- **Rebase workflow:**
  1. `rpm-ostree rebase ostree-unverified-registry:<image>:<tag>` - rebase to unsigned image
  2. `systemctl reboot` - complete the rebase
  3. `rpm-ostree rebase ostree-image-signed:docker://<image>:<tag>` - switch to signed image
  4. `systemctl reboot` - complete installation
- **Chunking:** Use `rpm-ostree compose build-chunked-oci` for smaller delta updates (replaces `rechunk` in the Justfile)
- **Key packages:**
  - `rpm-ostree`, `bootc`, `fedora-bootc` (base image)
  - `osbuild`, `osbuild-contrib` (for ISO generation)

## Just build automation

- **Key recipes to know:**
  - `build` - build container image
  - `build-qcow2`, `build-raw`, `build-iso` - build disk images
  - `rebuild-qcow2`, `rebuild-raw`, `rebuild-iso` - rebuild disk images
  - `run-vm-qcow2`, `run-vm-raw`, `run-vm-iso` - run VMs
  - `ostree-rechunk`, `rechunk` - create smaller delta updates
  - `tag-images <target> <tag> <tags>` - create multiple tags
  - `generate-default-tag`, `generate-build-tags` - generate tags
  - `check` / `fix` - syntax check/fix Justfiles
  - `clean` - clean build artifacts
- **GitHub Actions CI/CD:**
  - `build.yml`: Builds container image on push/PR/schedule (cron: 00 06 * * 2 = Tuesday 06:00 UTC)
  - `build-disk.yml`: Builds disk images on PR with disk_config changes, or manual dispatch
  - `just` installation: `extractions/setup-just@53165ef7e734c5c07cb06b3c8e7b647c5aa16db3` (v4.0.0)
  - Image pushed to: `ghcr.io/<owner>/<repo>:<tag>`
  - Optional: chunkah rechunking for smaller deltas

## Containerfile build quirks (ublue base)

**`FROM scratch AS ctx` has no `/bin/sh`.** The ctx stage is a `scratch` image, which contains no shell at all. Any `RUN` in the ctx stage fails with `error: executable file not found` or `Permission denied`. **Fix:** do not run scripts in the ctx stage — copy files only, and do any permissions or transformations in the main image stage instead.

**`COPY build_files /` copies the CONTENTS of `build_files` to the image root**, not the directory itself. So `build.sh` (inside `build_files/`) ends up at `/build.sh` in the ctx stage, not `/build_files/build.sh`. The main-stage RUN command references `/ctx/build.sh` (which resolves to the root of the ctx stage). **Gotcha:** do not be tempted to reference `/ctx/build_files/build.sh` — that path does not exist.

**`--mount=type=bind,from=ctx,source=/,target=/ctx` does NOT work in this Podman version.** The `type=bind` form silently fails. **Use** `--mount=from=ctx,source=/,target=/ctx` (without `type=bind`).

**The ublue base image ships `/usr/local` as a symlink to `/var/usrlocal`.** `/usr/local/bin` is NOT a real directory. A command like `mkdir -p /usr/local/bin` fails with `cannot create directory '/usr/local': File exists`. **Fix:** create `/var/usrlocal/bin` directly (the real target of the symlink), or use the full real path `/var/usrlocal/bin/<script>` in `install` commands.

## Hyprland configuration (see also: hyprland-config skill)

The user has two main patterns:

### Pattern 1: Lua-based Hyprland config (dms)

- Uses `hl.config({})`, `hl.monitor({})`, `hl.bind()`, `hl.env()`, etc.
- Files: `hyprland.lua`, `monitors.lua`, `bindings.lua`, `input.lua`, `looknfeel.lua`, `autostart.lua`
- Lua API:
  - `hl.config({ general = { gaps_in = 5, gaps_out = 20, border_size = 2, layout = "dwindle" } })`
  - `hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "1920x0", scale = "auto" })`
  - `hl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"))`
  - `hl.env("XCURSOR_SIZE", "24")`
  - `hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })`
  - `hl.window_rule({ name = "no-gaps", match = { float = false, workspace = "w[tv1]" }, border_size = 0 })`
  - `hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })`
- Layouts: `dwindle` (default), `master`, `scrolling`

### Pattern 2: Omarchy dotfiles (hyprland2)

- Uses `dofile(...bootstrap.lua)` and `require(...)` for config modules
- Omarchy provides `o.bind()`, `o.launch_on_start()`, `o.window()` helpers
- Uses dynamic module system with `hl.lua` config

## GSchema overrides

- Location: `gschema-overrides/zz0-<name>.gschema.override`
- Format: GNOME GSettings schema overrides
- Examples from user repos:
  ```ini
  [org.gnome.desktop.interface]
  accent-color='purple'
  color-scheme='prefer-dark'
  [org.gnome.desktop.wm.preferences]
  button-layout=':minimize,maximize,close'
  [org.gnome.desktop.background]
  picture-uri='file:///usr/share/backgrounds/hurunagus/leaf.jpg'
  [org.gnome.shell]
  enabled-extensions=['<email>', 'blur-my-shell@aunetx']
  ```

## System files and first-boot services

- **system_files/**: Copied to `/` during build via `cp -avf /ctx/system_files/. /`
- **add-default-user-groups.service**: Enables default user groups
- **flatpak-system-install.service**: Installs system Flatpaks from `system-flatpaks.list`
- **SDDM theming:**
  - Custom SDDM theme in `/usr/share/sddm/themes/omarchy`
  - Mirrored to `/usr/share/omarchy/default/sddm/omarchy` for `omarchy-refresh-sddm`
  - Custom greeter: `dms-greeter` from COPR
- **Wayland sessions:**
  - Remove base-image session entries: `omedora.desktop`, `hyprland.desktop`, `hyprland-uwsm.desktop`
  - Enable SDDM: `systemctl enable sddm.service`

## build.sh patterns

- Install build tooling: `dnf5 install -y dnf5-plugins python3`
- Enable COPR repos: `dnf5 -y copr enable <owner>/<repo>`
- Install packages: `dnf5 -y install <packages>`
- Disable COPR after install: `dnf5 -y copr disable <owner>/<repo>`

### The `omedora` COPR dependency (hurunagus-hyprland2)

The Hyprland desktop is built almost entirely from `agaspar/omedora-4`
(`dnf5 -y copr enable agaspar/omedora-4`, then `omedora omedora-settings`).
Hyprland is **not in Fedora's official repos**, so this image cannot drop the
COPR without either source-compiling the whole Hyprland lib chain in the
Containerfile (fragile) or switching to another maintainer's COPR (still
external). The *Omarchy configs/dotfiles/SDDM theme* the COPR ships, by contrast,
copy straight into `system_files/` and need no package. See
`references/omedora-copr.md` for the full package split and the verdict
framework for "can I remove the 3rd-party repo?".

- **Always `chmod +x` shell scripts in the repo** before committing (`chmod +x build_files/*.sh system_files/usr/libexec/*.sh`). git preserves the executable bit on commit; if a script is not executable, the container build fails with `Permission denied` when it tries to execute it.
- **Before enabling a systemd service, guard it:** services that are not present in the ublue base image (e.g., `flatpak-system-install.service`) cause the build to fail with `Failed to enable unit: Unit X.service does not exist`. Check first:
  ```bash
  if systemctl cat flatpak-system-install.service >/dev/null 2>&1; then
      systemctl enable flatpak-system-install.service
  fi
  ```

## Running plan-then-prompt with this user (design + scope decisions)

Big infra/build work is **plan → STOP → go**, and for THIS user the plan travels
as chat prose, never as a question form:

- Deliver the plan as compact prose plus a table of the decision points, each with a
  marked recommended default ("my defaults unless you say otherwise: …"), then stop.
  Do NOT open a multi-question `clarify` form for design decisions — the user steers in
  short fragments instead ("X is dead", "Y is to become the flagship", "we should not
  support Z"), and a blocking form goes unanswered while the plan rots.
- Expect SCOPE PRUNING as the main feedback loop: rows and options get deleted one message
  at a time. After every correction, restate the whole plan compactly with the pruned
  table — that restatement is how they check you tracked all of it.
- Turn each prune into the artifact immediately (table row, refusal list, README) and say
  what it changed ("dropped; `*-nvidia*` refs are now refused, not warned about"), instead
  of just acknowledging it.
- Say what the change does NOT touch (which repo, which live system). By default the user
  runs the build, the push and the rebase; when they hand one over ("push to github
  please"), do it and prove it from the remote rather than restating the command.
- On "go", the deliverable is the working artifact plus real tool output proving it — not
  a description of one, and not a replay of the process.
- **While executing a phased plan, decide by default and ask only about what changes the NEXT step.**
  Take the recommendation you marked for any decision the current phase does not touch, say which
  defaults you took and which you deliberately held back (with the reason), and keep going. Holding
  a phase on a decision it does not depend on spends the user's attention for nothing; they confirm
  with a one-liner once the recommendation is in front of them.
- **When they ask "what do you need to know from me?", answer with a short NUMBERED list of blocking
  questions** (three is plenty), one line each, each answerable in a word, with your recommendation
  attached — plus one line naming what is deferred and to which phase. Do not re-dump the plan and
  do not re-ask anything already answered.

## Adding a package or service to the image

When the user says "we should add X to the image", the deliverable is an item-by-item
plan (file, line range, one-line reason each) with **no edits until they say go** — this
user runs the build and the push themselves; the agent drafts and verifies. Establish
these facts read-only first:

1. **Availability + release.** `dnf5 repoquery --available --qf '%{name} %{evr} [%{reponame}]' <pkg>` on the running host (its repos mirror the image's). Confirm the release with `rpm -E %fedora` — NOT the release the Containerfile comment claims, since `base-main:latest` moves.
   - **For a package that lives in a COPR the host does NOT have enabled, query the repo ad hoc — never `copr enable` it to look:** `copr enable` writes `/etc/yum.repos.d` on a box whose `/usr` is read-only and whose repo list is part of the delivered state. Use a throwaway repo + cache instead:
     ```bash
     dnf5 --setopt=cachedir=<scratch>/dnfcache \
       --repofrompath=<name>,https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-<N>-x86_64/ \
       --repo=<name> repoquery --available --qf '%{name} %{evr}\n' <pkg>
     ```
     Nothing lands outside the scratch cache, and a hit proves the repo metadata is live (not just that a build once succeeded).
   - **Check the package's RUNTIME deps against the running host before proposing the install** — the host is the same image family, so one `rpm -q` loop is the cheapest proof they are already satisfied: `for p in <Requires…>; do printf '%s %s\n' "$p" "$(rpm -q --qf '%{VERSION}-%{RELEASE}' $p 2>/dev/null || echo MISSING)"; done`. A missing **`Recommends`** (a weak dep, e.g. `iw` for a Wi-Fi tool) is NOT a blocker: dnf5 pulls weak deps by default when a repo offers them.
   - **An app's own COPR is enabled only long enough to install from it:** `dnf5 -y copr enable <owner>/<app>` → install → `dnf5 -y copr disable <owner>/<app>`. Only the omedora COPR stays enabled, because its package helpers consume it at runtime; nothing consumes an app repo on demand once the app is baked in. Locate the insertion point in the app-install region of `build_files/build.sh` (next to the brave / cliamp / hermes-desktop blocks), not in the resolved Omarchy package lists — those are synced from the fork and would revert the addition.
   - **Decide the app repo's `auto_prune` deliberately.** `api_3/project?ownername=…&projectname=…` answers it, and with `auto_prune: true` COPR eventually prunes the RPM out of the repo. An UNGUARDED `dnf5 install -y <app>` then fails the whole image build — including the weekly scheduled run — while a guarded install (warning-and-continue, like the hermes-desktop / cliamp blocks) ships an image that quietly lacks the app. Default to the unguarded install, because a missing app should be loud, and turn auto-prune off for that project; only guard it if the user prefers a build that survives a dead repo.
   - **When they say the package "used to be in the image and I removed it", find the removal before planning — and expect the reason to be elsewhere.** A `-S <pkg>` hit in the flagship repo is often a false positive (`hurunagus-hyprland`'s only `rclone` match is `.github/workflows/build-disk.yml`, CI installing it on the RUNNER to upload disk images to S3), the real history is usually in a sibling line (bluebuild `recipes/recipe.yml` `dnf: packages:` vs ublue/bootc `build_files/build.sh`), a commented-out entry is what "removed" looks like, and the removal commit rarely says why. Read the user's shell history for the actual failure (`grep -h <pkg> ~/.bash_history ~/.zsh_history`) — that is where the diagnosis lives, and it usually is NOT the package's fault.
2. **Read the RPM without installing it.** `dnf5 repoquery --location <pkg>` → `curl -O` into the scratch dir → `rpm2cpio <pkg>.rpm | cpio -idm` to extract; `rpm -qpl` / `rpm -qp --scripts` for files and scriptlets. Read the shipped unit files, config template and job scripts. This is the step that catches a package whose defaults cannot work on this image.
   - **Then RUN it from the extracted tree whenever the package's value is behavioural** — a viewer, a CLI or a mount helper usually starts straight from the scratch dir against the user's real config and files, which answers "is this actually useful here?" with nothing installed and no rebuild. This user asks for it by name ("lets test it in a scratch dir") before agreeing to bake something in, and it is far cheaper than a 20-30 minute image build. When `ldd <binary>` reports a missing library, fetch the providing package the same way (`dnf5 repoquery --available --whatprovides 'libX.so.N()(64bit)' --qf '%{name}'`) and put its extracted `usr/lib64` on `LD_LIBRARY_PATH` — do NOT conclude the package cannot be tested. Launch it on the live session with `scripts/wayland-env.sh` and verify from pixels (see §"Driving the live desktop from an agent shell").
3. **Do its defaults even fire here?** Check the tool's default target against the real fstype: `stat -f --format=%T /` is `overlayfs` (composefs) while `/var`, `/etc`, `/sysroot`, `/var/home` are btrfs subvolumes of ONE device. A tool defaulting to `/` will no-op **and exit 0**, so it reads as success. Pick the replacement path from `findmnt --types btrfs` rather than assuming.
4. **Find the override seam.** Sysconfig-era packages source `/etc/sysconfig/<name>` and then `/etc/default/<name>` — the LAST one wins, so ship your own `/etc/default/<name>` from `system_files/` and leave the rpm-owned file pristine. Plain systemd packages want a `.d/` drop-in or a preset.
5. **Enumerate the enabling step separately from the install.** `systemctl` calls made by a package's own refresh script are silenced inside a container build, so scriptlet-generated schedules (timer drop-ins) do not exist yet: run the package's generator once at build time AND enable the unit explicitly through the guarded `enable_unit` wrapper.
6. **State what you are deliberately NOT adding** and why (extra timers the package drags in), plus the post-deploy verification commands.

Worked example with the full config table, the generated-schedule mechanics and the
checks: `references/btrfs-maintenance.md`. When the package's whole point is a
FILE-MANAGER mount (cloud drives, sync clients), the verdict, the probe and the mount
shape are in `references/cloud-storage-mounts.md`.

## Removing a package from the image

Same discipline as adding, with one extra decision — the seam. The bake set is
`omarchy-base.packages` + `fedora-baseline.packages` resolved through
`fedora.toml`, then filtered by `EXCLUDED_PACKAGES`. Choose by who ADDS the
package: nothing at runtime → an `EXCLUDED_PACKAGES` line in `build_files/build.sh`
(match the RESOLVER's RPM names, not the Arch list's); a migration, menu
installer or `setup` command that calls `omarchy-pkg-add <name>` → a
`source = "skip"` entry in `install/packages/fedora.toml`, because a skip `add`
exits 0 while an unmapped, not-baked `add` exits 1 and aborts the whole migration
queue. Verify against the resolver output (excluded names still appear there — the
filter is shell-side), gate the user-facing menu row with
`"when":"omarchy-cmd-present <cmd>"`, and say plainly that a trim never uninstalls
anything from the running host. Procedure, dependency tracing, the weak-dep lever
and the keep-list: `references/package-trimming.md`.

### When "add X" is really "rebrand this fork of X"

Three rules that apply to every forked-app adoption, before any plan is written —
the full procedure is `references/rebranding-a-forked-app.md`:

1. **Recon read-only first**: `gh repo view <fork> --json parent` + the upstream
tree + `distro/fedora/*.spec` if the upstream org ships one. Never clone and grep
the tree before you know the token surface.
2. **Check the licence for baked third-party credentials** (OAuth client IDs).
They are normally licensed to the upstream app only — a rebrand strips them or the
user registers their own; never bake upstream's into a renamed build.
3. **Never rename the app's config/data/state namespace** if the user's db,
keyring or settings already live under it (`ls ~/.config/<name> ~/.local/share/<name>`).
Say so explicitly in the plan — it can flip a decision the user was about to make.

## GitHub Actions patterns

→ Moved to `references/github-actions.md` — the image repos' two-workflow split, plus how to read the logs of an IN-PROGRESS run. Load that file when working on this.

## User doc/book-writing preference

Fork READMEs and the repos' public docs must be CONCISE for GitHub — a short lead (what it is, why it exists), a few crisp bullets for what's different, and pointers. The user explicitly rejected an exhaustive, everything-documented draft as "too detailed for github" and prefers to rewrite from the concise upstream README. Do not dump the full technical inventory into a README; the deep detail lives in this skill and `references/`, and the README points elsewhere (e.g. `omedora/README.md`). When asked to "draft a README" for a fork, start lean and expect the user to want a simpler cut than the complete analysis.

## omedora fork == immutable (2026-11)

→ Moved to `references/omedora-immutable-port.md` — the canonical Omedora-to-immutable adaptation: what changed, the `fedora-ostree` token, the pruning rules. Load that file when working on this.

## COPR ownership (2026-11)

→ Moved to `references/omedora-copr.md` — who owns the omedora COPR and where that default lives. Load that file when working on this.

## COPR build gotchas: fresh-project seed + Hyprland order-dependence (2026-11)

→ Moved to `references/omedora-copr.md` — COPR build gotchas: fresh-project seed + Hyprland order-dependence. Load that file when working on this.

## Omarchy updater override (Fedora atomic)

→ Moved to `references/update-notification.md` — the Omarchy updater override (and the immutable-specific checker) for Fedora atomic. Load that file when working on this.

## Harvesting the user's own config onto the image

→ Moved to `references/user-config-delta-capture.md` — harvesting the user's own config onto the image. Load that file when working on this.

## Hurunagus look-and-feel payload + `omarchy-hurunagus-configs` (2026-11)

→ Moved to `references/user-config-delta-capture.md` — the hurunagus look-and-feel payload + `omarchy-hurunagus-configs`. Load that file when working on this.

## Plymouth boot splash (2026-11)

- This image family defaults to the **`bgrt`** theme (firmware logo). Dropping a custom `watermark.png` into `themes/spinner/` does NOTHING until the theme is selected — which is exactly the state the silverblue repo's "custom plymouth theme" was in (one 27 KB PNG, no selection anywhere).
- Select it via `/etc/plymouth/plymouthd.conf` (`[Daemon]` / `Theme=spinner`). That one file is read twice: plymouthd at runtime, and dracut's `45plymouth/module-setup.sh` when building the initramfs (it prefers this file over `/usr/share/plymouth/plymouthd.defaults`). Ship it from `system_files/etc/plymouth/plymouthd.conf`.
- The stock `spinner` theme is `ModuleName=two-step` (that plugin already ships) and renders `watermark.png` from its `ImageDir`.
- That watermark path is owned by **`fedora-logos`**, not `plymouth-theme-spinner` (verify with `rpm -qf`), so overriding it shows up as `rpm -V fedora-logos` noise — harmless on an image-based OS.
- dracut embeds theme directories wholesale: the baked initramfs carries 81 theme files including every spinner animation frame, so an overridden watermark rides along.
- To prove a splash change, check inside the image: the conf says `spinner`, the watermark hash matches, and `lsinitrd /usr/lib/modules/*/initramfs.img | grep -i spinner` lists the theme.

## Base-image version drift (2026-11)

`FROM ghcr.io/ublue-os/base-main:latest` + `--pull=newer` means the Fedora MAJOR version can move under you on any build: ublue flipped `base-main:latest` from `44.20261102.0` to `45.20261108.23` within one week, so a CI run suddenly resolved 481 fc45 NEVRAs (`dnf5`/COPR chroot `fedora-45-x86_64`) and published a Fedora 45 image while the host was still F44. **Diagnose from evidence, not the tag string:** check the base's OCI version label (`skopeo inspect --no-tags docker://ghcr.io/ublue-os/base-main:latest | jq .Labels["org.opencontainers.image.version"]`) and confirm in the image (`podman run --rm <img> rpm -E %fedora; rpm -q fedora-release`). A handful of stale `fc44` packages in an otherwise-fc45 image is normal — they are inherited ublue base/vendored deps (jemalloc, jsoncpp, libvisual, tini-static, zimg, ublue-os-luks), not a build bug. Rebase implication: this is a Fedora MAJOR upgrade for the host, so warn the user rather than treating it as a routine update. `base-main` carries stable (`44`) and dated (`45-20261108.24`) tags for pinning when reproducibility is wanted; the Containerfile comment already flags this.

## Cross-DE/DM rebase helper (`hurubase`, 2026-11)

→ Moved to `references/hurubase.md` — the hurubase cross-DE/DM rebase helper: mechanics, prompts, state, the mock+real test seam. Load that file when working on this.

## Pushing a work branch into one of these repos

**Check `git config user.email` before any commit that will be pushed — the git identity
is per-repo here.** `~/hurunagus` (the base/template checkout, which is NOT one of the 7
repos tabled above) is configured `Hermes Agent <build@example.com>`, so a commit made
blind there is authored by that identity instead of the user; amend it
(`git commit --amend --author='wegweg7979 <…>' --no-edit`) rather than shipping the wrong
author. The plugin checkouts can differ again (`thord.workspaces` is `wegweg7979
<<user-email>>`), so read the per-repo value rather than assuming one.

Before pushing ANY branch that is not the repo's own build branch, read each
`.github/workflows/*.yml`'s **whole** `on:` block — never a first-N-lines window.
`sed -n '1,18p' … | grep -A12 '^on:'` cut off `copr-build.yml`'s `branches: [omedora-4]`
filter, which is exactly the line that decides whether the push publishes COPR
packages, and the wrong all-clear is the dangerous direction. What the fork's
workflows actually do:

- `copr-build.yml` — `on: push` **scoped to `omedora-4`** plus a spec-payload `paths:`
  filter, so a side branch cannot submit a COPR build. This is the one that matters:
  `wegweg7979/omedora-4` is the repo the running images consume.
- `test.yml` — also `omedora-4`-scoped, so a side branch does not run it.
- `i18n-sync.yml` — unscoped `on: push`, so it WILL run: it lands an `i18n-sync`
  branch/PR, never writes into the pushed branch, and no-ops when its translation
  secrets are absent.
- `i18n-check.yml` — `pull_request` only.

A new branch is safe by construction — it cannot alter the default branch — so push it
and prove it from the remote rather than from the push output: `git ls-remote origin`
shows the new ref AND the untouched default-branch sha in one listing, then
`gh run list -R <owner>/<repo> --limit 5` shows whatever actually fired. When the user
says "it's on a separate branch so it's safe to push, I assume" the honest answer is the
measured one — name the workflows that fire and the one live side effect that would have
been a problem, rather than agreeing.

On `omedora-4` the push is also the ONLY way a fix reaches the COPR: a build carries the
commit it is pinned to (`--commit <github.sha>`, self-sourced packages built from
`git archive` of that ref), so an unpushed local fix cannot be built by a push OR a
dispatch — the dispatch would simply build the old remote tip. When the user says "trigger
the build for my fix", push the ref first and say so; the mechanics are in
`references/omedora-copr.md` §"Which commit a build actually carries". **Then gate the image build on the COPR build reaching `succeeded`** — the image CI re-resolves the repo on every run (`OMEDORA_BUST`), so triggering it while the COPR build is still `running` bakes the PREVIOUS NEVRA and the host keeps the old payload on a green build (the ordering race in `references/omedora-copr.md` item 4). Poll `api_3/build/list?…&limit=2` until neither build is `running`, then push `main` (which is the trigger — `build.yml` has no separate dispatch requirement) and prove the run exists for that sha.

**A fork fix plus its image-side bake is TWO pushes in TWO repos — never let "the push is done" stand for the set.** After the `omedora-4` push, the matching image commit (the `build_files/fedora.toml` bake) is still local until you push `main` in `~/hurunagus-hyprland`; leave it local ONLY deliberately (for the COPR gate above) and name its sha in the same report, so the user is not the one who discovers the gap. When they later ask "did you push", answer PER REPO from the real remote, not from memory and not from local tracking refs (those only move on a fetch/push here): `git ls-remote origin <branch>` for each repo, `git log --oneline origin/<branch>..<branch>` for what is still missing, `gh run list -R <owner>/<repo> --limit 8 --json headSha,status,conclusion,event,createdAt` to see which sha the CI actually ran on, and the COPR `api_3/build/list` state for what the fork push published. The honest shape of the answer is "repo A landed (sha, CI, build state) / repo B is still local (sha)" — a single "yes" hides the half that did not go.

**A bare go with no context ("do the pushes and trigger the builds required") arrives in a FRESH
session/thread that holds none of the drafting conversation — reconstruct it from the CHECKOUTS, not by
asking.** The deferred work is uncommitted WORKING-TREE changes by design, so `git log @{u}..HEAD` is
empty and tells you nothing: `git status -sb` in `~/omedora-inspect` (a dirty `bin/**` or `install/**`
is the self-sourced COPR trio) and in `~/hurunagus-hyprland` (a dirty `build_files/fedora.toml` is the
bake that pairs with it) is what identifies the set. Then read the last session's tail for the agreed
shipping order and the gate — the drafts were left uncommitted precisely so the order stays open. Do not
re-derive the order, and do not ask the user to re-explain what they already approved.

**Fetch before pushing `main` in these repos — the README is edited in the GitHub web UI, so the
remote moves under you.** A `git push origin main` in the image repo came back
`! [rejected] … (fetch first)` while five commits sat on the remote. Recovery, in order:
`git fetch origin` → `git log --oneline HEAD..origin/main` → `git diff --name-only HEAD...origin/main`
(confirm no overlap with the files you touched) → `git rebase origin/main` (your commit is
unpublished, so nothing shared is rewritten) → re-run the syntax gates → push again. A local
`main` that matched `origin/main` at the last fetch proves nothing.
**A docs-only push then produces NO run at all**: `build.yml` carries
`paths-ignore: ['**/README.md']`, so a missing run after a README change is the filter working,
not a broken trigger. Check `git show --stat HEAD` before blaming the workflow.

## Driving the live desktop from an agent shell

GUI work on these boxes — launching a viewer, screenshotting a claim, proving a window
actually rendered — needs the compositor's environment, which is exported to its
CHILDREN and never to a fresh shell:

```bash
eval "$(bash scripts/wayland-env.sh)"   # WAYLAND_DISPLAY, XDG_RUNTIME_DIR, HYPRLAND_INSTANCE_SIGNATURE
```

- **Never improvise the discovery.** `pgrep -f 'quickshell|Hyprland'` plus the first
  readable `/proc/<pid>/environ` returns a process that has `XDG_RUNTIME_DIR` but NOT
  `WAYLAND_DISPLAY`, and then `grim`, `hyprctl` and every Qt/GTK app fail with
  `failed to create display` — which reads as a broken tool rather than a missing
  variable, and costs a re-diagnosis every time. The script scans `/proc` for a process
  owned by the current user whose environ CONTAINS `WAYLAND_DISPLAY`; confirm it with
  `hyprctl -j monitors` before trusting it.
- **Prove GUI claims from pixels, not exit codes.** `hyprctl clients` gives
  class/title/size/at (window existence); `grim <file>` + `vision_analyze` on the PNG is
  how you verify what is actually rendered — that a gallery shows real previews rather
  than placeholder icons, or which entries a file manager's sidebar really lists. A live
  process is not a rendered window.
- **Launch long-lived GUIs with `terminal(background=true)`** — `&`, `setsid` and
  `nohup` wrappers are refused, and the app must outlive the call.
- **A file-manager default that looks "not installed" is usually a Flatpak:** its
  `.desktop` lives under `/var/lib/flatpak/exports/share/applications/`, so
  `ls /usr/share/applications | grep -i <app>` finds nothing while the default works
  fine. Check `flatpak list --app` before declaring a handler broken.
- Parsing `hyprctl -j` belongs in a FILE, not an inline `python3 -c` (pitfall 12f):
  quoted f-strings inside a shell command die with `unexpected character after line
  continuation character`.
- **When a screenshot diff IS the evidence, diff only a region no window covers.** A whole-output
  `grim` frame measures whatever the user's windows are doing: a chat window streaming its own tool
  output moved a 35 % pixel delta on the monitor under test and read as a failed wallpaper revert,
  while the wallpaper-only strip below that window was pixel-identical (0.1 %, and 0.0 % on the 12 px
  gutter). Crop to that strip — the gap a tiled layout leaves — and quote the crop, never the full
  frame. `hyprctl layers` answers "which surface is on top, and is mine still mapped" with no pixels
  at all, and is the stronger claim.

## Pitfalls summary (if you remember nothing else)

1. `FROM scratch AS ctx` has **no `/bin/sh`** — no RUN in the ctx stage.
2. `COPY build_files /` copies contents to root, not the directory — the build script is at `/build.sh`, not `/build_files/build.sh`.
3. `--mount=type=bind,from=ctx` **does not work** — use `--mount=from=ctx,source=/,target=/ctx`.
4. The ublue base ships `/usr/local` → symlink to `/var/usrlocal` — `/usr/local/bin` is not a real directory; create `/var/usrlocal/bin` instead.
5. `build.sh` and other shell scripts must be `chmod +x`ed in the repo — git preserves the mode.
6. Guard every `systemctl enable X.service` with `systemctl cat X.service` first — missing services fail the build.
7. When an env-var means "enable X / use path P", never default it with `${VAR:-default}` if an explicitly EMPTY value must mean "off/mutable" — `:-` silently coerces empty back to the default. Test set-but-empty with `${VAR+x}` and only then fall back for the truly-unset case.
8. Test fixtures that assert a mutable path must force it explicitly on an ostree dev host (`/run/ostree-booted` exists there) rather than relying on the default. See `references/omedora-immutable-port.md`.

**9-17: the long ones live in `references/pitfalls.md`** — load that file before touching tests, migrations, kernels, packages or the distro token. Index:

- (9) **This user's tests must never run against the live desktop. The suite executes commands that reach systemctl/firewall/root against the INSTALLED …
- (10) Migrations that pkg-add a not-baked package fail on bootc. Bake the package (edit `$EXCLUDED_PACKAGES` in build.sh, rebuild), don't gate the …
- (11) **A bootc REBASE never re-seeds `/etc/skel` into an existing user's `$HOME`.** Anything a later image adds to `/etc/skel` (e.g. …
- (12) **The `fedora-ostree` mismatch hits COMMAND case-dispatch and `== fedora` checks too, not just migration guards (gotcha 8).** Any `case … — and a logo file that carries SGR breaks the About's OWN width + landmark probes: the window maps at the theme default and never corrects itself, and the sheen never builds (both probes must strip escapes; probe: `scripts/about-logo-probe.sh`).
- (13) **Custom-kernel swap — SHIPPED in hurunagus-hyprland (2026-11, commits ba703d2 + 107d504); Secure Boot signing of that kernel SHIPPED too** (`phase_sign` + committed cert + enroll helper, proven in an enforcing-SB OVMF VM — see `references/secure-boot-signing.md`).** `kernel-cachyos` (GCC flavor — the user explicitly chose …
- (14) **Bake a non-Fedora, non-buildable CLI by curl'ing its release binary inside build.sh — do NOT reach for a COPR spec or commit a git blob.** When the …
- (15) **A package can install cleanly, look enabled, and still do NOTHING — check its default target path against the real fstype before proposing it.** …
- (16) **A freshly built image can present as "chronologically older" to `rpm-ostree upgrade`, and the refusal has nothing to do with your content.** The guard compares the ostree commit stamp carried in the image — which a derived image can inherit from its ublue base — against the booted deployment's, never your build time; diagnose read-only with `rpm-ostree upgrade --check`/`--preview`, clear it with `--allow-downgrade`. Also: no `Staged:` line in `rpm-ostree status` means the transaction failed (the second entry is the rollback, not a staged update), and a push to main builds by itself. …
- (17) **Per-monitor workspaces (Omarchy 4.5+): the bar churn, the state file, and why a hand-edit vanishes.** Never pin workspaces with `hl.workspace_rule`; a pre-4.5 workspaces widget that reads workspace rules lists the wrong numbers and must go; `~/.local/state/omarchy/monitor-workspaces` needs a `hyprctl reload` after any hand-edit (the Lua module holds it in memory and writes it back); reassigning a block renumbers workspaces in place rather than moving windows. …
