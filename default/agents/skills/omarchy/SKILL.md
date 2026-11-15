---
name: omarchy
description: >
  REQUIRED for end-user customization of Linux desktop, window manager, or system config.
  Use when editing ANY file in ~/.config/, ~/.config/hypr/, ~/.config/omarchy/,
  ~/.config/alacritty/, ~/.config/foot/, ~/.config/kitty/, or ~/.config/ghostty/.
  Triggers: Hyprland, window rules, window behavior, animations, keybindings, monitors, gaps, borders,
  blur, opacity, omarchy-shell, bar, widgets, terminal config, themes, fonts, background,
  night light, idle, lock screen, screenshots, screen recording, reminders, layer rules, workspace
  settings, display config, appearance changes, and user-facing omarchy commands. Excludes Omarchy
  source development through `omarchy dev link` workflows.
  On Fedora hosts (mutable or bootc/atomic) read "Which distro is this?" first: package
  and system changes do not work the way the Arch instructions below describe.
---

# Omarchy Skill

Manage [Omarchy](https://omarchy.org/) Linux systems with Hyprland. Upstream that is a
beautiful, fun, agentic Arch Linux distribution; this checkout is **omedora**, the same
desktop and command suite ported to **Fedora** — both mutable Fedora and bootc/atomic
images (hurunagus).

This skill is for end-user customization on installed systems.
It is not for contributing to Omarchy source code.

## Which distro is this? (read first on Fedora)

The CLI is identical everywhere; the OS underneath is not. Ask the dispatcher itself —
every `omarchy-*` command routes on the token it prints:

```bash
omarchy-distro     # arch | fedora | fedora-ostree
```

| Token | What you are on | How a system change happens |
|-------|-----------------|-----------------------------|
| `arch` | Upstream Omarchy | `pacman` / AUR through `omarchy pkg …` |
| `fedora` | Fedora with a writable `/usr` | `dnf`/COPR/RPM Fusion/Flathub through the Fedora package map (`install/packages/fedora.toml`) |
| `fedora-ostree` | **A bootc/atomic image (hurunagus)** — `/` is a read-only composefs mount | a NEW IMAGE plus a reboot; nothing installs into `/usr` at runtime |

On `fedora-ostree` the whole Omarchy payload lives in `/usr` (owned by the
`omedora-settings` RPM) and is replaced wholesale by the next image build. So:

- **`/usr` is read-only — not even root can write it.** Privileges are not the
  obstacle and no `sudo` changes that. `/etc`, `/var` and `$HOME` are the parts
  that are writable and survive rebases.
- **`omarchy pkg add <rpm>` exits 1** with "…is not in the image. On an immutable host
  bake it into the image build (fedora.toml / Containerfile) and rebase". That is the
  correct answer, not a bug. Flatpak is the only runtime-installable tier. Fedora has
  **no AUR at all**: `omarchy pkg aur add` resolves through the same map (on mutable
  Fedora) or reaches the same bake message (on `fedora-ostree`).
- **Adding an RPM is an image change, and it is the USER's step.** The package goes into
  the image repo's bake set (`build_files/build.sh`, or the mapping the image's vendored
  `build_files/fedora.toml` resolves — e.g. in `~/hurunagus-hyprland` for the Hyprland
  variant), the image is rebuilt and the host rebases. Never hand-edit `/usr`, never tell
  the user a runtime install "worked", and never run the build/rebase for them.
- **`omarchy update` is an image update**, not a package upgrade: it applies the newest
  image (`ujust update`, or `bootc upgrade`), then runs migrations + post-update hooks,
  updates mise tools and Flatpaks, and ends with **reboot to apply**. Until that reboot
  the old payload is still what is running.
- **The shipped terminal is `foot`.** `alacritty`, `kitty` and `ghostty` are install
  targets, not shipped configs — confirm the terminal is present before editing its
  config file.
