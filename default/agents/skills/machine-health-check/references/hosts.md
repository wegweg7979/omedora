# Per-host reference

Read the entry for the host you are on **before** interpreting anything. Results that
look alarming are almost always hardware or image-line quirks documented here.

Four machines, two image lines:

| ssh alias | address | image line |
|---|---|---|
| `workstation` | local (no ssh needed) | `hurunagus-hyprland` F45, `kernel-cachyos` |
| `desktop` | user@<lan-ip> | `hurunagus-hyprland` F45 |
| `laptop` | user@<lan-ip> | `hurunagus-hyprland` F45 |
| `mini` | user@<lan-ip> | `hurunagus-hyprland` F45 (rebased 2026-11-12) |

All four have key auth set up from `workstation` (`~/.ssh/id_ed25519`), host keys
pinned, and `sudo` that **requires a password** on every one of them.

**Shared by all four — image-wide, benign, never a per-host fault:** the
`systemd-remount-fs.service` failure and the `tmpfiles /home /srv /root` noise. Both
are explained in the SKILL.md body; do not re-derive or re-report them per host.

---

## `workstation` (this machine)

Image `ghcr.io/wegweg7979/hurunagus-hyprland:latest` (bootc / rpm-ostree world:
**composefs read-only root** + Btrfs on `nvme0n1p3` mounted at `/var`, separate
`ext4 /boot` + `vfat /boot/efi`). Desktop: sddm → uwsm → Hyprland → quickshell, on
Intel i915 (Iris Xe, ADL GT2). **The CPU is a 12th-gen `i9-12900HK` — 14 cores /
20 threads, 400 MHz–5.0 GHz (ADL-P/H), in a 'Venus series' barebone — NOT an N-series
chip.** Verified with `lscpu` after a `scaling_cur_freq` reading of 4.90 GHz looked
impossible on the N-series part this skill originally (wrongly) claimed. Consequences:
H-class heat and a fast fan are normal, a 5 GHz reading is real, and a ~75 °C
*transient* under load is unremarkable — judge temps against the crit values (100 °C
package, 78.8 °C NVMe), not against N-series expectations.

- Kernel/hostname change between boots is normal here: a base bump shows as
  `7.2.15-200.fc44` → `7.2.15-300.fc45`. From the 2026-11 build onward the kernel is
  `kernel-cachyos` (swapped in from the bieszczaders COPR), so `uname -r` reads like
  `7.3.3-1.cachyos1.fc45.x86_64` and `rpm -q kernel` reports nothing — expected, not
  a fault.
- `kernel.dmesg_restrict=1`, so bare `dmesg` returns **one line and looks empty**. The
  kernel ring is available unprivileged via `journalctl -k`. Use that.
- `rpm-ostree status` works unprivileged; `bootc status` **requires root** and will just
  error out. Journal access works — the user is in the journal group.
- Radio is an **Intel AX210** (`8086:2725`, iwlwifi/iwlmvm). Two limits to know before
  reaching for wifi introspection: `iw dev wlp4s0 survey dump` returns **nothing at all**
  (exit 0, empty) and `/proc/net/wireless` reports `noise -256` — that is the kernel's
  "driver does not report a noise floor" sentinel. So **RF noise/interference cannot be
  measured on this card**; use `iw dev wlp4s0 link` plus `station dump` counters
  (signal, `tx retries`, `rx drop misc`) and the discarded-packet column in
  `/proc/net/wireless` instead. The phy *does* advertise `monitor`, but
  `valid interface combinations` lists only managed/P2P/AP — so monitor is **not a
  concurrent mode** here: creating it takes the radio and drops this host's own
  connection.

### The NAB9 capacitor recall — read this BEFORE chasing a power fault

