---
name: hyprland-config
description: "Hyprland config and monitor/DPMS power-churn triage."
version: 0.3.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [desktop, hyprland, omarchy, wayland]
    related_skills: [omarchy]
---

# Hyprland Configuration Skill

Configure Hyprland (wayland compositor). Based on the Omarchy Hyprland layout.

## When to Use

Use this skill when the user asks to:
- Configure Hyprland (wayland compositor) settings
- View or edit hyprland.lua, monitors.lua, input.lua, bindings.lua, looknfeel.lua, or autostart.lua
- Set up keybindings, monitors, window rules, or workspace rules
- Debug Hyprland configuration errors with hyprctl
- Diagnose displays that blink, drop signal, or power-cycle (lock/idle/DPMS churn) - see [`references/monitor-dpms-churn.md`](references/monitor-dpms-churn.md)
- Change window or terminal opacity / blur (window rules, terminal alpha), e.g. "make my terminal 80% opaque"
- Explain or fix workspace numbers on the bar, per-monitor workspaces, or workspace pills that act on the wrong screen - see the `omarchy-bar-modules` skill's per-monitor workspaces reference
- Edit a terminal emulator's own config (foot / alacritty / kitty / ghostty) - see [`references/terminal-appearance.md`](references/terminal-appearance.md)
- Make the palette follow the wallpaper (matugen / pywal / wallust style), or answer whether such theming already exists here - see [`references/dynamic-theming.md`](references/dynamic-theming.md)
- Tell whether a daemon has injected a watcher into the compositor's Lua VM, or why a tool you already stopped is still visible on the IPC socket - see "Daemons that inject a Lua watcher into the compositor"
- Understand the Omarchy Hyprland config structure

Use `omarchy` skill for Omarchy-specific commands and workflows.

- Main config: `$XDG_CONFIG_HOME/hypr/hyprland.lua` (default `~/.config/hypr/hyprland.lua`)
- Module files: monitors.lua, input.lua, bindings.lua, looknfeel.lua, autostart.lua in ~/.config/hypr/
- Lua LSP stubs: /usr/share/hypr/stubs/hl.meta.lua

## File structure

The main config is hyprland.lua, which loads Omarchy defaults then requires modules:

- hyprland.lua - main config
- monitors.lua - display config
- input.lua - keyboard/mouse settings
- bindings.lua - keybindings
- looknfeel.lua - appearance (gaps, borders, animations)
- autostart.lua - startup apps

## Lua API

- hl.config({}) - global variables (general, decoration, animations, input)
- hl.monitor({}) - monitor rules
- hl.bind(key, action, opts) - keybinds
- hl.unbind(key) - remove binding
- hl.env(name, value) - env vars
- hl.gesture({}) - touchpad gestures
- hl.window_rule({}) - window rules
- hl.workspace_rule({}) - workspace rules
- hl.layer_rule({}) - layer rules
- hl.on("hyprland.start", fn) - run after start
- hl.dsp - dispatcher namespace (exec_cmd, focus, window, layout, workspace)
- o - Omarchy namespace (o.bind, o.launch_on_start, o.window)

## Syntax

- Config files are Lua
- Sections: name { ... }
- Colors: rgba(r,g,b,a), rgb(r,g,b), or 0xAARRGGBB hex
- Mod keys: SUPER, SHIFT, CTRL, ALT, CAPS, MOD2, MOD3, MOD5
- Config reloads on save; use hyprctl reload

## Examples

### General
```lua
hl.config({
  general = { gaps_in = 5, gaps_out = 20, border_size = 2, layout = "dwindle" },
  decoration = { rounding = 8, shadow = { enabled = true } },
  animations = { enabled = true },
})
```

### Monitors
```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
```

### Keybindings
```lua
hl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + C", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim"))
```

### Window rules
```lua
hl.window_rule({ name = "no-gaps", match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
```

### Input
```lua
hl.config({ input = { kb_layout = "us", kb_variant = "intl", numlock_by_default = true } })
```

## Per-monitor workspaces and the focus gotcha (4.5+)

On Omarchy 4.5 every monitor owns a block of ten workspace ids
(`default/hypr/monitor-workspaces.lua`, state in
`~/.local/state/omarchy/monitor-workspaces`), the stock `omarchy.workspaces`
widget lists its own monitor's block, and `Super + 1-0` means slot N of the
focused monitor. Model, diagnosis and the widget swap in depth: the
`omarchy-bar-modules` skill's per-monitor workspaces reference.