- **`omarchy setup security fingerprint` does work here** (fprintd, fprintd-pam and
  authselect are baked); it wires PAM up via `authselect enable-feature with-fingerprint`
  instead of editing `/etc/pam.d/*` by hand.
- **Fedora bugs do not belong upstream**: see the routing table in
  [`contributing.md`](contributing.md).

## Topic Guides

Deeper instructions for common areas live next to this file. Read the
matching guide before starting:

- [`hyprland.md`](hyprland.md) - keybindings, monitors, window rules, and other Hyprland config
- [`plugins.md`](plugins.md) - the Omarchy shell: bar layout, widgets, plugins, idle behavior
- [`theming.md`](theming.md) - themes, backgrounds, and fonts
- [`hooks.md`](hooks.md) - automation hooks that run on system events
- [`capture.md`](capture.md) - screenshots, screen recordings, OCR text capture, and file sharing
- [`contributing.md`](contributing.md) - reporting Omarchy bugs and submitting fixes upstream

## Critical Safety Rules

For privileged commands, follow the Privilege Escalation rules below: `sudo` when a terminal is available for the password prompt, `pkexec` when it is not. Do not wrap commands that already manage privilege elevation themselves.

**For end-user customization tasks, NEVER modify anything in `/usr/share/omarchy/`** - but READING is safe and encouraged.

On upstream Arch that directory is owned by the `omarchy` package; on Fedora it is owned
by `omedora-settings`. Either way a local change is lost: on a bootc image `/` is a
read-only composefs mount, so nothing under `/usr` can be written at all, and the tree is
replaced wholesale by the next image build plus reboot.

```
/usr/share/omarchy/     # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                    # Command source (packaged binaries are on PATH)
│                           #   → bin/fedora/, bin/omarchy-ostree/: the Fedora +
│                           #     immutable siblings the dispatch execs
├── config/                 # Default config templates
├── themes/                 # Stock themes
├── default/                # System defaults
├── shell/                  # Omarchy shell source and defaults
├── omedora/                # Omedora packaging notes, COPR specs, Fedora docs
├── etc-overrides/          # Files Omedora overlays onto /etc
├── migrations/             # Update migrations
└── install/                # Installation scripts
                            #   → install/config/* runs only in the mutable
                            #     installer; on bootc only install/user/* does,
                            #     at first login, and it must stay $HOME-only
```

**Reading `/usr/share/omarchy/` is SAFE and useful** - do it freely to:
- Understand how omarchy commands work: `omarchy theme set --help` or `cat $(which omarchy-theme-set)`
- See default configs before customizing: `cat "$OMARCHY_PATH/config/omarchy/shell.json"`
- Check stock theme files to copy for customization
- Reference default hyprland settings: `cat /usr/share/omarchy/default/hypr/*`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/omarchy/themes/<custom-name>/` - Custom themes
- `~/.config/omarchy/hooks/` - Custom automation hooks

If the request is to develop Omarchy itself, this skill is out of scope. Follow repository development instructions instead of this skill.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo` for
privileged work. Upstream Omarchy may grant passwordless `sudo` access to particular
commands, and the terminal is the appropriate place to request a password
when one is needed.

**On Fedora — mutable and bootc alike — assume `sudo` ALWAYS prompts.** Omedora installs
no NOPASSWD rules (`sudo -n true` fails; `sudo -l` reports a password-required
`(ALL) ALL`). Never plan a privileged step that only works non-interactively: run it in a
terminal the user can see, or hand them the command. And on a bootc image page for this
instead: `sudo` cannot change `/usr` either, because the root filesystem is read-only —
see "Which distro is this?".

Use `pkexec` only when the caller cannot interact with a terminal or cannot
enter a password there, such as a command launched by an agent or a graphical
background process. Do not replace `sudo` with `pkexec` merely because a
command changes system state.

## System Architecture