This host is a **Minisforum Venus-series NAB9**. Minisforum recalled NAB9 units built
**2024-09-19 → 2025-03-14** whose **motherboard capacitors** were made with the wrong
materials. The symptom in the notice is verbatim: *abnormal shutdowns*, or *failure to
power on after a normal shutdown, with no indicator lights*. SN test: 3rd–5th
characters of the underside SN in **017–117** (3rd char `7`) or **386–526** (3rd char
`6`). The remedy is an **RMA, not a PSU swap and not a software fix** —
<email> / <email> or the original purchase channel;
replacement carries +12 months warranty, and **the SSD must be removed before the unit
is returned** (data does not come back, so back it up first).

So: on this box a **hard power-off with no software cause is a hardware symptom, not a
mystery.** Do not spend the investigation on drivers, thermals or the mains — confirm
the cut from the filesystem side, quote the SN range, hand over the RMA line.

**2026-11-17 23:29:46 GMT — this box died exactly that way**: a "pop" was heard, only
this machine dropped (nothing else in the room), and it refused to start until 09:29
the next morning = **9 h 59 m with zero log entries**.

**Signature of an unclean cut (use this shape every time):**

- the previous boot's journal ends **mid-line on a routine message** (here an `rclone`
  VFS line) with **no shutdown sequence** — every *clean* boot on this host ends with
  `Unmounting var-home.mount`;
