---
name: omarchy-bar-modules
description: Adding Omarchy bar widgets, modules, or menu rows.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [omarchy, quickshell, hyprland, status-bar, qml]
    related_skills: [omarchy, hyprland-config]
---

# Omarchy Shell: Bar Modules and Widgets

## When to Use

- Adding, changing, or removing a widget or control on the Omarchy bar.
- Writing a bar-widget plugin (`manifest.json` + entry-point QML).
- Adding a row or dynamic provider to the Omarchy menu.
- Debugging why a bar control does not appear (battery-gated widgets, hidden
  `command` modules, QML errors).
- Changing the bar/widget defaults of the omedora (Fedora) fork.

For adding a control to the Omarchy status bar (Quickshell under
`/usr/share/omarchy/shell` or an omedora fork), writing a bar widget plugin, or
adding a row to the Omarchy menu. The `omarchy` skill is the general end-user
guide; this one holds the implementation detail it does not carry.

## Cheap path: a `command` module in shell.json

```json
{ "id": "vpn", "type": "command", "exec": "~/script --status",
  "interval": 5, "tooltip": "VPN", "onClick": "~/script --next",
  "onRightClick": "~/script --menu" }
```

- Lives under `bar.layout.<left|center|right>` in `~/.config/omarchy/shell.json`;
  that file hot-reloads on save. `exec` runs via `bash -lc` (`$HOME` expands).
- Output: plain text, or Waybar JSON `{"text":"…","tooltip":"…","class":"active"}`.
  `class: "active"` paints the glyph in `bar.urgent`.
- Printing an empty `text` (no `keepSpace`) hides the module — the only way a
  command module can choose not to appear on a given machine.
- PITFALL: every command module logs `TypeError: Cannot assign to read-only
  property "moduleName"` (`Bar.qml` `injectProps()` assigns injected props onto
  `CustomCommandModule`, whose `moduleName`/`settings` are readonly). Harmless,
  but it fires on every shell.json save — ship a QML widget when the result is
  meant to be permanent.
- Read errors with `journalctl -t omarchy-shell --since "-60s"`. The shell is
  NOT a systemd unit; the journal identifier is `omarchy-shell`.

## Pitfall: a widget that renders itself invisible

Some first-party widgets size their visibility off their own content, so a
failed data fetch reads as "the widget was removed": `omarchy.weather`'s
BarWidget is `visible: panelLoader.item && panelLoader.item.label !== ""`. When
`~/.local/state/omarchy/settings/weather.json` carries coordinates
(`hasConfiguredCoordinates`), **only** the open-meteo daily fetch sets that
label; wttr.in can no longer fill it, so if the open-meteo request fails the
pill disappears while the layout stays correct (`omarchy plugin list` shows it
enabled, `omarchy-shell shell listPlugins` has no per-widget label to read, and
the journal stays clean — Process stderr is not logged).

Diagnose by replaying the widget's own request instead of reading QML: grep the
panel for its `curl` command, run it verbatim, and check the HTTP code. Known
trigger: open-meteo's edge answers **403 to a `curl/*` User-Agent on
`&timezone=auto`** (verified: same URL 200 with a browser UA, a custom UA, or no
UA, 403 with `curl/8.5.0`; UA-less without `timezone=auto` also 200).

Immediate fix from `$HOME` only (no image rebuild): drop the coordinates,
keeping the place name — `omarchy-weather-location --set "Newark on Trent"`
writes `{"name": ...}` alone, which flips the label source back to wttr.in.
`--clear` (deletes the file) also works but hands the place to IP auto-detect, so
it follows a VPN. The lasting fix is upstream's: drop the
`if (!root.hasConfiguredCoordinates)` guard around the wttr.in label assignment
so either provider can fill an empty icon (open-meteo still wins once it
answers) — that is upstream Omarchy code, so stage it in the omedora tree, never
in `/usr`.

