# Hurunagus/Omedora project map — load this FIRST

Orientation for this user's Fedora-atomic work: what the names mean, where the
code lives, which boxes exist, and which of them a session may touch. This is
the material that used to sit in agent memory; it lives here now so it loads on
the tasks that need it instead of on every turn.

## Vocabulary

- **omedora** — a Fedora/ostree rebase of Omarchy: an RPM literally named
  `omedora` (`0.3.0-beta.x`, tracking the Omarchy 4.5 base) that installs
  `/usr/share/omarchy`. It is how Omarchy's Hyprland desktop reaches Fedora
  atomic hosts. Source checkout: `/var/home/user/omedora-inspect` (GitHub
  `wegweg7979/omedora`).
- **hurunagus** — the user's image-family name. `hurunagus-hyprland` is the
  FLAGSHIP, actively developed variant; the bare `hurunagus` repo is dead and
  archived on GitHub (its old local clones are deleted).
- **hurubase** — the safe rebase helper: `~/Documents/GitHub/hurunagus-rebase`,
  standalone and deliberately NOT inside omedora, because not every hurunagus
  variant ships omarchy/omedora, so nothing in it may call `omarchy-*`.

## Disk layout (which checkout is which)

| Path | What it is |
|------|------------|
| `/var/home/user/hurunagus-hyprland` | Working clone of the flagship image repo (`github.com/wegweg7979/hurunagus-hyprland`). |
| `~/Documents/GitHub/hurunagus-silverblue` | The mini box's line (Silverblue + Niri + DMS). |
| `/var/home/user/omedora-inspect` | omedora source used for inspection/porting. |
| `~/Documents/GitHub/hurunagus-rebase` | hurubase, standalone helper repo. |

The SKILL.md "user's 7 repos" table carries the full repo list; the gotcha about
TWO hurunagus-hyprland clones (and how to tell which one built the running host)
is there too — read it before editing any checkout.

## Editing rule: `/usr` is read-only

The running host is a bootc/rpm-ostree image (`hurunagus-hyprland`), so `/usr`
(including `/usr/share/omarchy`) is read-only. **Distro-level changes go into
the omedora repo — never hand-edit `/usr/share`.** `/etc` is editable, `/var` is
left untouched by rebases (which is why hurubase keeps state in
`/var/lib/hurubase/state`).

## Apps on this host that are NOT in the image

The user's own apps are Flatpaks (`flatpak list --columns=application`) or
`~/.local/bin` shims, so a trim or a rebase never touches them. Three rules
before working on one:

- **A sandboxed app cannot use `/usr` paths for its plugins.** The DAW here is
  Bitwig Studio (`com.bitwig.BitwigStudio`); VST3 plugins go in `~/.vst3/` — the
  VST3 spec's per-user location and one Bitwig scans by default, and the only
  option anyway given the read-only `/usr` above. Per-app state lives under
  `~/.var/app/<app-id>/config/`.
- **Prove the sandbox can see a host path instead of assuming it.** That flatpak
  carries `filesystems=…;host;`, so host paths appear unchanged inside it:
  `flatpak run --command=ls com.bitwig.BitwigStudio -la /var/home/user/.vst3/`,
  and `flatpak run --command=ldd com.bitwig.BitwigStudio <plugin.so>` catches a
  plugin that resolves against the host but not against the runtime's libs.