- next boot shows the replay: `BTRFS info ... start tree-log replay`, fsck
  `recovering journal` on ext4 `/boot`, `Dirty bit is set. Fs was not properly
  unmounted` on the vfat ESP (auto-cleared), and journald's `user-1000.journal
  corrupted or uncleanly shut down, renaming and replacing` — the orphan
  `user-1000@…journal~` file is stamped with the cut time;
- `journalctl --list-boots` leap = the off time; count entries in the gap (zero);
- **what rules software out**: no MCE, no AER/PCIe error, no NVMe I/O error, no thermal
  critical, no watchdog, no panic — and `tainted` reads **512 (bit 9 WARN)**, with bit 4
  (MACHINE_CHECK) clear.

**CPU power limits are BIOS/EC-set, not a userspace script:** RAPL PL1 **35 W** /
PL2 **45 W** (`constraint_0/1_power_limit_uw`), `intel_pstate` `active`,
`max_perf_pct` 100. The only `/etc` rule touching powercap is `99-powercap.rules`,
which merely chmods `energy_uj` readable — do not report it as the source of the cap,
and do not "restore" the limit without asking (the user set it deliberately).

**Power input, and the parts worth salvaging (replacement, not repair):** the adapter is
an **external DC 19 V / 120 W brick**. The box has no battery and no UPS client is
installed (`nut`/`upsc`/`apcaccess` all absent), so an abrupt power-off is either the
mains or that brick and **the OS cannot tell you which** — say so instead of assuming the
mains. Salvageable hardware: **32 GB as 2 × 16 GB DDR4 SODIMM** (module marking
`WPBH32D408SWM-16G`; only ONE SPD EEPROM enumerates unprivileged, so `dmidecode -t 17` as
root is the only way to read the pair), a **Kingston `OM3PGP41024P-A0` 1 TB PCIe 4.0
M.2 2280** NVMe, an Intel **AX210** (M.2 2230), and on the board 2× i226-V 2.5 GbE plus
an empty 2.5" SATA bay. Displays in use: 2× 1920×1080 on `HDMI-A-1/2`. A replacement must
therefore accept **DDR4 SODIMM + M.2 2280** to avoid re-buying RAM — which matters,
because as of 2026-11-18 the plan is to **replace** the box (Amazon refund, or
Minisforum's own RMA, only if honored) rather than repair it. Expect the machine identity
to change; re-baseline this entry after the swap.

### Sensors on this board

`sensors` lists a Nuvoton NCT6798 whose unconnected channels read as alarming nonsense.
Report the real ones; name the phantoms so the user does not worry:

- **Real:** `coretemp` Package id 0 + cores, `PECI Agent 0` (agrees with coretemp
  within a few °C — useful cross-check), `CPUTIN`, `nvme-pci-0100` Composite,
  `iwlwifi_1`, `acpitz` / `thermal_zone0` (effectively ambient, ~28 °C).
- **Phantom — ignore, and say why:** `SYSTIN` +111 °C, `AUXTIN0/1/2/4` 106–110 °C and
  `AUXTIN3` **−29 °C**, all flagged ALARM; `intrusion0/1: ALARM`; `in1–in14` ALARM
  (their limits read `min +0.00 V max +0.00 V`, i.e. unconfigured, so they alarm
  unconditionally); `PCH_*_TEMP: 0.0 °C`. Evidence they are unwired: a negative
  temperature cannot occur in a running machine, and the same board reports 60–63 °C
  through two independent paths (PECI + coretemp) — a genuine 111 °C could not sit
  48 °C above those.
- **Fans:** `fan1` ≈ 7.1 kRPM and `fan2` ≈ 2.9 kRPM are the only two physically present
  (`fan3–7` read 0 — unpopulated headers). Neither moves across a 57–70 °C package swing.
- **The board DOES expose PWM — do not claim "the BIOS is the only lever"** (I did, and
  had to walk it back). `nct6798` offers `pwm1 pwm2 pwm3 pwm4 pwm5 pwm7`: `pwm1`/`pwm2`
  sit in the chip's automatic profile (`pwmN_enable=5`, duty 150 ≈ 59 % and 76 ≈ 30 %)
  while the rest are `enable=1` (manual) with no tach attached. So Linux can read exactly
  what the firmware is asking for and *could* take over via `pwmconfig`/`fancontrol` —
  but that is a deliberate thermal change on a 55 W-class i9, not a casual tweak.
- `hidpp_battery_0/1` are not thermal at all: Logitech K540/K545 keyboard + mouse
  battery levels, surfaced by `sensors` alongside the temperature chips.

---

## `desktop` (same image, different hardware)

`ssh desktop` (user@<lan-ip>) runs the same `hurunagus-hyprland` image but is a
**Haswell desktop** — do not carry workstation's numbers over to it:

- `i5-4690K` (4c/4t), 31 GiB RAM + 8 GiB zram swap, `i915` HD 4600.
- Disks are **SATA SSDs, not NVMe**: `sda` Samsung 840 (holds a Windows NTFS install),
  `sdb`/`sdd` Verbatim Vi500 S, `sdc` **Crucial BX500 = the OS disk**, same layout as
  workstation but at `/dev/sdc1`–`sdc3` (vfat `/boot/efi`, ext4 `/boot`, btrfs `/var`).
  `nvme smart-log` is useless here — use `smartctl -a /dev/sdX`. Map a disk to its port
  with `readlink -f /sys/block/sdX/device` (the `ataN` segment).
- `sde`–`sdi` are a USB stick + a 4-slot card reader (0 B). They are the source of the
  `ATTR{queue/scheduler}="bfq" ... Device or resource busy` udev noise when they have no
  media — **benign**, and `bfq` genuinely is present and active on the real disks
  (`none mq-deadline kyber adios [bfq]`), so the rule is fine.
- Sensors are an **it8620**, not the nct6798. Real: `coretemp` package, `temp3`
  (Intel PECI), `acpitz`, `fan1/2/4`. Phantoms: `temp2: -128 °C`,
  `intrusion0: ALARM`, `in4: 12 mV`. Idles ~30 °C package.

**Closed on desktop — verified benign, do not re-report:**

- `scx_loader: Failed to start scheduler (attempt N/5)` — July-only lines; the unit is
  `not-found` in the current image and `/sys/kernel/sched_ext/state` is `disabled`.
  Historical, and the 75 lines across four July days are all there is.
- `system-flatpak-setup.service` failures — it now runs clean (`Finished`, 46 flatpaks
  + 2 remotes) and no flatpak unit is failed.
- `chronyd: Could not add source 192.36.144.22 : Already in use` (~100 ×/journal) —
  cosmetic duplicate; chrony is locked to that server at stratum 2 with sub-ms offsets.
  No `conf.d/` exists. Do not call this a time-sync fault.
- Historical coredumps (gnome-session-service, gvfsd-dav, hyprland-update-screen) are
  old and retained no core file.
- `ata6.00: Read log 0x00 page 0x00 failed, Emask 0x4` on **`sdd` (Verbatim Vi500 S)**
  — a single occurrence in 70 boots of journal, Jul 21. Not the OS disk. Low severity,
  monitor only; SMART on `sdd` is the one thing left to read there.
- SATA chatter that is normal: Samsung 840 `NCQ Send/Recv Log not supported`, the OS
  disk's `LPM support broken, forcing max_power` (higher idle power, not a fault).

---

## `laptop` (Apple hardware — `MacBookPro11,1`, mid-2014 13")

`ssh laptop` (user@<lan-ip>). Same image, so the remount-fs / tmpfiles noise is
identical — what differs is the Apple hardware:

- `i5-4278U` (2c/4t), 8 GiB RAM, Iris 5100 `i915`, Broadcom **BCM4360**. One SSD at
  **`/dev/sda`** on libata, NOT nvme (`sda1` vfat /boot/efi, `sda2` ext4 /boot,
  `sda3` btrfs /var). So `nvme` / `-d nvme` are useless here; use
  `smartctl -d sat -a /dev/sda`, and expect an Apple SSD to refuse SMART anyway.
- **`applesmc` does not exist in the kernel-cachyos build.** Not blacklisted
  (`modprobe.d` holds only firewalld-sysctls, lockd, omarchy-usb-autosuspend, tuned):
  `modinfo applesmc` fails, it is absent from `modules.builtin*`, there is no `.ko` and
  no `APP0001` platform device — while `apple_gmux`/`apple_bl`/`applespi`/`hid_apple`/
  `bcm5974` are all present. Consequence: `sensors` shows ONLY `coretemp` + `BAT0-acpi`
  — no fan RPM, no SMC temps, no keyboard backlight (no `kbd_backlight` LED). The SMC
  still drives the fans itself, so there is no thermal risk, only blindness.
- **Taint is `12801` (P|O|E|W) vs `0` on the other hosts**, fully explained by the
  layered `akmod-wl`. It prints "You are using the Broadcom STA wireless driver ...
  incompatible with Linux kernel security mitigations" and trips
  `WARNING: arch/x86/kernel/cpu/bugs.c:3790 __warn_thunk` ("Unpatched return thunk in
  use"). No in-tree driver claims `14e4:43a0` (`grep v14E4D43A0 modules.alias` is
  empty), so `wl` is the only option — **do not propose a driver swap**. Treat
  `wl_notify_scan_status ... Scan_results error (-22)` and `bgscan ... Failed to enable
  signal strength monitoring` as driver noise.
- Battery comes from ACPI (`BAT0-acpi`). **Health = `CHARGE_FULL` /
  `CHARGE_FULL_DESIGN`, not `CAPACITY`** (`CAPACITY` is just state of charge).
  68 % / 321 cycles = past Apple's 80 % service threshold.
- Apple firmware quirks that are NOT faults: `[Firmware Bug]: TSC ADJUST differs …
  Restoring`; `ACPI Error: Aborting method \_SB.PCI0.XHC1._PS0 … AE_AML_LOOP_TIMEOUT`
  (fires during *some* resumes → USB may not re-enumerate, intermittently);
  `ata1.00: unexpected _GTF length (8)`; `spi-nor spi0.0: supply vcc not found`.
  `s2idle [deep]` = deep/S3 selected, and suspend/resume otherwise works.
- Flatpak: the image list is `/usr/share/ublue-os/flatpaks/system-flatpaks.list`
  (29 entries). `com.bitwig.BitwigStudio` cannot install anonymously (paid title) and
  always logs `warning: failed to install ...; continuing` — not a fault, and the
  boot-time `libostree HTTP error from remote flathub … Timeout was reached` retries are
  that same download. `flatpak list --app` excludes extensions, so diffing the list
  false-positives on `org.virt_manager.virt_manager.Extension.Qemu`.

### The PAM case — worked, and the trap in it

This box carried a **stale** `/etc/pam.d/omarchy-lock-password`: a hand-rolled stack
ending `account include system-local-login`, and that file exists on NO host, so
quickshell logged `PAM _pam_load_conf_file: unable to open config for
system-local-login` on every lock. `/etc` persists across deployments and the file is
**not RPM-owned** (`rpm -qf` fails), so `rpm -V` and bootc both miss it — compare the
file across hosts instead.

**The trap: do NOT blanket-copy the fleet's file.** The current image version is just
`auth/account include system-auth`, and `/etc/pam.d/system-auth` →
`/etc/authselect/system-auth` contains **no `pam_faillock` at all** on this image (the
fleet file's own comment claiming "incl. its faillock policy" is false). Copying it
would have silently *removed* the lock screen's failed-attempt lockout. The MacBook's
legacy stack held the only real lockout in the fleet (`deny=10 unlock_time=120`, and
`pam_faillock.so` is genuinely installed), so the correct minimal fix was repointing
just `account include system-local-login` → `system-auth` — one token, in place, with
the backup kept at `/var/home/user/omarchy-lock-password.bak-20261110T150653Z`.
Verified after: `md5 b5e6f386c360a7220caee0b02b051774`, label still `etc_t`, chain walk
clean, and his lock/unlock authenticated through it.

**Fleet-wide, still open (his call):** no host has a failed-attempt lockout at the lock
screen. Worth an upstream fix in `omarchy-lock-password`.

**Accepted by the user — do NOT re-raise as actionable:**

- The `wl` kernel taint (`P|O|E|W`) is **unavoidable and accepted**: no in-tree driver
  claims `14e4:43a0`, and he judges it better than a USB wifi dongle. Mention only if
  asked.
- Missing `applesmc` — **not important** to him. Don't propose kernel swaps for it.
- The 68 % / 321-cycle battery — **accepted**; it's an old machine. No replacement talk.

Still open but low priority, by his judgment:

- `akmod-wl` being a **layer** rather than baked into the image. Distinct from the taint
  and *is* actionable (he builds the images) — but it belongs on the image-repo backlog,
  never as a live-box action. Each update must re-layer and rebuild it against the next
  kernel, which is the real risk.
- The `XHC1` resume ACPI error: firmware-level, nothing to fix. Only value is awareness
  that USB may not re-enumerate after some resumes.
- Operational note: because the kernel is permanently tainted, a genuine kernel
  Oops/crash here must be correlated against `wl` before being taken at face value.

---

## `mini` (ASRock DeskMini, `hurunagus-hyprland` line)

`ssh mini` (user@<lan-ip>), hostname `mini`. **Rebased onto `hurunagus-hyprland`
(F45) on 2026-11-12** — it was the last host on the `hurunagus-silverblue` F44 line, so
the old F44 / stock-kernel facts in earlier notes are history. It now runs the same image
and kernel as the other three (`kernel-cachyos`, Fedora 45, `omedora 0.3.0~beta.1`), and
its OpenSSH moved to 10.5 with the line — the old "10.2 vs 10.5" tell is gone. Still
ships Omarchy/quickshell. It is a **shared, in-use box**: other people in the household
use this machine, so propose nothing disruptive.

- ASRock DeskMini (`Micro Computer (HK) Tech Limited` / `DeskMini Series`), Intel
  **N100** (4c/4t, Alder Lake-N), 15 GiB RAM, chassis type 35, one `nvme0n1` (`p1` vfat
  /boot/efi, `p2` ext4 /boot, `p3` btrfs /var). Sensors: `coretemp` (47 °C idle),
  `nvme-pci`, `iwlwifi_1`, `TCPU`; **phantoms** = `acpitz temp1` −273.3 °C and the nvme
  "Sensor 1" limits reading ±65261.8 °C.
- Two deployments, so **rollback IS available** here (unlike the MacBook, whose two
  deployments shared one digest).
- **Its udev group noise is now the hyprland line's `disk`/`audio`/`clock`**, not the
  old silverblue `plugdev` — the rebase changed it. Harmless either way.
- **`btrfsmaintenance` IS present and the scrub timer runs** since the rebase
  (0.5.2-7.fc45, `btrfs-scrub.timer`); the old silverblue line had neither. `fstrim.timer`
  is enabled and `btrfs device stats` reads unprivileged (all zero).

### Its wifi, and the fix that worked

`wlp0s20f3` (Intel ADL-N CNVi `8086:54f0`, iwlwifi/iwlmvm), 5 GHz, signal **−62 /
−66 dBm avg** (vs −48 on workstation), single-stream (HE-NSS 1, 97–172 Mbit/s),
**`Power save: on`** with NetworkManager `wifi.powersave` unset (so default), plus
`tx retries` 115k and `rx drop misc` 77k. Result was LAN latency min 30 / avg 86 ms
where every other host is 1–3 ms. Be precise — it was **slow, not flapping**: only 1
`CTRL-EVENT-DISCONNECTED` (reason=4, locally generated).

**What fixed it:** `sudo iw dev wlp0s20f3 set power_save off` moved 30-packet latency
from min 7.4 / avg 67.9 / max 158.6 ms (24/30 >20 ms, 20/30 >50 ms, mdev 39) to
min 2.2 / avg 9.5 / max 36.6 ms (2/30 >20 ms, 0/30 >50 ms, mdev 7). Power save was the
dominant cause.

**What did NOT fix it, and this is the trap:** (1) writing
`/etc/NetworkManager/conf.d/99-wifi-powersave.conf` with `[connection]
wifi.powersave = 2` plus `systemctl reload NetworkManager` changes nothing on the live
link — `wifi.powersave` is per-connection and applied at *activation*; (2)
`sudo nmcli device reapply <dev>` also does nothing, it re-pushes the stored profile.
Always verify with `iw dev <dev> get power_save`, never with the config file. To make it
survive reconnects without a reboot: `nmcli con down <name> && nmcli con up <name>`.

**Residual, still open:** ~3–6× slower than the other hosts even with power save off,
and that part is *link quality*, not power save — rx stays pinned at MCS 2 / 48.7 Mbit/s
against tx MCS 7 / 172 Mbit/s with `rx drop misc` ~77k, plus `iwlwifi: missed beacons
exceeds threshold`. The `enp1s0` port is DOWN with carrier 0, so wired is available and
is the real answer rather than more tuning. His call; he parked the nvme SMART read.

**Closed on mini:** `bluetoothd: Failed to set mode: Failed (0x03)`; historical
`minecraft-launcher` SIGABRT and `/app/brave/brave` SIGTRAP coredumps with no core
retained; `fedora-release is not installed` (custom release package). `tainted: 0`, no
crit entries, temps 36–49 °C. Also `systemd-logind: Failed to open
'/boot/loader/entries': Remote address changed` — errno 78 EREMCHG on a *local* ext4
dir, twice at boot, only `/boot/loader.1/entries/ostree-1.conf` present and no
`loader.0`; cause unverified, affects only logind's bootloader-entry enumeration — and
`Two services allocated for the same bus name org.freedesktop.IBus` (66× across boots,
possible IME flakiness). One user binary,
`…/audio_lip_sync_pro/bin/linux-x64/wavlm_blendshape_predictor`, logs `started with
executable stack` (no PT_GNU_STACK) — that process only, kernel stays untainted.
