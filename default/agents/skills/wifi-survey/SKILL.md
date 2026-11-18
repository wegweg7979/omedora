---
name: wifi-survey
description: Use when scanning or analysing Wi-Fi air via NetworkManager.
---

# Surveying the Wi-Fi air on Linux

How to read what is actually on the air: which access points exist, on which
channels, how strong — and how to build a tool that does it. The D-Bus and
shell recipes are in `references/nm-dbus-recipes.md`; a working implementation
is the airgraph project at `~/Work/airgraph` (`src/nmwifisource.*`,
`src/scanbackend.*`).

## The two rules that shape everything

- **NetworkManager is the only unprivileged door.** `iw dev <iface> scan` and
  `iw dev <iface> survey dump` need `CAP_NET_ADMIN`; on a normal account they
  fail with *Operation not permitted*, and these hosts have no passwordless
  sudo. Get scan data over the system bus from `org.freedesktop.NetworkManager`.
  Use `iw` only for queries that need no privilege: `iw dev`, `iw phy <phy>
  info`, `iw reg get`.
- **Read-only, always.** Never call `ActivateConnection`/`Disconnect`, never
  `iw set`, never touch regulatory state. A survey tool reports the air; it does
  not join it. Say so in the README when the tool is for the user's own machine.

## Procedure

1. **Find the device.** `NetworkManager.GetDevices` → the one whose `DeviceType`
   is `2` (wifi); the interface name is the Device's `Interface` property.
2. **Ask for a scan.** `Device.Wireless.RequestScan({})` — returns in a couple
   of milliseconds and is *always* accepted (see coalescing below).
3. **Read the access points.** `GetAccessPoints()` → `ao`, falling back to the
   `AccessPoints` property; then `Properties.GetAll` per AP for `Ssid` (`ay`),
   `HwAddress`, `Frequency` (MHz), `MaxBitrate` (kbit/s), `Strength` (0–100),
   `Flags`/`WpaFlags`/`RsnFlags`, `LastSeen`.
4. **Render on signals, not on the return value.** Subscribe to
   `AccessPointAdded`/`AccessPointRemoved` on the device and `PropertiesChanged`
   on each AP path. A scan's results arrive 4.5–12 s after the request as a
   burst of property changes; nothing useful comes back synchronously, so a
   sleep-then-read design is both slow and wrong.
5. **Pace the scans yourself** — one `RequestScan` every ~10 s, plus a manual
   rescan. Nothing polices the rate for you.
6. **Read the band plan from the phy**, not from a hardcoded table:
   `iw phy <phy> info` reports Band 1 / 2 / 4 (2.4 / 5 / 6 GHz) with the
   frequency span this radio actually supports.

## Coalescing: acceptance is not a scan

NetworkManager accepts *every* `RequestScan` at any interval and silently drops
the ones it will not run — six requests 2 s apart were all accepted and only two
actually scanned. So "the call succeeded" means nothing about freshness.

The device's `LastScan` property is the only proof: read it before and after.
Its unit is undocumented and does not match the machine's uptime (observed
deltas of ~7 500–11 700 for events seconds apart), so treat the *delta* as the
signal and the value as opaque. Report data age from that delta; a tool that
claims fresh data on request success is lying.

## What the data does and does not contain

- `Strength` is 0–100, derived from dBm as `2 * (dBm + 100)`. Invert it for
  display and label it derived — it is quantised to 0.5 dB, fine for an axis,
odious as a measurement.
- **No channel width in scan data, ever.** Assume 20 MHz and say it is assumed — but that assumption is *only* needed for other APs: `iw dev <iface> info` (also unprivileged) reports the width and centre frequency of the link the machine is on right now (`channel 100 (5500 MHz), width: 40 MHz, center1: 5510 MHz`). Use it for the associated AP and mark the rest as assumed; a graph that draws your own 40 MHz link as 20 MHz is wrong about the one AP you can actually measure. Other APs' widths need `iw scan`, i.e. root.
- **No noise floor and no channel utilisation.** Both need `iw survey dump`,
  i.e. root (a `pkexec` helper is the way if it is ever needed).
- `LastSeen` is a boot-time millisecond stamp, not an age.
- An AP in the list is one NetworkManager heard recently, not necessarily in the
  latest scan, and the set changes between runs (5–10 APs across consecutive
  scans on the same desk).