A hurunagus host also carries a local delta on top: an identifying `-A` on both
Open-Meteo calls in the panel (`dailyForecastProc`, `geocodeProc`), because the
edge rejects curl's own UA on `timezone=auto` outright. That delta is what keeps
Open-Meteo data (day/night glyph, the panel's 3-day strip) alive on those
machines until upstream sends a UA of its own — a rebase that drops it loses
those two and leaves the pill riding on wttr alone, which the fallback fix no
longer hides but does keep visible.

Expect the failure to look sudden and unrelated to any local change: the fetch
failure paths keep `report`, `dailyForecastReport` and `label`, retrying without
clearing them, so a shell that fetched once keeps a stale icon through failed
refreshes and the pill only disappears on the next shell start (an image update
plus reboot, a theme/migration restart). Check the shell's start time before
blaming whatever was last edited.

**A provider fallback is not a fix for the blocked provider.** Once either
source can fill the icon the pill stops vanishing — but if the rejected provider
keeps rejecting, the widget is riding on the OTHER one alone, with zero real
redundancy, and the day/night glyph plus the open-meteo forecast stay lost. So
after carrying the fallback, re-test BOTH provider URLs from the shell's own
curl invocation and say which sources are actually live, rather than calling the
issue closed. Only the second fix — an identifying `-A` user-agent on the
open-meteo calls, which open-meteo's docs ask for — restores two working
sources.

## Bar widget plugin

Third-party: `~/.config/omarchy/plugins/<id>/{manifest.json, <Entry>.qml}`.
Manifest needs `schemaVersion`, `id`, `name`, `version`, `author`,
`kinds: ["bar-widget"]`, `entryPoints.barWidget`, and `barWidget`
(`displayName`, `description`, `category`, `allowMultiple`, optional
`defaultSection`, `defaults`, `schema`). Then `omarchy-shell -q shell
rescanPlugins`, `omarchy plugin list`, `omarchy plugin enable <id>` (writes the
layout entry at `defaultSection`).

**A popup widget is ONE plugin — the bar entry point may itself be the popup.** No
separate `panel`-kind plugin is needed: first-party `omarchy.audio` declares
`kinds: ["bar-widget"]` with `entryPoints.barWidget = "panels/audio/Panel.qml"`, and the
payload's `thord.powerprofile/PowerProfile.qml` is the third-party template to copy —
a `Panel { moduleName; ipcTarget }` root holding the `BarIconButton` (glyph in `text` as
a `\uXXXX` escape, `slotSize: Style.bar.iconSlot * 2` when a label is shown,
`onPressed` → `root.toggle()`, right/middle click to cycle through values) plus an inner
`KeyboardPanel { owner: root; open: root.opened }` whose content is the popup, with a
`PanelKeyCatcher` for arrows/Enter/Escape. `Panel` supplies `opened`,
`open()/close()/toggle()` and the `IpcHandler`, so `omarchy-shell <ipcTarget> open`
drives the same popup from a script. A widget whose backing app is absent hides itself
with `visible: configured` + `implicitWidth/Height: 0`. Refresh in `onOpenedChanged`
(plus a slow Timer while visible for the glyph) and set the displayed value
optimistically, so the icon turns over on click rather than a poll later.

For a payload-shipped widget the layout entry in the payload's `shell.json` IS the
enablement — ship the plugin dir and that line together, aligned with where
`omarchy plugin enable` would insert it. When the widget edits another app's settings,
prefer writing THAT app's own config file and letting it hot-reload over restarting its
units; the worked-out contract (config path, key precedence, which keys have an upstream
writer, how lenient the parser is) is the "Settings surface" section of this agent's
fedora-atomic-hurunagus skill.

First-party (in an omarchy/omedora source tree):
`shell/plugins/panels/<name>/{Panel.qml, manifest.json}` with id
`omarchy.<name>` plus placement in the default `config/omarchy/shell.json`.

Native-looking pieces:

- `qs.Ui.Panel` — adds `open()/close()/toggle()` and the `IpcHandler` for
  `ipcTarget`; panels must expose `open(payloadJson)`/`close()`.
- The bar injects `bar`, `moduleName`, `settings`; `setting(key, fallback)`
  reads the widget's own shell.json entry.
- `qs.Ui.KeyboardPanel { anchorItem; owner; bar; open; focusTarget }` for the
  popup, `qs.Ui.PanelKeyCatcher` for keyboard (`moveRequested`,
  `activateRequested`, `closeRequested`, `tabRequested`). Layer namespace is
  `omarchy-keyboard-panel` — what the acceptance tests assert on.
- `Panel.barForeground` and `bar.fontFamily` work for first-party (Bar root) and
  third-party (PluginBarApi) alike.
- Data: `Process` + `StdioCollector`; poll with a `Timer` (`running:
  root.opened` while open, plus a slow one to keep the bar glyph current).

## Workspace widgets are a subsystem, not a label list

A workspace switcher on the bar is coupled to how the compositor numbers
workspaces, and Omarchy 4.5 changed that numbering. Before editing one, or
explaining numbers that come and go, read
[`references/workspaces.md`](references/workspaces.md): the per-monitor block
model, what the stock `omarchy.workspaces` widget renders, the `omarchy plugin
enable/disable` swap, and why pinning workspaces with `hl.workspace_rule` makes
the bar churn.

## Menu rows and providers

`~/.config/omarchy/extensions/omarchy-menu.jsonc` (user) or
`default/omarchy/omarchy-menu.jsonc` (source). Dotted ids imply hierarchy;
`provider: "<name>"` makes a submenu dynamic from the provider declared in
`shell/plugins/menu/Menu.qml` (rows are `label\tvalue\tcurrent`; the action
comes from the provider's `actionFor`).

`power-profiles` ships declared but referenced by no stock row, so one line adds
a working CPU power-profile picker to the menu:

```jsonc
"system.power-profile": {"icon":"\uf0e7","label":"Power profile","provider":"power-profiles"},
```

`omarchy menu summon <dotted.id|alias>` opens at a route; `omarchy menu refresh`
re-parses the JSONC without a shell restart.

## Why battery-less machines had no power-profile control

`omarchy.power` gates its whole panel on `visible: batteryPresent`, and the
`omarchy.battery` service only restores profiles on AC/battery transitions — so
a desktop/VM (`omarchy-hw-laptop` exits 1, no UPower battery) has neither, even
though `omarchy-powerprofiles-list/set` (`performance`/`balanced`/`power-saver`,
via the ppd/tuned-ppd PowerProfiles D-Bus API) works. Check `omarchy-hw-laptop;
echo $?` and `powerprofilesctl get` before blaming the shell.

## Verify on the live session

```bash
# Wayland env lives on the shell process, not on the agent's shell
tr '\0' '\n' < /proc/$(pgrep -f 'quickshell -n -p' | head -1)/environ |
  grep -E 'WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR'
# /run/user/<uid>/hypr/ also holds hyprland.log: take the signature directory
# that contains .socket.sock (ls -d /run/user/$UID/hypr/*/.socket.sock), not the
# newest entry by name, and export HYPRLAND_INSTANCE_SIGNATURE from it or
# hyprctl cannot connect.
grim -o HDMI-A-1 shot.png     # or grim -g "x,y WxH" for a bar strip
hyprctl layers                # which layer surfaces are mapped
omarchy-shell <ipcTarget> open   # direct verb; `shell call` needs 3 args
```

Inspect the pixels only when nobody in the conversation can see the screen — a
remote box, an image build, a headless VM: load the PNG with vision and ask about
clipping, tofu boxes, spacing, and which row is highlighted. On the user's OWN
desktop, verification is tool output (`hyprctl`, `omarchy plugin list`,
`journalctl -t omarchy-shell`): do not screenshot a screen the user is looking at,
and do not crop and re-crop it to read a label they can read themselves. Report
the state change instead.

## Showing a value beside a bar glyph (icon + text)

`BarIconButton` (qs.Ui) takes `labelText` for a label drawn next to the glyph;
the documented example is the battery percentage and `panels/power/Panel.qml` is
the reference: `labelText` = the value, **plus `slotSize: Style.bar.iconSlot * 2`
to make room**. The button's width is its `fixedWidth`, which BarIconButton sets
to `slotSize` and then centers glyph+label inside — so a label on an un-widened
slot overhangs its neighbours rather than widening the widget.

Changing one widget's rendering is a clone: `omarchy plugin clone omarchy.weather`
gives `~/.config/omarchy/plugins/<user>.weather`, disables the packaged widget and
enables the clone *at the packaged widget's exact position* in the layout (no
reordering to fix up). The clone is a FROZEN copy of the whole plugin: upstream
panel changes and any local carry (the Open-Meteo UA, the wttr fallback) do NOT
reach it, so copy those into the clone's own files and expect hand-syncing; a
change meant to last belongs in omedora (image) instead.

Verifying a bar-widget edit without looking at the screen: `omarchy plugin
validate <dir>`, `qmllint-qt6 <file>` (only `unresolved-type`/
`missing-property`/`inheritance-cycle` noise is expected — those types come from
the shell's import path; parse errors would say so), then **`omarchy-restart-shell`**.
A file edit alone does NOT re-instantiate a running widget: the plugin watcher
rescans the registry (and `omarchy-shell -q shell rescanPlugins` refreshes it),
but the bar keeps the instance it already built, so the new QML shows up only
after a shell restart — a widget that "didn't change" is usually this, not a
broken edit. Clone edits therefore cost one restart, and it is safe to spend.

Do not plan a debug probe with `console.log`: plugin QML console output reaches
neither `log.qslog` (binary trace, read with `strings`/`grep -a`) nor
`journalctl -t omarchy-shell` — a probe Timer that never appears in either log
proves nothing about whether it ran. Verify from behaviour (does the pill show
the value?) and the syntax gates instead.

## Pitfall: glyph stripping

The `patch` fuzzy matcher can silently drop a private-use codepoint from a line
it rewrites (seen: a Nerd Font glyph in a comment in `omarchy-menu.jsonc` came
back empty). Anchor patches tightly, write new glyphs as `\uXXXX` escapes (valid
in JSON and QML strings), and if one is lost, restore the exact bytes with
Python from the packaged copy under `/usr/share/omarchy/`.

## Changing the distro: omedora vs the Hurunagus payload

Two repos, two jobs — pick deliberately, because they are not interchangeable:

- **omedora** (`~/omedora-inspect`, github wegweg7979/omedora) is the Fedora
  rebase of Omarchy and installs `/usr/share/omarchy`. Its
  `config/omarchy/shell.json` and `default/omarchy/omarchy-menu.jsonc` are
  rebased against upstream and churn constantly (upstream ships new bar
  widgets by editing exactly those lines), so anything added there is a
  recurring conflict. Read `AGENTS.md` → `agents/skills/shell-dev.md` before
  touching `shell/`. Gates: `test/shell.d/manifest-entrypoints-test.sh` and
  `bar-widget-contract-test.sh` enumerate every manifest automatically (a new
  widget is covered without editing them); `config-test.sh` asserts every
  default bar widget id resolves to a manifest; `test/acceptance.d/panels-test.sh`
  has hand-maintained panel lists.

  Running those gates from a checkout: `panels-test.sh` drives the *installed*
  shell in the live session, so a checkout-only edit cannot make it pass and it
  fails (15s timeouts on layer surfaces) on a pristine tree too — `git stash`
  and rerun before blaming the change. Cheap, relevant, and self-contained for a
  shell/panels edit: `weather-test.sh` (or the matching `*-model`/widget test),
  `qml-text-format-test.sh`, `config-test.sh`, `bar-test.sh`,
  `manifest-entrypoints-test.sh`, `bar-widget-contract-test.sh`. Do not loop all
  of `test/shell.d/` in one agent call — several tests reach the network and
  hang, and a single timeout kills the whole loop with nothing reported.
  QML under `shell/` needs
  `omarchy-restart-shell` in a running session.
- **hurunagus-hyprland** (`~/hurunagus-hyprland`, github wegweg7979/hurunagus-hyprland)
  is the bootc image. `/usr/share/hurunagus/config` is its "Hurunagus deltas
  only" payload: `omarchy-hurunagus-configs` replays it into `$HOME` (missing →
  write, identical → no-op, differs → back up to `.pre-hurunagus-<ts>` then
  write) and the build seeds `/etc/skel` from the same tree. It ships the bar
  config (`.config/omarchy/shell.json`), `shell.toml`, branding, backgrounds,
  `foot.ini` and its own vendored `thord.powerprofile`. **A user-facing bar
  widget belongs here**, as a delta — no package change, no upstream conflict
  surface. Change the payload's `shell.json`, not `config/omarchy/shell.json` in
  omedora.

Two rules that keep that payload honest:

- **A payload is frozen while upstream keeps moving.** Omarchy's migrations
  rewrite the `$HOME` copy only, so an upgraded box keeps working while the
  payload silently falls behind, and the next replay writes the OLD shape back
  over a working file. On every upstream MAJOR bump, rebuild the payload's
  `shell.json` from the new `$OMARCHY_PATH/config/omarchy/shell.json` with the
  deltas re-applied, and re-check every other payload file against its new
  default. Schema moves are invisible otherwise — the bar's one `center` list +
  `centerAnchor` became `centerBegin`/`center`/`centerEnd`/`tray`, and a payload
  that predated the per-monitor block model shipped a workspace widget keying
  off `hl.workspace_rule`, i.e. the churn the new base had already replaced (see
  `references/workspaces.md`).
- **Replay only ever writes; it never deletes.** Dropping a file or a plugin
  from the payload reaches new users only, and changes nothing on machines that
  already have it — say so when dropping one, and change those boxes
  deliberately (by hand, with a backup). Mirror of the image-side rule that a
  rebase never re-seeds `/etc/skel` into an existing `$HOME`. Keep the helper's
  own `#` inventory comment (which payload entries exist and what each changes)
  in step with the payload in the same commit: it is the only statement of what
  the deltas ARE, so a stale line reads as intentional.

How to verify a payload change without an image rebuild:

```bash
P=$PWD/system_files/usr/share/hurunagus/config
HURUNAGUS_CONFIGS_DIR="$P" omarchy-hurunagus-configs --plan --no-theme
```

Aim for `create N, back up 0, leave M unchanged` against a machine that already
has the config: any `backup` line means the payload disagrees with the live
arrangement (often widget *order* — `omarchy plugin enable` inserts at
`barWidget.defaultSection`, so align the payload to where enable puts it, or the
next replay silently reshuffles the bar).

Only upstream-Omarchy-bound fixes (and genuine Fedora porting work) need the
omedora tree; if a widget is meant for Omarchy proper, the package tree is the
staging ground, since Hurunagus-only delivery never reaches omedora users
elsewhere.
