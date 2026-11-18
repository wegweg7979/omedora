---
name: quickshell
description: "Build custom desktop shells on Linux with QtQuick/QML: bars, widgets, lockscreens, display managers. Qt6-based, hot-reloading, Wayland+X11 with Hyprland/I3/Sway integrations. Fedora via omedora COPR."
version: 0.1.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [quickshell, qtquick, qml, desktop-shell, hyprland, wayland, x11, omedora, fedora, status-bar, widget, lockscreen, display-manager]
    related_skills: [fedora-atomic-hurunagus, hyprland-config]
---

# Quickshell Skill

This skill covers building custom desktop shells with **Quickshell**, a QtQuick-based toolkit for composing desktop components (status bars, widgets, lockscreens, display managers) using QML.

## When to Use

Use this skill when the user asks to:
- Build or run a Quickshell desktop configuration (shell, bar, widget, lockscreen)
- Configure a Quickshell config for **Hyprland**, Sway, or X11
- Install/use Quickshell on Fedora (omeda COPR `quickshell` package)
- Debug a Quickshell QML config (hot-reload, IPC, logging, QML debugger)
- Write QML for a status bar, system tray, MPRIS media player, or lockscreen

## Quick Reference

| Concept | Detail |
|---|---|
| Framework | QtQuick 6 (QML) — declarative UI description language |
| Config format | QML files; hot-reloads on change |
| Display servers | Wayland + X11 |
| Compositor integrations | Hyprland, I3, Sway (window mgmt, screen recording via Wayland) |
| Audio | PipeWire |
| Media | MPRIS (media players) |
| System tray | StatusNotifierItem |
| Bluetooth | BlueZ |
| Auth / lockscreen | PAM, Greetd (display manager) |
| Battery | UPower |
| Power profiles | Power Profiles Daemon |
| Install (Fedora) | `dnf copr enable errornointernet/quickshell`, then `dnf install quickshell` (or `-git` for master) |

### CLI

- `quickshell` / alias `qs` — run a config
- `-c, --config NAME` — run named config under `$XDG_CONFIG_HOME/quickshell/<NAME>/shell.qml`
- `-p, --path PATH` — run a QML file or config folder (env `QS_CONFIG_PATH`)
- `-d, --daemonize` — detach from the terminal (run as background service)
- `-n, --no-duplicate` — exit if another instance of the same config is running
- `-v` / `-vv` — INFO/DEBUG verbosity
- `--debug PORT` + `--waitfordebug` — QML debugger; useful for inspecting the live UI
- Subcommands: `log`, `list`, `kill`, `ipc`, `msg` (deprecated; moved to `ipc call`)

### Config layout

```
$XDG_CONFIG_HOME/quickshell/<config-name>/shell.qml   # or shell.qml for 'default'
$HOME/.config/quickshell/shell.qml                    # default config (no subdir)
$HOME/myshell/shell.qml                               # run with: qs -p ~/myshell
```

## Core Concepts

### QML structure

Every QML file starts with imports. Root object is typically `Item` or a Quickshell shell type. Key QML facts:

- `id` assigns a name to an object (scope binding).
- Property bindings: `width: 100`, `height: width` — reactive updates.
- Property definitions: `property int myProp: 5;`
- `Object {}` assigns an object to a property.
- Signals: `signal foo(bar: int)` + handlers `onFoo: ...`.
- Attached signal handlers: `Component.onCompleted: ...`.
- Lambdas for inline functions; JS in expressions is standard.

### Layout (QML differs from CSS)

- `Row`, `Column`, `Grid` arrange children; `Flow` wraps.
- `spacing` controls gaps; `alignment`/`add` control placement.
- `layout` property and `Layout` attached properties.
- `width`/`height`/`x`/`y` are explicit; use `Layout.fillWidth`, `Layout.preferredWidth`, `Layout.minimumWidth` for responsive sizing.
- `parent`/`children`/`childAtIndex` for tree traversal.
- Use `Rectangle`, `Text`, `BorderImage`, `Svg`, `Item` (invisible container), `Flickable`/`ScrollView` for scrolling.

### Hot reload

- Modify QML and the shell reloads automatically (if running under a terminal / not daemonized). Changes are applied without restarting.
- Edit JS files referenced via `import "file.js" as NS` — also hot-reloads.

### IPC / inter-process communication

- `qs ipc` — communicate with other Quickshell instances.
- `qs ipc call <name> <msg>` to send messages.
- `qs ipc subscribe <topic>` / `qs ipc unsubscribe <topic>` for pub/sub.
- Useful for synchronizing multiple shell instances or notifying external apps.

## Guidelines

### Do
- Start small: one bar, then add widgets before a full shell.
- Use official examples and existing user configs as references ( configs vary widely and many are outdated).
- Reference the [QML Language Reference](https://quickshell.org/docs/guide/qml-language) and [QtQuick type index](https://quickshell.org/docs/guide/qml-language).
- Use `qs -v` to see internals while debugging.

### Don't
- Don't expect CSS-like layout; QML uses a scene-graph model (Item tree + layout + `anchors`/`width`/`height`).
- Don't ship configs without testing for both Wayland and X11 if targeting both.
- Don't rely on AUR/Home-brew fastest updates; Qt upgrades can break Quickshell (AUR warning path exists).

## References

- [quickshell.org (docs)](https://quickshell.org/)
- [About Quickshell](https://quickshell.org/about/) — integrations list, is-it-for-me
- [Usage Guide](https://quickshell.org/docs/guide/) — install, guided intro, QML overview, size/position
- [QML Language Reference](https://quickshell.org/docs/guide/qml-language) — syntax, bindings, signals
- [Official Examples](https://git.outfoxxed.me/quickshell/quickshell-examples) — code samples
- [Debian man page](https://manpages.debian.org/unstable/quickshell/quickshell.1.en.html) — quick reference
- [GitHub source](https://github.com/PlusieursFr0mage/quickshell) — reference implementation (separate from omedora's build)
- `templates/minimal-bar/` — copy-paste minimal bar config (`shell.qml`) to run with `qs -c mybar`