Workspace dispatches target the **globally focused** monitor by default, and a
`workspace`/`focusworkspace` dispatch on an id that is *already open on another
monitor* follows it there — so clicking a workspace pill can flip focus to the
other screen even if you focus the clicked monitor first.

- `hl.dsp.focus({ workspace = N })` acts on the currently focused output; if N's
  workspace is open elsewhere it jumps to that monitor. Focusing the monitor first
  (`hl.dsp.focus({ monitor = "<connector>" })`, accepts a name or l/r/+1/-1) is
  necessary but **not sufficient** to stop the jump.
- **Do not pin workspaces to outputs with
  `hl.workspace_rule({ workspace = "N", monitor = "HDMI-A-1" })` on 4.5+.** That
  was the 4.0-era fix for the jump, and it now fights the per-monitor blocks:
  Hyprland keeps the pinned ids alive on those monitors while block tracking
  treats them as another monitor's, so every reconcile renumbers them and the
  bar's workspace list churns (numbers appearing and disappearing). Reach for
  `o.workspaces.focus(slot, monitor)` when a pill must act on a named screen,
  and treat an existing pin block in `monitors.lua` as something to remove.
- Omarchy's `hyprctl dispatch "..."` wraps the arg as Lua (`hl.dispatch(...)`), so raw
  dispatcher names (
  `focusworkspaceoncurrentmonitor`, `workspace 3`) error — you must pass an
  `hl.dsp.*` expression. `focusworkspaceoncurrentmonitor` is **not** exposed in
  `hl.dsp`, so you cannot reach it this way; use workspace rules instead.
- Workspace rules only move empty/new workspaces; an *occupied* workspace already on
  the wrong monitor stays put after `reload` and the `workspace` dispatch follows it.
  To migrate it: `hyprctl dispatch "hl.dsp.workspace.move({ workspace = '2', monitor =
  'HDMI-A-1' })"` (verified working).
- The stock `omarchy.workspaces` widget is per-monitor on 4.5: it maps its own
  connector to a block read from the state file, so each bar lists its own
  screen. A pre-4.5 clone (`thord.workspaces` here) derives its list from
  `hyprctl workspacerules` plus what is on its monitor — with no rules left it
  lists 1-5 plus every open workspace on
  **every** bar, so both bars show both monitors' ids and keep churning. That is
  a symptom of the version mismatch, not a per-monitor feature; the fix is
  `omarchy plugin enable omarchy.workspaces --after omarchy.menu` plus
  `omarchy plugin disable <clone-id>`. Edit a *user* clone
  (`~/.config/omarchy/plugins/<id>/Workspaces.qml`), never the packaged copy.
  Plugins hot-reload on save; force with `omarchy-shell shell rescanPlugins`.
  On Omarchy, `hyprmoncfg` is a separate tool that manages workspace→monitor
  rules (not installed on this box) — don't double-manage rules if it gets
  added, and on 4.5 its rules are the thing to remove.

## Layout per workspace (4.5+)

4.5 owns the layout per workspace and the bar shows which one each workspace
uses, so a global layout setting is no longer "the default layout":

- `Super + L` cycles the focused workspace through tiling (dwindle), scrolling
  and floating (`Super + Alt + L` backwards), and records the choice per
  workspace id in `~/.local/state/omarchy/workspace-layouts/<id>.lua`; the active
  entry on the bar renders that layout's glyph instead of its digit, and
  clicking it cycles.
- Set the default for workspaces that have no record of their own with
  `omarchy hyprland workspace layout default <dwindle|scrolling|floating>` (it
  writes `…/workspace-layouts/default.lua`). Only when that file is absent does
  4.5 fall back to Hyprland's own `general.layout`.
- **Do not force `general.layout` in `~/.config/hypr/looknfeel.lua` as the way to
  pick the default layout.** It is the 4.0 way, it loses to any per-workspace
  record, and it reads as a leftover: the fresh file is the stock commented
  template plus whatever the user picked through the UI. Removing one means
  restoring that template (`/usr/share/omarchy/config/hypr/looknfeel.lua`, which
  is what the image seeds into `/etc/skel`) rather than deleting the file, then
  `hyprctl reload` and confirm with `hyprctl getoption general.layout -j`.
- Records outlive the workspace they described. A stale `<id>.lua` for an id that
  is not currently in use applies again if that id comes back — and under the
  per-monitor block model an id changes owners when monitors are swapped — so
  read `~/.local/state/omarchy/workspace-layouts/` before blaming the default.

## Where bindings actually live (read before claiming "nothing is bound")

