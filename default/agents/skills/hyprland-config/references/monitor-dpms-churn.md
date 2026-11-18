# Monitor power / DPMS churn triage

Use when displays blink, drop signal, show "no signal", or appear to power-cycle - especially
while the session is locked or idle - and the layer that is cycling them must be identified.

## Ground rules

- Hermes runs inside the user's live desktop. Anything that blanks or interrupts it
  (`hyprctl dispatch dpms disable`, `hyprctl reload` on a live session, `omarchy system lock`)
  needs the user's go-ahead first. Probe read-only before that.
- Separate proven from inferred in the answer: counters prove churn happened, they rarely prove
  who started it. State which is which.
- Omarchy 4.x locks the session with a Quickshell ext-session-lock plugin, not hyprlock/swaylock.
  Do not go looking for a hyprlock config on these systems.
- Check `omarchy-shell idle status` before any measurement. `enabled:false` / `stayAwake:true` means
  no shell timer blanks a display, so the lock/idle blank-wake loop below is ruled out in one
  read-only command and a sleeping screen must have been switched off by an action the user took.
  Ask what that action is; do not assume a timer.

## 1. Make hyprctl usable from the agent shell

`HYPRLAND_INSTANCE_SIGNATURE` is normally unset for the agent's shell even while a session runs:

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$UID/hypr | head -1)
hyprctl version && hyprctl monitors all
```

Newest signature directory wins. Confirm the compositor answers before trusting anything else.

## 2. Is it flapping right now? (non-disruptive)

```bash
for i in $(seq 1 45); do cat /sys/class/drm/card*-HDMI-A-*/status; sleep 1; done | uniq -c
timeout 30 udevadm monitor --subsystem-match=drm
```

Stable connector status and zero DRM events mean the churn is dormant. Report that instead of
asserting the storm is ongoing.

Per-connector sysfs gives more than `status`, unprivileged and per output:

```bash
for c in /sys/class/drm/card*-[A-Z]*; do
  n=$(basename "$c"); echo "$n id=$(cat $c/connector_id) status=$(cat $c/status) \
    dpms=$(cat $c/dpms) enabled=$(cat $c/enabled)"
