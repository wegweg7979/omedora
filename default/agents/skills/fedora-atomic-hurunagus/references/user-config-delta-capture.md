# Harvesting the user's own config onto the image

Use when the user asks for "a script like `omarchy-reinstall-configs` but it loads my
custom settings", "copy the look and feel / shell settings I changed from the omarchy
defaults", or any capture-and-reapply of their own desktop config into the image. The
SOURCE is the live box's `$HOME`; the shipped defaults are the baseline.

## Rule 0 — the user names the payload set

Inventory and PRESENT; do not design the payload path, the script, the install
location, or the file layout before the user has picked the set. A capture request is
answered with a table of concrete deltas (`path` + `what actually differs`) plus an
explicit EXCLUDED list with reasons, then STOP. Moving straight to "here is the payload
dir and the wrapper design" gets corrected for assuming which settings are in scope.

## Baselines to diff against

| Baseline | What it is |
|---|---|
| `/etc/skel/.config` | Defaults the IMAGE ships: the `omedora-settings` skel payload PLUS this repo's `system_files/` overlay (build.sh runs `cp -avf /ctx/system_files/. /` AFTER `dnf5 install -y omedora omedora-settings`, so hurunagus wins) |
| `/usr/share/omarchy/config` | Omarchy's own payload (`$OMARCHY_PATH/config`) |
| `~/.local/state/omarchy/current/theme/` | RUNTIME-GENERATED theme payload (the target of the generated symlinks/copies in `~/.config`) |

A `<path>.pre-omedora-<ts>` file in `$HOME` is proof `omedora-adopt-user` — what
`omarchy-reinstall-configs` dispatches to on `fedora-ostree` — has already run there.

## Procedure

1. Confirm what the user means by "my settings" (categories: bar/shell, look-and-feel,
   terminals, keybinds, theme/wallpapers) — see Rule 0.
2. Run `scripts/config-delta.py` (read-only three-way classify vs `/etc/skel`: ADDED /
   MODIFIED / DELETED, tagging each modified file `omarchy-default`, `hurunagus+user`,
   or `not-in-omarchy`). Trim its NOISE set for the user in question.
3. `diff -u` EVERY MODIFIED hit. A byte diff is not a user edit — see traps.
4. Present surviving deltas as a table + the EXCLUDED list with a reason each. STOP.
5. Only after confirmation: design delivery (see below), then implement and verify.

## Classification traps

- **Version drift is not a customization.** `~/.config/btop/btop.conf` differed only
  because a newer btop rewrote its own config (header version bump + new upstream keys
  with upstream defaults). Read the diff and drop pure upstream churn.
- **Theme-generated files live inside `$HOME/.config` and look like user files.**
  `foot/dank-colors.ini`, `alacritty/dank-theme.toml`, `btop/themes/current.theme` are
  written by `omarchy-theme-set`; `readlink -f` shows they resolve into
  `~/.local/state/omarchy/current/theme/`. Check `readlink -f` and mtime before calling
  anything a user setting.
- **"Absent from `/etc/skel`" does NOT mean "not a setting".** `~/.config/omarchy/shell.toml`
  is an OVERRIDE file omarchy expects the user to create — the full file is generated at
  `~/.local/state/omarchy/current/theme/shell.toml`. Compare the live override against the
  generated file to size the change (there: `[font] base-size = 18` / `[bar]
  size-horizontal = 30` vs generated `12` / `26`). A diff-vs-skel run reports it as merely
  "added", which understates it.