Omarchy is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Base OS** | upstream Arch Linux; here Fedora (mutable) or a Fedora **bootc/atomic** image — `/usr` read-only, `/etc`+`/var` persistent | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Omarchy shell** | Status bar + notifications (Quickshell) | `~/.config/omarchy/shell.json` |
| **Launcher/menus** | Quickshell menu | `~/.config/omarchy/extensions/omarchy-menu.jsonc` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Omarchy OSD** | On-screen display | Quickshell plugin |

## Command Discovery

Omarchy ships a single `omarchy` CLI that dispatches to all `omarchy-*` binaries via `omarchy <group> <action>`. Always prefer this form — it is self-documenting and stable. The underlying `omarchy-*` binaries still exist on `PATH` and remain safe to read for source.

```bash
# List every documented command and its summary (--all includes hidden commands)
omarchy commands

# Show the commands inside a group
omarchy theme --help
omarchy refresh --help
omarchy restart --help

# Show help for a specific command (does not execute it)
omarchy theme set --help

# Machine-readable listing (binary, route, summary, args, aliases)
omarchy commands --json

# Read a command's source to understand it
cat $(which omarchy-theme-set)
```

### Command Groups

Run `omarchy --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `omarchy refresh` | Reset config to defaults (backs up first) | `omarchy refresh shell` |
| `omarchy restart` | Restart a service/app | `omarchy restart shell` |
| `omarchy toggle` | Toggle feature on/off | `omarchy toggle nightlight` |
| `omarchy theme` | Theme management | `omarchy theme set <name>` |
| `omarchy bar` | Bar layout and widgets | `omarchy bar move omarchy.clock --section right` |
| `omarchy plugin` | Manage/clone shell plugins | `omarchy plugin clone omarchy.clock` |
| `omarchy hook` | Install automation hooks | `omarchy hook install theme-set <script>` |
| `omarchy install` | Install optional software / packages | `omarchy install docker dbs` |
| `omarchy launch` | Launch apps | `omarchy launch browser` |
| `omarchy capture` | Screenshots and recordings | `omarchy capture screenshot` |
| `omarchy reminder` | Desktop notification reminders | `omarchy reminder 15 "Pickup Jack"` |
| `omarchy pkg` | Package management | `omarchy pkg add <pkg>` |
| `omarchy setup` | Interactive setup wizards | `omarchy setup security fingerprint` |
| `omarchy update` | System updates | `omarchy update` |

"Stock omarchy command" does not mean "distro-neutral command": `install`, `pkg` and
`update` are the three that route differently per distro. Check the group's own `--help`
and the per-distro rules above before promising a result.

## Configuration Locations

Hyprland config lives in `~/.config/hypr/` — see [`hyprland.md`](hyprland.md).
The Omarchy shell (bar, notifications, plugins, idle) is configured in
`~/.config/omarchy/shell.json` — see [`plugins.md`](plugins.md).

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `omarchy restart terminal`

On Fedora only `foot` ships with the image; the others are install targets
(`omarchy install terminal <alacritty|foot|ghostty|kitty>`, subject to the Fedora
package map). Editing the config of a terminal that is not installed does nothing.

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |

## Safe Customization Patterns

### Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/hypr/bindings.lua

# 2. Backup before changes
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Hyprland: auto-reloads on save, but MUST validate with `hyprctl reload` and `hyprctl configerrors`
# - Omarchy shell: shell.json and user plugin code under ~/.config/omarchy/plugins/ hot-reload on save
# - Menus/launcher: ~/.config/omarchy/extensions/omarchy-menu.jsonc hot-reloads on save
# - Terminals: apply with `omarchy restart terminal` (reloads running terminals; foot picks changes up in new windows)
```

### Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
omarchy refresh shell
omarchy refresh hyprland