- The same SSID on several bands is normal: key everything by **BSSID**.
- Signal swings several dB while the machine sits still (−65.5 → −55.0 dBm
  inside 20 s), so any "over time" view needs a rolling window or smoothing.

## Band and channel math — and test it

- band: `f >= 5925` → 6, `f >= 5150` → 5, else 2.
- channel: 6 GHz `(f - 5950) / 5`; 5 GHz `(f - 5000) / 5`; 2.4 GHz
  `(f - 2407) / 5` — **except 2484 MHz, which is channel 14** (the formula
  yields 15). Pin these in unit tests; the channel-14 case is the one that
  silently passes review.
- `iwlist` and `iwconfig` are not installed on Fedora: `nmcli`, `iw` and
  `rfkill` are.

## Graphing it: test the axis maths

Put the axis mapping, the bell, the congestion score and the channel choice in
pure functions and pin them in tests — and when a change is asked for as a
quality (*brighter*, *calmer*), pin the quality as well as the literal values
(brightness, hue sector), or a palette that keeps the numbers and loses the
quality still passes. Traps, all of which have bitten:

- **The dBm axis sign.** dBm grows upward, the plot's y grows downward, so
  `fraction = (dbm - floor) / (top - floor)` and `y = bottom - fraction * height`.
  Inverting that denominator draws the entire graph upside down, and it still
  *looks* like a plausible graph — the test is what catches it.
- **Channel 14.** See above; `(f - 2407) / 5` gives 15 for 2484 MHz.
- **Colour is composited, not chosen.** A vivid fill drawn translucent over a
  near-black plot does not arrive as the colour that was picked: `#ff9e2c` at
  ~30 % alpha over `#121216` reaches the screen as `#7d5120`, a brown — measured
  off the rendered PNG, not guessed — and four bells stacked on one 2.4 GHz
  channel muddle each other further. Keep solid data shapes near-opaque
  (≈0.75–0.85 alpha) so what is on the screen is the colour, and paint every
  outline after every fill so overlapping shapes still read as overlapping.
  Verify by counting the rendered pixels by hue bucket, never by eye and never
  by a vision model's colour naming — a muddy brown gets called orange.
- **Paint order decides what survives, once the fills are opaque.** Two APs on
  one channel share a footprint, so the shape painted last is the only one on
  the screen: paint the **tallest first** and let every shorter neighbour land
  on top of it. Tallest last buries each weaker AP on a crowded channel while
  the table still lists it, and nothing in the data looks wrong. Two APs in the
  *same* strength tier are pixel-identical under either order, so prove the
  order on a pair that spans two tiers.
- **Prove a render change against frozen data, not the live air.** Signal drifts
  several dB between two grabs, so a shot taken before a change cannot be
  compared with one taken after it. Flip the code back, rebuild, and take both
  shots from the same fabricated fixture, then count pixels per hue bucket
  inside one channel's column: the mix should track the dB spans either side of
  each AP's peak there, and a column that is all one colour means everything
  else in it is being painted over. Read the produced image's own tabs and
  summary line as well — a view that follows the associated network can render a
  band other than the one the command line asked for.

A linear frequency axis (MHz, not channel number) is the honest one: it makes
2.4 GHz's overlapping channels overlap and 5 GHz's gaps visible. Take the band's
channel list from `iw phy` so the axis matches the radio, and draw the assumed
width as a stated assumption, not as a measurement.

Render it offscreen with no display (`QT_QPA_PLATFORM=offscreen
./build/airgraph --band 2 --settle 8 --grab out.png`, which waits for a real scan)
and histogram the graph area's saturated pixels by hue bucket.

## 6 GHz

Capability and observation are two different facts, and both need reporting.
An Intel AX210 advertises Band 4 fully (59 channels, 5955–7115 MHz) and the
regulatory domain can allow 5925–6425, yet five scans in a domestic setting
found zero 6 GHz APs. Nothing distinguishes "no 6E router nearby" from "the scan
skipped the band", so make the 6 GHz view one that is *allowed to be empty* —
"no 6 GHz APs heard" next to the phy's capability, never an error. Many Band 4
channels are flagged `(no IR)`: passive-scan only, so they answer only if an AP
is there. The phy is often `self-managed` (`country DE` under a `GB` global),
meaning wpa_supplicant owns the regulatory state — never suggest `iw reg set`.