`~/.config/hypr/bindings.lua` ships as commented examples only, so grepping it proves
nothing. Omarchy's real defaults are one file per topic in
`/usr/share/omarchy/default/hypr/bindings/*.lua` (`dictation.lua`, `media.lua`, ...),
loaded via `require("default.hypr.omarchy")`; a personal file that is all comments is
the normal state. Read the live list instead:

```bash
omarchy menu keybindings --print        # descriptions included
# agent shell: hyprctl needs the compositor env
SIG=$(ls -t /run/user/$UID/hypr | head -1); export HYPRLAND_INSTANCE_SIGNATURE=$SIG XDG_RUNTIME_DIR=/run/user/$UID
hyprctl binds | grep -B6 -i "<description substring>"   # modmask/description per bind
```

Dictation is bound by `default/hypr/bindings/dictation.lua` **only when
`omarchy-default-dictation` names an installed backend**: `ALT + SPACE` toggles,
holding `Alt_R` is push-to-talk (`bind_hold` start/stop with `ignore_mods`). With that
in place the backend's own hotkey stays off on purpose — voxtype's
`[hotkey] enabled = false` in `~/.config/voxtype/config.toml` is expected, and the
toggle to bind elsewhere is `omarchy dictation toggle` (or `voxtype record toggle`
directly). `voxtype setup compositor` is the fix if the held ALT modifier leaks into
typed output.

Disabling the backend (user asked for dictation off, keep it reversible):

```bash
systemctl --user disable --now voxtype.service     # daemon + its OSD die, no desktop disruption
cd ~/.config/omarchy/defaults && cp -p dictation dictation.disabled-voxtype.bak && : > dictation
```

An empty/absent `~/.config/omarchy/defaults/dictation` makes `omarchy-default-dictation`
exit 1, which is precisely what `dictation.lua` tests, so the binds stop being created —
no `/usr` change, no image rebuild. The keys stay bound in the **already running**
compositor until the config is loaded again, so ask before reloading (it remaps the
live desktop): `omarchy-restart-hyprctl`, or just let it happen at next login. The
systemd unit the backend installed is `~/.config/systemd/user/voxtype.service`, so
re-enabling is `printf 'voxtype\n' > ~/.config/omarchy/defaults/dictation && systemctl
--user enable --now voxtype.service` plus a model download. `~/.config/voxtype` is
recreated on first run; `~/.local/share/voxtype/models/` holds the ~141 MB whisper model.

## Daemons that inject a Lua watcher into the compositor

