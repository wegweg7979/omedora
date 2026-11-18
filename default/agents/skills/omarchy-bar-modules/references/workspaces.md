# Per-monitor workspaces and the bar switcher (Omarchy 4.5+)

## The block model

- Every monitor owns a **block of ten Hyprland workspace ids**: first monitor
  1-10, the next 11-20, then 21-30. Hyprland still numbers globally; Omarchy
  partitions the number space per monitor.
- Ownership is keyed to the monitor's **description (make, model, serial)**, not
  its connector — a dock renames connectors between plugs, and Hyprland hands a
  freed id to whichever display appears next — and is persisted as
  `block<TAB>connector<TAB>identity` lines in
  `~/.local/state/omarchy/monitor-workspaces`. The lowest unused block goes to a
  monitor seen for the first time, so an established state file decides which
  monitor owns 1-10, not today's plug order. The internal panel sorts first and
  takes the first block.
- `default/hypr/monitor-workspaces.lua` is the authority — read it before
  reasoning about a numbering. It hooks `monitor.added`, `monitor.removed`,
  `config.reloaded` and `hyprland.start`, and on each one puts every monitor on a
  workspace of its own block, brings a returning monitor's workspaces home, and
  **renumbers** (`workspace.change_id`) workspaces stranded by an unplug into the
  block they landed on, remembering the origin in
  `~/.local/state/omarchy/monitor-workspaces-merged`.
- Consequence: workspace ids are NOT stable across reloads and hotplugs. A key,
  window rule or script naming a raw id is wrong on every monitor except the one
  that owns that block. Prefer `Super + 1-0`, `o.workspaces.focus(slot,
  monitor)` and `o.workspaces.move_window(slot, follow)`.

## What the stock widget renders

`/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml` — read it before
judging a list.

- A `FileView` watches `monitor-workspaces` to map its connector → block, so each
  bar lists **its own** monitor's block, labelled 1-10, whichever monitor has
  focus. A widget that instead resolves the *compositor's focused* monitor makes
  every bar show the same list.
- `workspaceIds()`: always slots 1-5; then any of its own slots 6-10 that exist;
  then workspaces of *another* monitor that are visiting this one ("guests", set
  apart by a gap). Entries appearing and disappearing as workspaces are
  created/destroyed is designed 4.5 behaviour — a static 1-5 row is not.
- The **active** entry renders the layout glyph (square = dwindle, circle =
  scrolling, triangle = floating) instead of its digit; clicking it cycles the
  layout, clicking another entry focuses it, and the wheel scrolls one step,
  holding at the ends. `Super + Tab` / `Super + Ctrl + Tab` / `Super`+scroll stay
  on the current monitor's workspaces.
- A clone of this widget inherits the version it was copied from. The pre-4.5
  shape derives its list from `hyprctl workspacerules` plus what is on its
  monitor; with no rules left it falls back to "1-5 plus every open workspace",
  so both bars list both monitors' raw block ids and keep churning — swapping in
  the stock widget is required, not optional.

## Diagnose "extra workspaces appearing and disappearing"

1. `hyprctl workspacerules -j` — any rule mapping 1-10 to a monitor is a 4.0-era
   pin fighting 4.5 (`grep -rn 'workspace_rule' ~/.config/hypr/`).
2. `cat ~/.local/state/omarchy/monitor-workspaces` (block per connector) and
   `…-merged` (workspaces renumbered while another monitor was unplugged).
   `…-merged` is rewritten empty at every Hyprland start, so rows naming a
   retired monitor are harmless.
3. `hyprctl monitors -j` / `hyprctl workspaces -j` — each monitor's active
   workspace id and every live workspace with its monitor. A monitor sitting on
   an id outside its own block is the symptom.
4. `omarchy plugin list` — which workspace widget the bar actually runs.

## Fix: return to the stock arrangement

1. Back up first: `cp ~/.config/hypr/monitors.lua{,.bak.$(date +%s)}` and the
   same for `~/.config/omarchy/shell.json`.
2. Delete the `hl.workspace_rule` pins from `~/.config/hypr/monitors.lua` and
   leave a comment saying why, so they do not return. Keep the `hl.monitor({…})`
   lines — physical mode/position/scale is a separate concern.
3. Swap the widget: `omarchy plugin enable omarchy.workspaces --after
   omarchy.menu`, then `omarchy plugin disable <clone-id>`. There is no
   `omarchy bar remove`; for a `bar-widget` the enable/disable verbs ARE the bar
   layout verbs (`shell.pluginRegistry.inBar`), so this adds and removes the
   `shell.json` layout entry.
4. Verify from tool output: `hyprctl reload`, `hyprctl configerrors` (empty),
   `hyprctl workspacerules -j` (pins gone), `hyprctl workspaces -j` (each monitor
   on its own block), `omarchy plugin list` (stock widget enabled, clone
   disabled), `journalctl -t omarchy-shell` (the stock widget instantiated).
5. Say before starting that the numbers shift once, and where each workspace
   lands — removing the pins renumbers live, and the user is watching the bar.

## Aftermath decisions

| Situation | Effect | Call |
|---|---|---|
| A retired monitor still owns a low block in the state file | Live monitors keep high ids (11-20, 21-30) underneath while the bar still labels 1-10 | Leave it. Reclaiming low ids needs the state file's monitor lines cleared **and** a Hyprland restart — another renumber |
| Stale `…-merged` rows for a monitor that is gone for good | `restore()` finds no connected monitor with that identity and skips | Leave it; rewritten at the next Hyprland start |
| Fewer than ten workspaces in use on a monitor | The bar still shows slots 1-5, dimmed while empty | Expected; do not "fix" it by hiding empty workspaces |

## When the bar default ships from an image payload

If the layout comes from an image payload (`/usr/share/<vendor>/config/.config/omarchy/shell.json`,
`/etc/skel/.config/omarchy/shell.json`) rather than `~/.config`, the default is a
**repo decision, not just a box fix**: a payload that ships a pre-4.5 workspace
widget answers a question the new base no longer asks, so every fresh install
reproduces the churn. Fix the live box first, then fold the change into the
payload (see the distro/payload section of SKILL.md), leave the replaced plugin
shipped-but-disabled, and re-run the payload plan against a machine that already
has the config before building.

Three things to say out loud while doing it:

- **Prefer the stock widget in the payload to shipping a clone of it.** A clone
  is a copy of one base version's internals, so shipping it turns every later
  base change into visible churn on fresh installs — exactly the defect the
  payload cannot be re-checked for on its own. Vendor a plugin only for
  behaviour the base does not have (here, the battery-less power-profile
  picker); where the base ships the widget, the payload's bar should name it.
- **Replay never deletes.** Dropping the clone (or a `looknfeel.lua` override)
  from the payload stops it reaching new users and leaves it on every machine
  that already has it, so the live boxes need the change made deliberately —
  by hand with a backup, one box at a time.
- **Rebuild the payload's bar config against the new base's schema; do not patch
  the old shape.** Its `centerAnchor`-era layout is migrated in `$HOME` only, so
  a payload left as-is keeps working on upgraded boxes and writes the pre-4.5
  shape over a working file the next time it runs.
