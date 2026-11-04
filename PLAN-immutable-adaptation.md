# Omedora → Immutable (bootc) Adaptation Plan

Decision basis: user's fork of omedora (Omarchy 4, mutable-Fedora port). Target: run the
command suite on an immutable/bootc Fedora image (baked at build, updates via rebase).

## Decisions (confirmed by user)

1. **Hardware**: x86 desktops + laptops, integrated Intel GPU only.
2. **Gaming**: remove entirely.
3. **AI agents**: only Hermes.
4. **Commercial services**: remove all installers/removers.
5. **Adaptation strategy**: Option 2 — keep Arch/Omedora bodies byte-identical, add a
   THIRD `ostree` branch to the existing distro dispatch, so upstream rebases stay clean.
6. All six removal-candidate groups approved (XR, brand-hw, non-Hermes agents, gaming,
   services, AI/dev/windows-vm).

---

## Overall design (Option 2)

Extend the existing dispatch from two tokens to three:

| Token | Meaning | When |
|-------|---------|------|
| `arch` | Arch (upstream) | non-Fedora |
| `fedora` | mutable Fedora / Omedora on Workstation (dnf) | existing behavior |
| `fedora-ostree` | immutable Fedora image (bootc) | NEW — `/run/ostree-booted` present |

- `omarchy-distro` gains a `fedora-ostree` output: if `/run/ostree-booted` exists →
  `fedora-ostree`, else existing `arch|fedora` logic. Honored `OMARCHY_DISTRO` override
  stays. Add `/run/ostree-booted` read to the resolution order.
- Every surviving mutable-state command's Fedora `case` becomes:
  ```bash
  case "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" in
    fedora-ostree) exec "$(dirname -- "${BASH_SOURCE[0]}")/omarchy-ostree/<sibling>" "$@";;
    fedora) ...existing dnf sibling...;;
  esac
  ```
  Arch bodies stay untouched → upstream `git rebase` stays clean; only the dispatch
  prepend and new additive `bin/omarchy-ostree/` siblings change.

---

## Phase 1 — infra (new additive files, no upstream body edits)

- `bin/omarchy-distro`: emit `fedora-ostree` when `/run/ostree-booted` exists.
- `bin/omarchy-ostree/` directory: shared immutable siblings (named omarchy-ostree, not ostree, since /usr/bin/ostree is the real ostree CLI — a dir there conflicts).
- `bin/omarchy-ostree/pkg.py` or siblings — bake-check + flatpak fallback.

## Phase 2 — package helpers (`pkg-*`, mutable)

On bootc, packages are baked; `dnf` cannot persist. New `fedora-ostree` behavior:
- `pkg-add` / `pkg-install` / `install-*` (RPM-backed): check if the mapped package is
  already baked (`rpm -q` / `fedora.toml` source=dnf|copr). If present → success (already
  installed). If missing → for `source=flathub` entries, `flatpak install` (persists on
  bootc); for `dnf|copr` entries → print "bake into the image at build" and exit with a
  clear message (no attempt since it cannot persist).
- `pkg-drop` / `remove-*`: RPM removal cannot persist → message "remove from image build".
  Flatpak removal works → route flatpak-uninstall.
- `pkg-missing` / `pkg-present`: work unchanged (query rpm/flatpak).
- `pkg-aur-*`: no AUR on bootc → no-op (same as Fedora).

## Phase 3 — update chain (`update-*`, `omarchy-update`)

Use the skill's proven bootc rework (`references/update-notification.md` + `ujust update`):
- `omarchy-update-available` → branch on `/run/ostree-booted`; check staged-deployment
  timestamps + `skopeo` digest vs deployed. Keep the widget contract (exit 0 / state files).
- `omarchy-update` → Fedora-ostree arm runs `ujust update` (rpm-ostree stage + flatpak +
  distrobox), then surface "reboot to apply."
- `update-system-pkgs`, `update-aur-pkgs`, `update-orphan-pkgs`, `update-aur-pkgs`,
  `update-keyring`, `update-pkg-prune`, `update-pacman-guard` → no-op or trivial on bootc.
- `update-firmware` (fwupd) → works, keep.
- `update-mise`, `update-time`, `update-confirm`, `update-lock`, `update-stay-awake`,
  `update-requires-free-space`, `update-analyze-logs`, `update-status`, `update-restart`,
  `update-user-notify` → keep (user-space / non-package).

## Phase 4 — installers / optional software

- RPM-backed optional installers (`install-{and-launch,app,browser,terminal,editor-*,
  font,dev-env,preinstalls}`, `install-hermes-cli`): bake-present → success; else
  flatpak-if-mapped; else "bake at build" message. Hermes is kept (user's agent).
- `remove-ai-hermes`, `remove-browser`, `remove-dev-env`, `remove-launcher-entry`,
  `remove-preinstalls`: bake-irrelevant → message.

## Phase 5 — explicit removals from repo

**bin/** (~120 files):
- gaming: 18 (`install-gaming-*`, `remove-gaming-*`)
- services: 12 (`install-service-*`, `remove-service-*`)
- non-Hermes agents: 9 (openclaw/chatgpt/t3-code/perplexity)
- brand hw: 14 (asus*, dell-xps*, framework16, surface, nvidia*, hybrid-gpu, intel-ptl,
  recover-internal-monitor)
- boot/plymouth/sdDM/limine/factory-reset/windows-vm/reinstall/snapshot: 21
- dev tooling: 12 (`dev-*`)

**Menu** (`default/omarchy/omarchy-menu.jsonc` + `config/omarchy/extensions/...`):
- prune 42 entries that reference removed commands (verified list attached).

**install/hardware/**: apple/, asus/, asus-rog.sh, dell-xps*, fix-surface-keyboard.sh,
fix-tuxedo-backlight.sh, framework/, framework16.sh, lenovo/, nvidia.sh, surface.sh.
Keep the generic portable subset (bluetooth, fix-bcm43xx, network, set-wireless-regdom,
speaker-tuning, vulkan, fix-fkeys, fix-synaptic-touchpad, fix-yt6801).

**omedora/packaging/copr/**: drop the XR stack (~35 files: hypxr*, basalt-xreal,
monado-xreal, wivrn-hypxr, xreal-ctl). Also prune their references in `fedora.toml`,
`build-repo.sh`, `managed_packages.py` if present.

**omarchy-distro / docs / fedora.toml**: update distro doc + tests for the new token.

## Phase 6 — `medora-*` oracle / Composer
(placeholder — actual cover scope TBD with user)

## Keep as-is (work unchanged on bootc)
~330 user-space commands: audio, battery, bluetooth, brightness, capture, clipboard,
crash, font, hyprland, launch, launcher, menu, network, notification, osd, plugin,
power, powerprofiles, reminder, restart, shell, state, theme, toggle, transcode, tui,
voxtype-status/config/model, weather, webapp + generic `hw-*` (laptop, laptop-closed,
external-monitors, display, intel, vulkan, webcam, touchpad, touchscreen, fingerprint).

Also keep (edit /etc + PAM + systemd + usergroups, which merge on bootc):
setup/remove-security-{fido2,fingerprint,sshd,sudoless-docker}, sudo-*, apply-lock.

## Verification
- `./test/all` + `./test/cli` + `./test/shell` greens after each phase.
- `omarchy commands --check` to validate metadata after deletions.
- Menu JSONC re-validation (no dangling refs).
- Distro dispatch tests for the new `fedora-ostree` token.