# The refresh command:
# 1. Backs up current config with timestamp
# 2. Copies default from $OMARCHY_PATH/config/
# 3. Restarts the component where the refresh needs it (e.g. `refresh shell`)
```

## System Commands

```bash
omarchy update                  # Apply the system update (image + reboot on bootc)
omarchy version                 # Show Omarchy version
omarchy debug --no-sudo --print # Debug info (ALWAYS use these flags)
omarchy system lock             # Lock screen
omarchy system shutdown         # Shutdown
omarchy system reboot           # Reboot
```

**IMPORTANT:** Always run `omarchy debug` with `--no-sudo --print` flags to avoid interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
omarchy debug --no-sudo --print

# Reset specific config to defaults
omarchy refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `omarchy refresh config hypr/hyprland.lua` will refresh ~/.config/hypr/hyprland.lua
omarchy refresh config <config-file>

# Full reinstall of configs (nuclear option)
omarchy reinstall configs
```

## Decision Framework

When user requests system changes:

1. **Is it a stock omarchy command?** Use it directly
2. **Is it a config edit?** Edit in `~/.config/`, never `/usr/share/omarchy/`
3. **Is it a theme customization?** Follow [`theming.md`](theming.md); create a NEW custom theme directory
4. **Is it automation?** Follow [`hooks.md`](hooks.md); use `omarchy hook install` and the hook `.d` directories
5. **Is it a package install?** Arch: `omarchy pkg add <pkgs...>` (AUR-only: `omarchy pkg aur add <pkgs...>`). Fedora: `omarchy pkg add <pkgs...>` covers the mapped tiers only; a package with no Fedora source needs an image bake (the user's step), and there is no AUR — see "Which distro is this?"
6. **Is it built-in shell/plugin code?** Follow [`plugins.md`](plugins.md); clone it with `omarchy plugin clone`, never edit the packaged copy
7. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)

### Reminder Requests

When the user asks to set a reminder, use `omarchy reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder 60 "Check laundry"
omarchy reminder show
omarchy reminder clear
```

## Out of Scope

This skill intentionally does not cover Omarchy source development. Do not use this skill for:
- Editing files in `/usr/share/omarchy/` (`bin/`, `config/`, `default/`, `shell/`, `themes/`, `migrations/`, etc.)
- Creating or editing migrations
- Running `omarchy dev ...` commands

## Example Requests

- "Change my theme to catppuccin" -> `omarchy theme set catppuccin`
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings first, then use `o.rebind` to replace one or `o.bind` to add one in `~/.config/hypr/bindings.lua`
- "Configure my external monitor" -> Edit `~/.config/hypr/monitors.lua`
- "Make the window gaps smaller" -> Edit `~/.config/hypr/looknfeel.lua`
- "Turn on night light" -> `omarchy toggle nightlight` (for time-based schedules, edit `~/.config/hypr/hyprsunset.conf` profiles, then `omarchy restart hyprsunset`)
- "Set a reminder to pickup jack in 15 minutes" -> `omarchy reminder 15 "Pickup Jack"`
- "Show my reminders" -> `omarchy reminder show`
- "Clear all reminders" -> `omarchy reminder clear`
- "Customize the catppuccin theme colors" -> Overlay: put an edited `colors.toml` in `~/.config/omarchy/themes/catppuccin/`, then re-apply the theme (see `theming.md`)
- "Run a script every time I change themes" -> Install it with `omarchy hook install theme-set <script>`
- "Change how workspace labels are rendered" -> Clone `omarchy.workspaces`, which switches the bar to `<username>.workspaces`, then edit the clone
- "Lock after ten minutes" -> Set `idle.lock` to `600` in `~/.config/omarchy/shell.json`
- "Reset shell/bar to defaults" -> `omarchy refresh shell`
- "Record my screen" -> `omarchy screenrecord --fullscreen`, then `omarchy screenrecord --stop-recording` (see `capture.md`)
- "Install an app that isn't on Flathub" -> On `fedora-ostree` that is an image bake, not an install: say so and hand it to the user (see "Which distro is this?")
- "Report this bug to Omarchy" -> Gather diagnostics and a capture of the problem, then file it (see `contributing.md`)