- **Runtime state, credentials and backups are not config**: `~/.config/cliamp/`
  (socket/pid/log/history), `gh/hosts.yml` (tokens), `*.pre-omedora-*` / `*.bak.*`,
  `monitors.xml`, `user-dirs.*`, `mimeapps.list`, and the app-state dirs (`systemd/`,
  `pulse/`, browsers, `dconf`, `gtk-3.0`/`gtk-4.0`, `qt6ct`, `ibus`, `fcitx5`, `niri/`
  when the box runs Hyprland, `nvim/` which is omarchy's own payload).
- **A config that references a plugin is incomplete without it.** The live
  `omarchy/shell.json` names the `thord.workspaces` bar widget instead of the stock
  `omarchy.workspaces`; ship the plugin payload too (upstream
  `McNutty/omarchy-workspaces`, `manifest.json` + `*.qml`, minus `.git`), or the captured
  `shell.json` loads a widget that does not exist. **But prefer the built-in widget
  whenever upstream now ships it, and drop the clone.** A vendored clone is a copy of
  one base version's internals, so it keeps deriving its behaviour from something the
  base has since replaced — the workspace clone worked out each bar's list from
  `hypr.workspace_rule` pins, which 4.5 replaced with per-monitor blocks — and the
  payload then reproduces that mismatch on every fresh install. Vendor a plugin only
  for behaviour the base genuinely lacks (here, the battery-less power-profile picker).
- **Wallpaper sets count.** The live theme background dir held 21 images where the image
  ships 1, and the active background is a symlink:
  `~/.local/state/omarchy/current/background -> ~/.config/omarchy/backgrounds/<theme>/<img>`.

## What "look and feel / shell settings" resolves to here

- `~/.config/omarchy/shell.json` — bar position (top/bottom), `transparent`, per-section
  widget layout, idle `screensaver`/`lock` timers
- `~/.config/omarchy/shell.toml` — `[font] base-size`, `[bar] size-horizontal` overrides
- `~/.config/hypr/{monitors,input,bindings,looknfeel,autostart}.lua`, `hyprsunset.conf`, `xdph.conf`
- terminals: `foot/foot.ini`, `kitty/kitty.conf`, `alacritty/alacritty.toml`,
  `ghostty/config`, `wezterm/`
- `starship.toml`, `btop/btop.conf`, `cava/config`, `~/.bashrc`, `~/.bash_profile`
- `~/.config/omarchy/{backgrounds,themes,branding,plugins}/`, `~/.local/state/omarchy/current/{theme.name,background}`

`~/.config/omarchy/shell.json` edits land as a re-serialized key order, so its diff
looks larger than the change; read it semantically (which keys changed) before quoting
line counts at the user.

## Delivery design (agreed shape — confirm before implementing)

- Payload in the repo: `system_files/usr/share/hurunagus/config/` mirroring `$HOME` paths
  (`config/.config/omarchy/shell.json`, `config/.config/hypr/monitors.lua`, ...).
- Name the command `omarchy-<x>` and install it to `/usr/bin`: `/usr/bin/omarchy` scans
  `$OMARCHY_BIN_DIR/omarchy-*` and registers each command from its `# omarchy:summary=`
  metadata header, so the prefix IS the menu registration. Read the top of
  `/usr/bin/omarchy` before inventing a registration mechanism.
- Reuse the existing engine for PLAIN-FILE payloads: `omedora-seed-config --source <dir>
  --dest "$HOME" [--plan]` implements the whole policy (missing→write,
  byte-identical→skip, differing→backup `<path>.pre-omedora-<ts>` then write, skip-list
  via `OMEDORA_SEED_SKIP`). It is what `omedora-adopt-user --reset` wraps, i.e. exactly
  `omarchy-reinstall-configs` on `fedora-ostree`. Two limits mean you own the pass
  yourself whenever the payload carries a symlink (wallpaper sets do, e.g.
  `backgrounds/<theme>/0-hurunagus.png -> /usr/share/backgrounds/hurunagus/*.png`):
  it enumerates with `find "$source_dir" -type f`, so PAYLOAD SYMLINKS ARE SILENTLY
  SKIPPED; and it writes with `cp -f`, which on a destination that is itself a symlink
  follows it and clobbers the target (read-only under `/usr/share` → failure), where
  `rm -f "$dst"` then `cp -a` reproduces the link and rewrites the entry instead. Copy
  its classification verbatim, but use the suffix `<path>.pre-hurunagus-<ts>` so the
  provenance is obvious in `$HOME`.
- Keep the theme/wallpaper pointers OUTSIDE the payload tree (e.g.
  `/usr/share/hurunagus/theme.conf`), because everything under the payload dir is
  `$HOME`-relative and the seeder copies it into `$HOME`.
- Refuse root, user-invoked only (no unit/timer/autostart), support `--plan`.
- ONE source of truth: have `build.sh` seed `/etc/skel` from the same payload dir, so
  `useradd -m` and a re-run of the command can never diverge. See SKILL.md gotcha 11 for
  why an existing `$HOME` needs the command at all.
- Machine-specific values (pinning `hypr/monitors.lua` to named outputs with per-monitor
  workspace ranges) are the user's call, not a default to sneak in.
- Placement under bootc: these are USER files, so they only ever reach a `$HOME` via
  `/etc/skel` (new users) or the reapply command (existing users) — never by dropping
  them elsewhere in `system_files/usr/`.
- Consolidating skel into the payload means DELETING the skel originals that are now
  byte-identical copies of payload entries (`etc/skel/.config/hypr/*.lua`,
  `omarchy/branding/screensaver.txt`, `omarchy/backgrounds/<theme>/0-hurunagus.png`).
  Propose the deletion and ASK — this user's standing rule is that nothing is removed
  without explicit permission. Leaving both copies in place is harmless (build.sh
  reseeds them identically), so the ask never blocks the work.
- Before adding an image/wallpaper payload, check for byte-identical blobs already in
  the repo (`cmp -s` each payload file against `system_files/usr/share/backgrounds/<brand>/`)
  and report the overlap with sizes. Wallpaper sets routinely overlap the shipped
  background dir (15 of 21 identical ≈ 31 MB), so the honest options are
  duplication-in-git for a self-contained payload, or symlinks back into
  `/usr/share/backgrounds/...` (the inline pass reproduces symlinks).

## Implementing the reapply command

Working reference implementation already in the repo — read it before writing a new
one, its classification pass already handles missing/identical/differing/symlink/`--plan`:
`system_files/usr/bin/omarchy-hurunagus-configs`,
`system_files/usr/share/hurunagus/theme.conf`, and the skel seeding block in
`build_files/build.sh`.

- Payload path and name: `/usr/share/hurunagus/config/` + `/usr/bin/omarchy-hurunagus-configs`
  (route `omarchy hurunagus configs`). Confirm the route cannot collide first:
  `ls /usr/bin/omarchy-<group>*`.
- Metadata validation WITHOUT installing: the dispatcher only scans the installed
  `/usr/bin`, so re-run its own regex over your header lines instead —
  `[[ $line =~ ^[[:space:]]*#[[:space:]]*omarchy:([[:alnum:]_-]+)=(.*)$ ]]` — and check
  `summary` is present (its absence fails `omarchy commands --check`) and that
  `requires-sudo`/`hidden` are omitted or literally `true`. Recognised keys: `group`,
  `name`, `summary`, `args`, `examples`, `alias`/`aliases`, `requires-sudo`, `hidden`.
  The route derives from the filename stem: `omarchy-<group>-<name>` → `omarchy <group> <name>`.
- Refuse root (`EUID == 0`), support `--plan` / `--no-theme` / `--no-reload`, and never
  install a unit/timer/autostart — this command is user-invoked only.
- Re-apply the theme DETERMINISTICALLY: `omarchy-theme-set <theme>` and then
  `omarchy-theme-bg-set <abs-path>`. `omarchy-theme-set` lowercases/dash-izes the name
  ("Tokyo Night" → `tokyo-night`) and its `choose_theme_background` picks the NEXT image
  in the theme dir (index+1 of the current link), so theme-set alone makes a re-run
  rotate the wallpaper instead of restoring it.
- Pick the new settings up WITHOUT resetting them: `omarchy-shell shell reloadConfig`
  (fall back to `omarchy-shell -q shell rescanPlugins`) — the idiom the sourced helper
  `omarchy-shell-config` uses. NEVER call `omarchy-refresh-shell` for this: it is
  `omarchy-refresh-config omarchy/shell.json` + `omarchy-bar defaults`, i.e. it RESETS
  `shell.json` to Omarchy's defaults. For `hypr/*.lua`: `omarchy-restart-hyprctl`
  (a plain `hyprctl reload`). A terminal alpha change needs no restart — say so rather
  than restarting terminals under the user.
- `build.sh` seeds skel from the payload with the same enumeration
  (`find … \( -type f -o -type l \) -print0`, `mkdir -p "/etc/skel/${rel%/*}"`,
  `rm -f` then `cp -a`, `chown -R root:root /etc/skel`) plus `chmod 0755` on the helper,
  and should warn rather than fail when the payload dir is absent.

## Verifying without touching the live session

`omarchy-theme-set` runs its post-theme commands in PARALLEL and they reach the live
session — `omarchy-restart-terminal` (killall SIGUSR1 kitty, SIGUSR2 ghostty),
`omarchy-restart-btop`, the editor re-tints, and `omarchy-hook theme-set`. So never
exercise the theme path while testing:

1. `--plan` against the real `$HOME`: read-only, and it is also the deliverable for the
   user (it shows exactly which of their files would be backed up).
2. Apply into a scratch tree with the session-touching steps off:
   `HOME=/tmp/fakehome HURUNAGUS_CONFIGS_DIR=<repo payload> <cmd> --no-theme --no-reload`.
3. Re-run it: the second pass must report every file `unchanged` — that is the
   idempotency proof.
4. Pre-seed the scratch `$HOME` to exercise the branches: a differing file (expect a
   `.pre-hurunagus-<ts>` backup), a symlink where a payload file goes, and a copy of a
   payload file (expect `unchanged`). Then `readlink` the symlink entries in the result
   to confirm they came out as symlinks.
5. `bash -n` the helper and `build.sh`.

## Keeping the payload current with upstream (major bumps)

- **Omarchy's migrations rewrite the `$HOME` copy, never the payload.** They edit
  `~/.config/omarchy/shell.json` in place — the bar's one flat `center` list plus
  `centerAnchor` became `centerBegin`/`center`/`centerEnd` plus `tray`, widget ids got
  renamed, legacy keys like `"transparent": true` became `"background": "none"` — so an
  upgraded machine keeps working while the payload silently falls behind, and the next
  replay writes the OLD shape back over a working file (after backing it up). Staleness
  is invisible from the running box: only a fresh install or a replay exposes it.
- Therefore, on every upstream MAJOR bump: rebuild the payload's `shell.json` from the
  new `$OMARCHY_PATH/config/omarchy/shell.json` with the deltas re-applied (keep the
  live key order so the diff stays readable), and re-check every other payload file
  against its new upstream default. Do not assume a payload that still applies is still
  correct.
- **Replay only ever WRITES; it never deletes.** Dropping a file or a plugin from the
  payload stops it reaching new users and does nothing to machines that already have it
  (a `looknfeel.lua` override, a vendored plugin). Say that when dropping one, back it up
  on each live box, and change those boxes deliberately — by hand or with a migration.
  This is the mirror of gotcha 11: `/etc/skel` reaches new `$HOME`s only, the payload
  reaches existing ones only, and neither removes anything.
- Keep the helper's `#` inventory comment — the block naming each payload entry and what
  it changes — in step with the payload in the same commit. It is the only statement of
  what the deltas ARE; a stale line reads as intentional.
- Prefer the base's own mechanism over a config override, both in the payload and on a
  live box: per-workspace layout via `omarchy hyprland workspace layout default`, not
  `general.layout` in `looknfeel.lua`; the stock workspace widget once the base ships
  per-monitor blocks, not a clone.
- After any payload change, re-run the dry run against a machine that already has the
  config and aim for `back up 0`: a `backup` line is the payload disagreeing with the
  live arrangement, usually widget order or a frozen stock file that has since drifted.


<!-- absorbed from SKILL.md 2026-11-12 -->

## Harvesting the user's own config onto the image

**Rule: the user names the payload set — inventory and PRESENT, then STOP.** A request
like "make a script that loads my custom settings" is answered with a table of concrete
deltas (path + what actually differs) plus an explicit EXCLUDED list with a reason per
item. Do NOT proceed to a payload path, script name, or install layout before they have
picked the set; designing the mechanism unasked gets corrected. Procedure, baselines,
classification traps and the delivery shape live in
`references/user-config-delta-capture.md`; run `scripts/config-delta.py` (read-only) to
produce the delta table.

Mechanics that make the delivery cheap, so don't invent alternatives:

- `/usr/bin/omarchy` scans `$OMARCHY_BIN_DIR/omarchy-*` and registers each command from
  its `# omarchy:summary=` metadata header — naming a script `omarchy-<group>-<name>` and
  shipping it to `/usr/bin` IS the menu registration (route: `omarchy <group> <name>`).
  Validate the header by re-running that regex yourself; the dispatcher only scans the
  installed tree, so `omarchy commands --check` cannot see an uninstalled script.
- `omedora-seed-config --source <dir> --dest "$HOME" [--plan]` implements the
  backup-then-write policy that `omedora-adopt-user --reset`, i.e.
  `omarchy-reinstall-configs` on `fedora-ostree`, wraps — but it ENUMERATES WITH
  `find -type f`, so payload symlinks are silently skipped, and it writes with `cp -f`,
  which writes THROUGH a destination symlink. Own the pass (`rm -f "$dst"` then `cp -a`)
  when the payload has symlinks; keep its classification and use a
  `.pre-hurunagus-<ts>` backup suffix.
- Re-applying the theme is TWO calls: `omarchy-theme-set <theme>` then
  `omarchy-theme-bg-set <abs-path>` — theme-set's `choose_theme_background` picks the
  NEXT wallpaper in the theme dir, so theme-set alone ROTATES the background each run.
- To make the running shell read `shell.json`/`shell.toml`, use
  `omarchy-shell shell reloadConfig` — NEVER `omarchy-refresh-shell`, which RESETS
  `shell.json` to Omarchy's defaults.
- `omarchy-theme-set` fires its post-theme commands in PARALLEL and they reach the live
  session (`omarchy-restart-terminal` → SIGUSR1 kitty / SIGUSR2 ghostty, btop, editor
  re-tints, `omarchy-hook theme-set`). So verify the SEEDING path only: `--no-theme
  --no-reload` against a scratch `HOME`, twice (the second run must report everything
  `unchanged`). Full detail: `references/user-config-delta-capture.md`.


<!-- absorbed from SKILL.md 2026-11-12 -->

## Hurunagus look-and-feel payload + `omarchy-hurunagus-configs` (2026-11)

Sibling of `omarchy-reinstall-configs`, but it replays ONLY the Hurunagus deltas (the omarchy-defaults reset clobbers settings the user tuned themselves):

- Payload in the image repo: `system_files/usr/share/hurunagus/config/` = a `$HOME`-relative tree of the deltas (shell.json bottom and clear bar naming the stock
`omarchy.workspaces`, shell.toml base-size 18/bar 30, vendored
`plugins/thord.powerprofile`, `backgrounds/tokyo-night` set, `branding/screensaver.txt`,
`foot/foot.ini` alpha — and no `hypr/looknfeel.lua`, because the layout belongs to
the workspace, not the payload) + `system_files/usr/share/hurunagus/theme.conf` (`THEME=`/`BACKGROUND=`). Helper: `system_files/usr/bin/omarchy-hurunagus-configs` (chmod +x, user-run, never autorun). `build.sh` seeds `/etc/skel` from that same payload — one source of truth, so never keep a second copy under `system_files/etc/skel/`.
- Discovered by the dispatcher with no registration step: `/usr/bin/omarchy` scans `$OMARCHY_BIN_DIR/omarchy-*` (= `/usr/bin`), and the filename stem after `omarchy-` splits into route group + name. So `omarchy-hurunagus-configs` auto-registers as `omarchy hurunagus configs`; it only needs a `# omarchy:summary=` header (`args`/`examples` optional). **Pitfall: the route must be typed in full** — the dispatcher registers only `omarchy hurunagus configs`, and there is no `omarchy-hurunagus` group binary, so `omarchy hurunagus`, `omarchy hurunagus config` (singular) or `omarchy hurunagus-configs` all print `Unknown Omarchy command: omarchy ...` even on a correctly updated box. The bare binary name is the reliable invocation; add a `group=`/`name=` header only if you want a different route. Verify metadata with the same regex the dispatcher uses: `^[[:space:]]*#[[:space:]]*omarchy:([[:alnum:]_-]+)=(.*)$`.
- Per-file policy to copy from `omedora-seed-config`: missing→write, byte-identical→no-op, differs→back up `<path>.pre-hurunagus-<ts>` then write, `..` paths refused, never write outside `$HOME`.
- **A user plugin and a menu-extension file are legitimate payload deltas.**
  `plugins/<id>/{manifest.json,<Entry>.qml,README.md}` lands under
  `~/.config/omarchy/plugins/` where the shell already scans, so no enable step
  is needed after a replay; `extensions/omarchy-menu.jsonc` is a user-extension
  file the shell merges over the stock menu. Ship the stock template WITH the
  added row rather than a one-row stub, so a machine already holding the
  template stays byte-identical.
- **Widget ORDER must match what `omarchy plugin enable` produced on a live
  host**, or every replay rewrites `shell.json` and prints a `backup` line for a
  purely cosmetic reshuffle. Diff the payload's copy against the live file and
  align positions before shipping.
- **Accept a payload change only when the dry run reports `create N, back up 0`**
  on the machine that already has the config:
  `HURUNAGUS_CONFIGS_DIR=<checkout>/system_files/usr/share/hurunagus/config omarchy-hurunagus-configs --plan --no-theme`.
  Any `backup` line means the payload disagrees with the live arrangement —
  usually widget order, or a frozen stock file that has since drifted.
- **Shipping a whole stock file freezes it**: the payload copy wins over later
  package/upstream edits on every replay (after a backup). Fine for `shell.json`
  and the menu-extension template, but say it out loud when adding a new one, and
  prefer a delta file when the upstream file churns.
- **Do NOT delegate the seeding to `omedora-seed-config` if the payload may contain symlinks**: it builds its list with `find -type f` (symlinks silently skipped) and writes with `cp -f`, which writes THROUGH a destination symlink (would clobber the link target, e.g. the read-only `/usr/share/backgrounds/...`). Classify symlinks explicitly: payload symlink → reproduce as a symlink; a plain destination file holding the target's exact bytes counts as unchanged.
- Wallpapers already shipped in `/usr/share/backgrounds/hurunagus/` should be SYMLINKS in the payload (saves tens of MB of git duplication); omarchy enumerates theme backgrounds with `find -L`, so symlinked wallpapers are valid choices. `0-hurunagus.png` follows this pattern already.
- Reload traps: `omarchy-refresh-shell` RESETS shell.json to omarchy defaults — never use it to reload; use `omarchy-shell shell reloadConfig` (fallback `omarchy-shell -q shell rescanPlugins`). `omarchy-theme-set <name>` picks the NEXT wallpaper while cycling, so re-pin the intended one with `omarchy-theme-bg-set <abs-path>` after; the theme name must exist in `$OMARCHY_PATH/themes/<name>` (lowercased, spaces→dashes). `hyprctl reload` (or `omarchy-restart-hyprctl`) for `hypr/*.lua`.
- Harvest the deltas by diffing live `~/.config` against `/etc/skel/.config` (the image's shipped merged defaults), NOT against `/usr/share/omarchy/config` alone; treat upstream version drift (e.g. btop.conf rewritten for a newer btop) and theme-generated files (`alacritty/dank-theme.toml`, `foot/dank-colors.ini`, `btop/themes/current.theme` → symlinks into `~/.local/state/omarchy/current/theme/`) as noise, not user settings. Monitor layout is per-machine: keep it OUT of the payload.
- Test the helper with `HOME=<scratch dir> --no-theme --no-reload` (never `--theme` in a test: `omarchy-theme-set` runs `omarchy-restart-terminal` and other hooks against the LIVE session), and `--plan` for a read-only classification against the real `$HOME`.
- PROVE a pushed change without rebasing anyone's box: `gh run list` for the run, then `skopeo inspect --no-tags docker://ghcr.io/wegweg7979/hurunagus-hyprland:latest` for the new digest + `latest.<date>-<sha>` label, `podman pull` THAT digest, and run a bind-mounted read-only check script inside it: `podman run --rm -v check.sh:/check.sh:ro,z <digest> bash /check.sh`. Assert, in the image: the helper exists and is 0755; `/usr/share/hurunagus/config` has zero `find -xtype l` dangling symlinks; `/etc/skel` really was seeded (incl. symlinked wallpapers resolving to `/usr/share/backgrounds/...`, and `monitors.lua` still the generic skel default); and `omarchy commands --check` reports exactly ONE more command than the pre-change count (361 -> 362) with the new route in `omarchy commands` output. That last pair is the only proof the registration worked, since `--check` against the dev checkout cannot see an uninstalled script.