- **A `~/.local/bin` file shadows the image's command of the same name** — it is
  ahead of `/usr/bin` and `/usr/sbin` on PATH. Some are deliberate (the
  `powerprofilesctl` shim exists because Fedora's tuned-ppd ships no CLI), but a
  stale hand-written override is invisible until the command misbehaves: diff
  `~/.local/bin` against `/usr/bin` + `/usr/sbin` and check `command -v <cmd>`
  resolves where you think it does before debugging the command itself.

## Hosts (ssh aliases)

| Alias | Address / notes |
|-------|-----------------|
| `workstation` | **This host** (the one agent sessions run on). Desktop chassis, no system battery. Displays: 2x1920x1080 — HDMI-A-2 (Acer V227Q) at 0x0, HDMI-A-1 (Philips 27E1N1200A) at 1920x0. A third panel, an Acer K272HL, is gone but still owns workspace block 0 in `~/.local/state/omarchy/monitor-workspaces`, so the live monitors run on ostree workspace ids 11-20 / 21-30 (each bar still labels its own block 1-10). |
| `desktop` | .24 |
| `laptop` | .20 |
| `mini` | .149 — Intel N100 / DeskMini, on the F44 line |

### workstation display hardware (Minisforum NAB9, Alder Lake-P / Iris Xe)

- Video out is **2x HDMI + 2x USB-C in DP alt mode** — the `card1-DP-1` /
  `card1-DP-2` DRM connectors ARE the USB-C ports (hardware mux, no firmware
  involvement). There is **no USB4/Thunderbolt host**: one xHCI controller in
  `lspci`, no TB/USB4 device, and no `typec`/`ucsi`/`tcpm` driver loaded. ODM
  SSDT is named `TbtTypeC`, which is where reseller "USB4" claims come from.
- **VRR on this GPU is DP/eDP only, never HDMI.** i915's
  `intel_vrr_is_capable()` handles `eDP`/`DisplayPort` and `default: return
  false` for HDMI (upstream comment: "currently we support VRR only for
  DP/eDP"; HDMI 2.1 VRR is BMG/LNL-and-later). So on the HDMI-connected panels
  `vrr_capable` is 0 and `monitor=...,vrr,1` is a silent no-op.
- Both panels DO advertise adaptive sync (AMD VSDB: Philips 27E1N1200A 48-120Hz,
  Acer V227Q E3 48-100Hz; both also have DP 1.2 inputs). VRR is therefore
  reachable only by cabling a monitor's DP input to a USB-C port with a
  **passive USB-C-to-DP cable** — a dock/hub or DP-to-HDMI converter is a DP
  branch/PCON device and the driver refuses (`drm_dp_is_branch`).
- **Read VRR capability without root**: aquamarine logs it per connector —
  `grep -i vrr /run/user/1000/hypr/<sig>/hyprland.log` shows
  `connector HDMI-A-N crtc is incapable of vrr: props.vrr_capable -> 0`.
  Also readable: parse the connector EDID at `/sys/class/drm/*/edid`.

- **Rebooting a remote host is blocked from here**: polkit refuses a
  non-interactive ssh reboot and there is no NOPASSWD `systemctl` rule. The user
  has to run reboots on those boxes themselves — do not promise to do it.
- The desktop shell is `quickshell -n -p /usr/share/omarchy/shell`; its logs come
  from `journalctl -t omarchy-shell`.

## omedora COPR

The fork serves its own COPR: **`wegweg7979/omedora-4`** (upstream was
`agaspar/omedora-4`). Details:

- The project's owner default lives in `bin/omedora-copr` (`OMEDORA_COPR_OWNER`).
- Builds run through the repo's `copr-build.yml` `workflow_dispatch` with an
  **explicit package list — a blank list builds nothing** — from the dispatched
  ref.
- `wegweg7979/omedora-4` is the repo the running images actually consume, so its
  contents are a live dependency of every image build (see the image-drift
  gotchas in SKILL.md: same commit + rebuilt COPR = different image).

## hurubase, in one breath

Safe rebase helper for moving a box between hurunagus variants. The interface is
the image ADDRESS, not a name:
`hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest`. It needs a controlling
terminal (prompts read `/dev/tty`, so plain `ssh host './hurubase …'` dies — use
`ssh -tt`, a real terminal, or `HURUBASE_ANSWERS`), keeps state in
`/var/lib/hurubase/state`, and is re-run with the same address rather than with
`--continue`/`--finish` ceremony. Full mechanics and the test seam are in
SKILL.md's hurubase section.