done
```

- `connector_id` is the map between a sysfs connector and the `Connector NNNN` lines in
  hyprland.log - read it instead of guessing which id belongs to which output.
- `dpms` (`On`/`Off`) and `enabled` change per output, so a 1 s poll of these three files is the
  cheapest way to catch *per-monitor* transitions; `hyprctl -j monitors` costs a compositor
  round-trip per sample and only reports Hyprland's view.
- Long windows, done for you: [`scripts/monitor-churn-capture.py`](../scripts/monitor-churn-capture.py).

## 3. Count the churn in Hyprland's own log

Aquamarine/DRM debug output lives at `/run/user/$UID/hypr/<sig>/hyprland.log`:

```bash
L=$(echo /run/user/$UID/hypr/*/hyprland.log)
grep -c 'Got a hotplug event' "$L"                            # link drop/re-assert incidents
grep -c 'Modesetting HDMI' "$L"                               # real re-modesets
grep -oE 'Connector [0-9]+ connection state: [0-9]+' "$L" | sort | uniq -c   # 1=connected 2=disconnected
grep -c 'Cannot commit when a page-flip is awaiting' "$L"      # ERR: compositor fighting the churn
# map connector ids to names:
grep -E 'Connector id [0-9]+ already initialized|connector (HDMI-A|DP)-[0-9]' "$L" | head -30
```

Thousands of `connection state: 2` for a connector that is physically plugged in means the panel
really is dropping its link - not a rendering artifact, and not something the shell caused.

Pitfalls:
- hyprland.log carries **no timestamps** and is written through a fully-buffered 8 KB pipe, so a
  60 s window with zero growth means the buffer has not flushed, not that nothing happened. Never
  derive a wall-clock time from byte offsets; get timing from the journal (step 4).
- `Disabling output` / `released crtc` lines are produced by both the DPMS-off path and the
  monitor-disconnect path; on their own they do not prove DPMS is involved.

## 4. Get timing from the journal

Journal-side proxies are timestamped where hyprland.log is not:

```bash
journalctl --user -t omarchy-shell --since '-3 hours' | grep 'Handler was registered'
journalctl --user --since '-3 hours' | grep -iE 'omarchy (lock|idle)|lock-requested|idle-cycle'
omarchy-shell idle status; omarchy-shell lock status      # last event + timestamps
```

Each Quickshell scene rebuild logs ~10 duplicate-`IpcHandler` warnings (one per plugin target
already registered), so a burst of them is one rebuild of the whole shell scene, i.e. one
screen-set/monitor change. Burst cadence dates the churn period; correlate it with lock and unlock
timestamps to see whether the session was locked through it.

Caveat: the same shell also hot-reloads the whole scene when a file it watches changes, so a burst
can come from a rewritten config/state file rather than from monitors. Check mtimes under
`~/.config/hypr` and `~/.config/omarchy` (and the state file a FileView watches) before blaming the
displays.

Discriminator for "is this burst monitors or an actor?": burst cadence is regular (a fixed interval)
and the journal shows a matching repeating non-DRM actor in the same window - e.g. a `sudo` PAM
accounting line plus `rpm-ostree ... Allowing active client` every cycle from a script - then the
bursts are that actor rewriting a watched file, not a screen-set change. Confirm with the hotplug
counter over the same window: zero hotplugs plus a burst storm means nothing was hotplugged. A
history check is also worth ten seconds: `journalctl --user -t omarchy-shell | grep 'Handler was
registered' | awk '{print $1,$2,$3}' | uniq -c` prints bursts per second and dates every churn
period in the retained journal.

## 5. Omarchy's blank/wake loop (the usual "cycles while locked")

Safe to read, never edit: `/usr/share/omarchy/shell/plugins/lock/Service.qml` and
`/usr/share/omarchy/shell/plugins/services/idle/Service.qml`, plus
`/usr/share/omarchy/default/hypr/input.lua`.

- `idle.screensaver` / `idle.lock` seconds in `~/.config/omarchy/shell.json` drive the idle service;
  `omarchy debug idle` dumps the whole diagnostic picture.
- **Read `idle status` before reading the plugin code.** `enabled:false` with `stayAwake:true` means
  the idle service is inert and none of the blank/wake machinery below can be the cause; the
  stay-awake flag is persisted in `~/.local/state/omarchy/indicators/stay-awake`.
- **Two different "off"s, only one persisted:** `omarchy-brightness-display off` calls
  `hl.dsp.dpms({ action = "disable" })` and hits *every* output (the `--monitor` argument only
  routes brightness/DDC, not the blank). Turning off *one* display while it stays plugged in is
  `hyprctl eval 'hl.monitor({ output = "HDMI-A-2", disabled = true })'`, which is exactly what the
  bar's monitor panel does (`/usr/share/omarchy/shell/plugins/panels/monitor/Panel.qml`). Because
  `hyprctl eval` edits the live config only, the next `hyprctl reload` re-reads `monitors.lua`, finds
  no `disabled` rule and brings that display back on - so a reload loop (see monitor-watch below)
  will re-light a screen the user deliberately switched off, over and over.
- On lock, `idleBlankTimer` (hard-coded `interval: 5000`, `repeat: false`) runs
  `omarchy-brightness-keyboard off; omarchy-brightness-display off` -> `hyprctl dispatch dpms disable`
  -> outputs disabled, CRTCs released.
- Any input wakes it: `runWake()` -> `omarchy-system-wake` -> `omarchy-brightness-display on` ->
  `hyprctl dispatch dpms enable` - and `runWake()` re-arms the same 5 s timer. Wake triggers include
  the lock view's full-screen `MouseArea` (`hoverEnabled: true`, `onPositionChanged`), any key press,
  and password submit.
- Omarchy's Hyprland defaults set `misc:mouse_move_enables_dpms = true` and
  `misc:key_press_enables_dpms = true`, so the compositor re-lights DPMS on any input by itself.
  Verify live with `hyprctl getoption misc:mouse_move_enables_dpms`.

Net effect: blanked 5 s after locking, re-lit by the slightest mouse jitter, blanked again 5 s later
- a power-cycle loop that sustains itself with no user effort. A wireless mouse with drift is enough.

### 5b. The arrival-is-a-wake loop (one display cycles, the other stays dark)

Symptom: on lock, one panel stays off and the other blanks/wakes forever with no input, until a real
unlock. The two halves are the lock plugin's wake rule and one marginal HDMI link:

- `~/.local/state/.../lock/Service.qml` (packaged, `/usr/share/omarchy/shell/plugins/lock/Service.qml`)
  re-arms the 5 s blank timer on **any display arriving** while locked:
  `Connections { target: Quickshell; function onScreensChanged() { if (screens > knownScreenCount) { …; if (lockRequested) armBlankTimer() } } }`.
  So a connector that drops and re-asserts its link counts as a wake.
- `idleBlankTimer.idleMs` is hard-coded 5000, `repeat: false`, and `runBlank()` runs
  `omarchy-brightness-keyboard off; omarchy-brightness-display off` -> a **global** `hl.dsp.dpms(disable)`.
  `runWake()` runs `omarchy-system-wake` -> `omarchy-brightness-display on` (which self-skips when every
  output is already lit).
- Loop: DPMS off -> the marginal panel drops link -> connector re-asserts -> screen count rises ->
  blank timer re-armed **and** the returning output is re-modeset (that re-modeset is the visible
  "wake") -> 5 s -> DPMS off -> repeat, ~10-20 s per cycle. The healthy panel never drops link, never
  produces an arrival, and so is never re-armed or re-lit - which is exactly the asymmetry the user sees.

Read it, do not guess it: the capture that proves it polls per-connector sysfs
`/sys/class/drm/card*-HDMI-A-N/{status,dpms,enabled}` once a second and logs deltas of the Hyprland-log
counters above. Expected trail: `HDMI-A-1 dpms On->Off` interleaved with `hotplug+2` and
`Connector 513 connection state: 2 +1`, with the other connector flat and staying `Off`.

A poller that shells out to `hyprctl` must set `HYPRLAND_INSTANCE_SIGNATURE` **inside** the script
(derive it from the newest `/run/user/$UID/hypr/*/hyprland.lock`): a background process started from
the agent shell does not inherit the compositor's env, and `hyprctl -j` then returns empty output,
which reads as "no monitors" rather than as an error.

This is a link-margin fault surfaced by a software rule - neither side is user misconfiguration, and
no Hyprland/Omarchy setting fixes it. Fix the link (cable, port, or the free DP connector); report it
upstream as "a display arriving counts as a wake". Do **not** pin the panel to a lower refresh as a
"fix" without saying it is a margin test, and never edit the packaged Service.qml.

Other omarchy actors to read before concluding:
- `omarchy-hyprland-monitor-watch` runs for the whole session, reacts to
  `monitoradded/removed/configreloaded`, and can loop `hyprctl reload` through `recover_modeless`
  while any enabled monitor sits at 0x0 (`omarchy-hyprland-monitor-modeless` exits 0 in that state).
  Each reload re-applies monitor rules -> re-modeset -> Quickshell rebuilds its per-screen UI.
- `omarchy-system-wake` also calls `omarchy-hyprland-monitor-clamshell`, which can rewrite
  `~/.config/hypr/monitors.lua` and so trigger a config auto-reload. Check that file's mtime to see
  whether this path is active.

## 6. Decisive test (ask first - it blanks the user's screens ~10 s)

```bash
a=$(grep -c 'Got a hotplug event' "$L")
hyprctl dispatch dpms disable; sleep 5; hyprctl dispatch dpms enable; sleep 5
b=$(grep -c 'Got a hotplug event' "$L"); echo "$a -> $b"
```

- +2-4 hotplugs per cycle: the panels drop their link on every DPMS blank, so any blank/wake loop is
  a monitor power-cycle generator. Say so plainly.
- ~0: DPMS is clean on this hardware; the flap has another driver - keep hunting with steps 2-4.

## Attribution: which layer owns the flap

Do this before changing any config. hyprland.log is per compositor run, so the counters do not carry
history - the panel/connector/cable mapping does. Record it in every report:

- Attribute to the **connector**, never to "the monitor". A flap that survives a panel replacement
  and stays on the same connector while the other connector's disconnect counter is flat excludes
  both the system layer (no DPMS transitions, see step 2) and the panel. What is left is that
  **cable** and that **port**.
- Swap test, cheapest decisive step: move the panel to the other HDMI port, or just swap the two
  cables. Whichever counter starts climbing owns the fault. Run it before touching config.
- Mind the pinned rate: the highest-refresh output sits at the highest pixel clock, and a marginal
  sits at the highest pixel clock, and a marginal cable fails there first. Dropping one step (e.g. `1920x1080@120.00` -> `60.00` in `monitors.lua` +
    `hyprctl reload`, with permission) is only a quick confirmation of a bandwidth theory - the panel was
    seen running its full rated 120Hz again after a cable swap, so a lower rate is not the fix and must
    not be left in place as one. DisplayPort is the durable answer.
- What a panel advertises is readable: `cat /sys/class/drm/card*-<CONN>/edid` (256 B, unprivileged)
  and the per-connector mode list in hyprland.log (`drm: Mode N: 1920x1080@120.00Hz (preferred)`).
  Do not hand-roll an EDID parser for the HDMI max-TMDS field to "prove" a bandwidth theory - CTA
  data-block lengths are easy to mis-read and a mis-aligned block looks like a plausible VSDB.
  Quote only what a real decoder returns.

## 7. Fix order

0. **Replace the cable.** Confirmed in the field: a box with the arrival-is-a-wake loop (§5b) was
   cured by swapping the HDMI cable alone - zero hotplugs and one modeset per live connector on the
   next boot. It is the cheapest step and it is a real fix, not a margin workaround, so do it before
   touching refresh rates, DPMS or input settings. Replacing an *existing* cable with a known-good one
   is the test; keep the old one only to re-run the swap if the churn returns.
1. Move the panel to DisplayPort where a DP port is free (`ls /sys/class/drm/` shows connectors and
   their status). DP handles DPMS far better than HDMI, which is where panels re-enumerate on blank.
2. In the monitor's own OSD, turn off input auto-detect / "auto source" / deep-sleep quick-start -
   panels that hunt inputs re-assert HPD whenever the signal drops.
3. Remove the phantom-wake driver in `~/.config/hypr/input.lua`, then apply and validate:

   ```lua
   hl.config({ misc = { mouse_move_enables_dpms = false } })
   ```

   Keep key-press wake (and the lock view's own wake path) working; tell the user that after this a
   mouse nudge alone will no longer relight a DPMS-off display.
4. The 5 s blank-on-lock has no user-facing toggle - it is hard-coded in the packaged plugin. If the
   cycle survives 1-3, it is an upstream Omarchy issue, not user misconfiguration; see the `omarchy`
   skill's contributing guide for filing it.