Some Hyprland companions (hyprglaze and friends) never poll the IPC socket: at
startup they install a Lua watcher into the compositor's Lua VM with `hyprctl
eval`, and that watcher pushes their state onto socket2 as `custom>>…` events.
Four things follow, all measured on 0.56.2:

- **Stopping the process does NOT remove the watcher.** The daemon's own exit path
  only cleans up its Zig state, so the timer and its heartbeat keep running in the
  compositor. They disappear only when the Lua state is recreated, i.e. on a config
  reload. Counted with the daemon dead: 3 watcher events in 6 s; after `hyprctl
  reload`: 0 in 8 s. So the "off" half of any toggle is **stop + reload** — and a
  second stop with nothing running should skip the reload rather than remap the
  desktop for nothing.
- **Start needs no reload**: a daemon launched after a reload re-installs its own
  watcher (events resume, surface renders).
- **`omarchy-restart-hyprctl` is literally `hyprctl "(--instance 0)" reload`** — the
  `--instance 0` fallback is why it still works from a menu, where
  `HYPRLAND_INSTANCE_SIGNATURE` is not exported. Prefer it over bare `hyprctl reload`
  in anything user-facing; both drop the watcher.
- **Detect the injection instead of guessing:** run
  [`scripts/hypr-ipc-watch.py`](scripts/hypr-ipc-watch.py) (socket2 event counter that
  splits out a given prefix) with the daemon down — a non-zero count means a watcher
  is still installed. It is also the cheapest way to tell whether a state-pushing
  tool is alive at all.

Prerequisites for this class of tool, worth checking before promising it works:
**Hyprland 0.55+ configured with `hyprland.lua`** (they refuse a classic
`hyprland.conf`), and a compositor whose `hyprctl eval` works — `hyprctl eval
'return 42'` → `ok`.

A background-layer daemon added beside Omarchy's own background surface does not
need `omarchy.background` disabled: both sit at layer level 0 and the one mapped
later is the visible one, which `hyprctl layers` shows as the order of the
`namespace:` lines. Stopping it reverts the wallpaper with nothing to restore.

## hyprctl commands

- hyprctl monitors all
- hyprctl clients
- hyprctl dispatch reload
- hyprctl configerrors

## Opacity and blur

Omarchy already sets window opacity: `/usr/share/omarchy/default/hypr/windows.lua` tags
every window `+default-opacity` and then applies `opacity = "0.985 0.96"`
(active / inactive) to whatever still carries the tag. Apps opt out in
`/usr/share/omarchy/default/hypr/apps/<app>.lua` with `-default-opacity`; terminals
(`apps/terminals.lua`) do NOT opt out.

Always-on rules when a user asks for a specific opacity:

- **An app's own alpha multiplies with that rule**, so the number they asked for is not what
  they will see: a terminal at `alpha=0.8` renders ~0.79 focused / ~0.77 unfocused. Report
  the effective value and offer the split - set the app alpha, or opt the app out of the tag
  and pin an explicit rule
  (`o.window("foot", { tag = "-default-opacity", opacity = "0.8 0.8" })`) - rather than
  presenting the requested number as the finished result.
- **Blur is off by default** (`looknfeel.lua`: `blur = { enabled = false }`), so transparency
  reveals a sharp wallpaper. Never tell the user blur will show through without reading the
  current state; enable blur first if that is what they are picturing.
- **Read what is already applied before editing:**
  `grep -rn "opacity\|blur" /usr/share/omarchy/default/hypr/ ~/.config/hypr/`.
- **Never kill or relaunch the user's running windows or terminals to apply a change.**
  State that existing windows pick it up when reopened and ask before touching them - a
  reload is not worth a lost shell.
- Terminal-side appearance (alpha, fonts, colors) lives in the terminal's own config, which
  survives `omarchy theme set`; a window rule is global to that window class. Layout, gotchas
  and verified commands: [`references/terminal-appearance.md`](references/terminal-appearance.md).

## Where the palette comes from (and dynamic theming)

Hyprland's border and group colors are NOT set in `~/.config/hypr/looknfeel.lua`: they come from the
active Omarchy theme, whose generated `hyprland.lua` is pulled in by
`require_optional.module("omarchy.current.theme.hyprland")` in
`/usr/share/omarchy/default/hypr/omarchy.lua`. So "change the border color" is a theme edit
(`colors.toml`, rendered through `default/themed/hyprland.lua.tpl`) that survives `omarchy theme set` —
a `looknfeel.lua` override only fights the theme.

Always-on rules when a palette is involved:

- **`colors.toml` in the active theme is the single input** for every themed surface (Hyprland
  borders, bar, notifications, lock screen, terminals). Edit or generate that one file, then
  `omarchy theme refresh` — it re-renders the active theme in place, no theme switch needed.
- **No hook fires when the wallpaper changes.** `omarchy theme bg set|next` only repoints
  `~/.local/state/omarchy/current/background` and tells the shell over IPC, so a
  wallpaper→palette pipeline needs a systemd user **path unit** on that state dir, not an Omarchy
  hook.
- **Never hook or patch a packaged script** (`/usr/share/omarchy/bin/omarchy-theme-bg-next` and
  friends): an edit there is lost on the next image build, and on `fedora-ostree` `/usr` cannot be
  written at all.
- Per-app template overrides for every theme go in `~/.config/omarchy/themed/<config>.tpl`.
- Palette details (the 24 `colors.toml` keys, the matugen role mapping, wallpaper linking, prior
  art and the Fedora/matugen packaging options):
  [`references/dynamic-theming.md`](references/dynamic-theming.md).

## Pinning refresh rates

Refresh is part of the mode string: `mode = "1920x1080@120.00"` in `monitors.lua`.
Read `hyprctl monitors all` -> `availableModes` first: the requested rate must exist on
that panel (e.g. an Acer V227Q tops out at 100Hz while a Philips 27E1N1200A does 120Hz),
and a rate the panel does not advertise silently falls back rather than erroring.
Apply the same way as a move: edit `monitors.lua`, `hyprctl reload`, then confirm the live
rate with `hyprctl monitors` (`1920x1080@120.00000 at 1920x0`) and `hyprctl configerrors`.

## Moving/reordering monitors at runtime

The non-legacy (Lua) parser rejects live `hyprctl keyword monitor ...` AND
`hyprctl keyword eval 'monitor ...'` with "keyword can't work with non-legacy
parsers. Use eval." - a runtime monitor move is a dead end on a Lua config.
The working path is: edit `monitors.lua`, then `hyprctl reload`, then confirm
with `hyprctl monitors all` and `hyprctl configerrors`. `hyprctl reload`
briefly remaps the live desktop, so get permission first (see the always-on
rules under DPMS churn above).

To swap two monitors' physical positions, the wildcard rule
`hl.monitor({ output = "", position = "auto" })` does NOT encode order - it
auto-assigns by connector, so a reload returns to the same wrong layout. Pin
explicit per-output rules for each connector with literal `position` values
(after the wildcard, so they override it), e.g. the left monitor at `0x0`
and the right at `<width>x0`. Explicit rules persist across reboots; the
wildcard does not.

## Diagnosing monitor power / DPMS churn

Displays that blink, drop signal, or appear to power-cycle - especially while the session is locked
or idle - are diagnosed from Hyprland's own log plus the shell journal. Full procedure, counters,
decisive test, and fix order: [`references/monitor-dpms-churn.md`](references/monitor-dpms-churn.md).
Re-runnable timestamped capture (per-connector sysfs state + log-counter deltas + udev DRM events):
[`scripts/monitor-churn-capture.py`](scripts/monitor-churn-capture.py).

Always-on rules for that work:

- `HYPRLAND_INSTANCE_SIGNATURE` is usually unset in the agent's shell even while a session runs:
  `export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$UID/hypr | head -1)`, then confirm with
  `hyprctl version` — take the signature from the TOP LEVEL of `…/hypr/`; listing one
  level deeper (`…/hypr/*/`) returns `hyprland.log` and hyprctl then cannot connect.
  Without it every `hyprctl` call fails with "HYPRLAND_INSTANCE_SIGNATURE not set".
- `/run/user/$UID/hypr/<sig>/hyprland.log` has **no timestamps** and is written through a
  fully-buffered pipe: count events in it, take timing from `journalctl --user -t omarchy-shell`,
  and never quote a wall-clock time for one of its lines.
- The Omarchy screen locker is a Quickshell ext-session-lock plugin (not hyprlock) and blanks the
  panels with `hyprctl dispatch dpms disable` 5 s after locking, while
  `misc:mouse_move_enables_dpms` / `misc:key_press_enables_dpms` are true by default - so the
  compositor re-lights DPMS on any input and the lock re-arms the blank timer. That pair is the
  usual mechanism behind "monitors power-cycle on a loop while locked".
- Anything that blanks or locks a live session (`hyprctl dispatch dpms disable`, `hyprctl reload`,
  `omarchy system lock`) interrupts the desktop Hermes is running inside: ask first, and do the
  read-only probing (`/sys/class/drm/*/status`, `udevadm monitor --subsystem-match=drm`, log
  counters) before it.
- Report proven counters separately from the inferred trigger - churn counts show what happened,
  not who started it.
- **Gate on the idle service first:** `omarchy-shell idle status` returns one JSON blob; if
  `enabled:false` / `stayAwake:true`, no timer in the shell is blanking anything and the whole
  lock/idle blank-wake path is out of play. Then a screen that "sleeps" was switched off by an
  action - find that action before measuring anything else.
- **Per-output off and global DPMS are different mechanisms, and only one is persisted.** Global
  blank is `omarchy-brightness-display off|on` -> `hl.dsp.dpms({ action = "disable"|"enable" })`
  (what the locker calls; it hits every output). One output off while it stays plugged in is
  `hyprctl eval 'hl.monitor({ output = "HDMI-A-2", disabled = true })'` - what the bar's monitor
  panel does. `hyprctl eval` changes the live config only, so a later `hyprctl reload` re-reads
  `monitors.lua`, which carries no `disabled` rule, and the display comes back: any reload-driven
  loop re-lights a screen the user switched off.
- **`~/.config/hypr/*.lua` ship as commented templates.** Grepping them for `dpms`/`misc` and
  finding nothing proves nothing - the effective values come from `/usr/share/omarchy/default/hypr/`.
  Read the packaged file, or ask the compositor: `hyprctl getoption misc:mouse_move_enables_dpms`.

## Tips

- Split config into files, require them
- Use pcall(require, ...) for missing modules
- Set omarchy_default_bindings = false before loading Omarchy defaults
- Unbind then rebind to change an existing key
- Layouts: dwindle (default), master, scrolling
- Reading `/usr/share/omarchy/` (bin scripts, default configs, packaged shell QML) is safe and the
  fastest way to learn how a command or the lock/idle path actually behaves; never edit it - it is
  package-owned and overwritten on update.
- New Omarchy desktop-customization lessons belong in THIS skill: the `omarchy` skill can be read
  with skill_view but skill_manage refuses it (not in the active profile), so patches against it fail. Bar/widget-specific lessons go to the `omarchy-bar-modules` skill instead.
- Comments you add to a user config file must state only what you verified against the real config
  (read the shipped defaults / man page first). Do not assert runtime behavior such as "blur shows
  through" without checking that it is enabled.