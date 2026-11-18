---
name: machine-health-check
description: Use when health-checking this machine for urgent issues.
version: 0.2.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [diagnostics, journalctl, smart, btrfs, bootc, fedora]
    related_skills: [diagnose-crash, hermes-agent, fedora-atomic-hurunagus]
---

# Machine Health Check

## When to Use

Use this skill when the user asks to:

- "check dmesg / journalctl for urgent issues", "is anything wrong with this box",
  "is my machine healthy", "how's the machine looking"
- check a machine after an OS upgrade or reboot ("upgraded to the newest build,
  everything seems fine" — verify that claim, don't repeat it)
- look at SMART / NVMe drive health, `btrfs device stats`, or "is my SSD dying"
- triage a failed systemd unit or repeated log spam on this desktop
- health-check one of **his other hosts over ssh** — `desktop`, `laptop`, `mini`
- ask whether the **LAN or wifi is noisy/chatty**, or what is broadcasting on the network
  — `scripts/lan-chatter-census.sh`, baseline and limits in
  [`references/lan-chatter-census.md`](references/lan-chatter-census.md)

Not for a single crash with a core dump — that is [`diagnose-crash`](../diagnose-crash/SKILL.md).

Run the sweep below and report **urgent vs benign** with real tool output. Do not
narrate the process.

## Ground rules

- **Never infer a capability from a package NAME — query the artifact.** I told this
  user hardware video decode was unavailable on the grounds that `rpm -q
  intel-media-driver libva-intel-driver` reported both missing. Both drivers were
  installed under **Fedora's** names: iHD is `libva-intel-media-driver`
  (`/usr/lib64/dri/iHD_drv_video.so`) and legacy i965 is `intel-vaapi-driver`
  (`i965_drv_video.so`). `vainfo` showed VA-API 1.24 served by iHD 26.4.0, and the
  user's own `about:gpu` dump already said `Video Decode: Hardware accelerated`. The
  correct probe order is: run the tool that exercises the capability (`vainfo`,
  `intel_gpu_top`, `vulkaninfo`), then `rpm -qf <the file it names>` — package names
  differ from upstream project names constantly. Same rule when a probe that needs
  root is the only one that could settle it: say the claim is *unverified*, don't
  assert the opposite.
- **A capability that reads as "missing" may be a permission gate, not a missing
  backend.** A tool reporting `Permission denied` on a perf/PMU path is being refused by
  the kernel, not finding absent hardware: btop's GPU box needs the i915 PMU (it vendors
  `intel_gpu_top`'s reader), and `intel_gpu_top -l` prints `Failed to initialize PMU!
  (Permission denied)` while `kernel.perf_event_paranoid` is 2. Run the smallest tool
  that exercises the capability, then read the gate itself —
  `sysctl -n kernel.perf_event_paranoid`, `ls /sys/bus/event_source/devices/` — before
  concluding anything about the driver. The durable fix is an `/etc/sysctl.d` drop-in
  (hand the line to the user; root stays with them), never a per-run `sudo`. Minimum
  values, the inert `setcap` route, and the btop box toggle:
  [`references/perf-and-capability-gates.md`](references/perf-and-capability-gates.md).
- **Compare across hosts before calling anything a per-host fault.** He runs the same
  image on several machines, so an odd failed unit or log line is usually image-wide.
  `systemd-remount-fs.service` failing, the `tmpfiles` symlink noise, the missing
  `system-local-login` include and the rest of the `/etc` drift all looked host-specific
  at first and were not. When a second host reproduces it byte-for-byte, stop chasing it
  per machine. Two cheap comparisons: a `/etc` md5 diff across hosts, and a control ping
  to a host you know is healthy when latency looks wrong.
- **Do not identify hosts by MAC OUI on this fleet.** NetworkManager randomizes the
  Wi-Fi MAC (stable per network), so every host presents a locally-administered MAC with
  no vendor prefix — this host included (`wlp4s0` = `0e:7b:d5:…`). I read mini's`6e:…` as evidence of "a privacy OS or a VM" and it was just the distro default.
  Identify by `hostnamectl`, `/etc/os-release`, the SSH banner or `uname -r` instead.
- **A config file is not a live change.** After editing config, verify the *state of the
  thing*, never the config file: `iw dev <dev> get power_save`, `systemctl is-active`,
  `md5sum` of the file the daemon actually read. NetworkManager applies
  `wifi.powersave` at connection *activation*, so writing it into `conf.d/` plus
  `systemctl reload` left a live wifi link in power save, and `nmcli device reapply`
  did not fix it either.
- **Writing anything under `/etc`: truncate in place.** `tee`/`cp` onto the existing path
  keeps the inode, owner, mode and SELinux label; `rm`+recreate, `mv` and `install` all
  swap the inode and lose the label (on these images the label is `etc_t`, not
  `pam_config_t`). A currently-working file's label is ground truth — never `restorecon`
  it. Before overwriting, stash a copy in his home and keep it: these files are not
  RPM-owned, so `rpm -V` cannot recover the original.
- **For changes that can lock a user out (PAM, sshd, display managers), verify
  statically and leave the functional test to the user.** Walk the include chain for
  dangling targets, confirm the journal message stops after the write's mtime, and let
  him do the real lock/unlock with an ssh session still open as a fallback. Never
  blanket-copy a known-good file from another host without reading it first — matching
  the fleet can mean silently dropping a protection the odd host had.
- **Read-only.** Never run anything that could break the running OS (no
  `rpm-ostree cleanup`, no `btrfs scrub start` without asking, no package changes).
- **Root stays with the user.** Never type a password or run `sudo` blocking on one —
  `sudo` needs a password on every host. Hand over a single copy-paste line (or the
  script under `scripts/`) and wait. Confirm which command actually ran by reading the
  audit trail (`journalctl --since -30min | grep -oE 'COMMAND=[^;]*'`) rather than
  assuming — twice he ran a different command than the one asked for, and one of them
  was a no-op I had muddied the list with.
- Don't invent a clean bill of health from an empty result — say what you could and
  could not read.

## Hosts

Four machines, two image lines. **Per-host hardware, disk layout, sensor phantoms,
ssh addresses, and the items already closed as benign live in
[`references/hosts.md`](references/hosts.md) — read the entry for the host you are on
before interpreting anything.**

| ssh alias | address | image line | hardware | tells you which host you're on |
|---|---|---|---|---|
| `workstation` | local | hyprland F45, `kernel-cachyos` | i9-12900HK, `nvme0n1p3` | `dmesg` restricted → use `journalctl -k`; NCT6798 phantoms |
| `desktop` | `.24` | hyprland F45 | i5-4690K Haswell desktop | SATA `sdc` is the OS disk; it8620 phantoms |
| `laptop` | `.20` | hyprland F45 | MacBookPro11,1, i5-4278U | `tainted=12801` from `wl`; **no `applesmc`**; `sda` not nvme |
| `mini` | `.149` | **silverblue F44, stock kernel** | ASRock DeskMini, N100 | OpenSSH 10.2 not 10.5; `plugdev` udev noise |

**Shared by all four — image-wide, benign, never a per-host fault:**

`systemd-remount-fs.service` fails (`Remount Root and Kernel File Systems`,
`mount for / exited with status 32`). Cause: the bootc-generated `/etc/fstab` declares
`/` as `btrfs subvol=root,compress=zstd:1,ro`, while `/` at runtime is a **composefs
overlay** (`findmnt -no SOURCE,FSTYPE /` → `composefs overlay`), so the fstab remount
cannot apply. Nothing is degraded — `/var` is writable, `/boot` and `/boot/efi` have
 their own units, boot completes. It is one permanently red unit that could mask a real
future remount failure. The fix belongs upstream in the image, NOT as a hand-edit of
`/etc/fstab` (`bootc-fstab-edit.service` rewrites it on deploy). Likewise
`systemd-tmpfiles: /home /srv /root already exists and is not a directory` — those are
the ostree symlinks to `var/home`, `var/srv`, `var/roothome`.

## The sweep

Batch these in parallel (they are independent), all unprivileged. Over ssh, use a
generous timeout (`ssh -o ConnectTimeout=10`, `timeout 150`) and keep each call's output
bounded — one host is on a poor wifi link.

```bash
# 1. baseline: is this even the same boot / deployment as last time?
date; uptime; uname -r; head -4 /etc/os-release
cat /proc/sys/kernel/random/boot_id; journalctl --list-boots --no-pager | tail -5

# 2. real faults: errors, then the specific killers
journalctl -b -p err --no-pager -o short-monotonic | tail -30
journalctl -b -p crit --no-pager
journalctl -b --no-pager | grep -Ei "out of memory|oom-kill|machine check|media and data|I/O error|EXT4-fs error|BTRFS (error|warning)|gpu hang|ring.*reset|drm.*(error|timeout)|segfault|core dumped"

# 3. units + resources
systemctl --failed --no-pager
df -h / /var /boot; free -h; cat /proc/sys/kernel/tainted

# 4. kernel ring (substitute for dmesg) — i915 / drm / power
journalctl -k -b -p warning --no-pager
journalctl -k -b --no-pager | grep -iE "i915|dmc|drm" | tail -10

# 5. crashes over time, not just now
coredumpctl list --no-pager | tail -15

# 6. update state
rpm-ostree status
```

Add host- and hardware-specific probes from `references/hosts.md` (wifi link quality,
battery via ACPI, `applesmc` presence, disk-to-port mapping). Then filter the noise
against [`references/known-benign.md`](references/known-benign.md) **and** the host's
own "closed / accepted" list in `references/hosts.md` before writing anything up.
Anything in either file is **not** a finding — list it as known noise and move on.

## Continuous hardware watch (power-path faults)

`scripts/hw-watch.py` is the unprivileged sampler behind the 5-minute watchdog on
`workstation` — live copy at `~/.hermes/scripts/hw-watch.py`, because a Hermes cron job's
`script` must sit under `~/.hermes/scripts/`, driven by a `no_agent` job so **empty
stdout delivers nothing**. Each tick appends to `~/.hermes/state/hw-watch/hw.csv`:
package/core temp, fan RPM, PROCHOT + core-throttle counters, NVMe temp + alarm, RAPL
watts, the CPU power limits, and every NCT6798 rail. It prints an alert block only on a
threshold trip — keyed per category, re-printed at most hourly, with a one-off "ok now"
line when a condition clears. Rails are judged against their **own rolling baseline**
(~8 h), never against assumed nominal values: this board's channels are unlabeled and
`in8` legitimately sits ~0.2 V under the other 3.3 V channels. `HW_WATCH_FORCE_ALERT=1`
exercises the delivery path without touching thresholds.

The live job on `workstation` is `6af4c31a7352` ("workstation hardware health watch
(NAB9)"): `every 5m`, `no_agent`, `deliver=origin` — so alerts land as a **note in that
desktop chat, not a live push**, and a recurring job also runs once on return, which is
what produces the first sample after an outage. Creation was verified end to end: the
first tick fired 09:51:34 with `status ok` and a row in the CSV, stdout empty (so nothing
was delivered).

Be honest about its reach: it **cannot predict an instant capacitor failure**. What it
gives you is a rail/temp record leading up to the next death (and a first tick after
boot, since recurring jobs run once on return). When a host dies hard, the recall note
in `references/hosts.md` is worth more than the sampler.

## Verifying "it's upgraded / everything's fine"

Treat a claim of an upgrade as unverified until the machine agrees. An in-place
bootc/rpm-ostree update is only real after a reboot, so check **all** of:

- a new `boot_id` and a new boot in `journalctl --list-boots` (uptime resets);
- `uname -r` and `/etc/os-release` (VERSION/NAME change on a base bump);
- `rpm-ostree status`: which deployment is `●` booted vs the prior one, digest +
  version string, `State: idle`, and whether anything is staged (a staged
  deployment = update pending reboot, not applied);
- `/boot/loader.0` + `bootupd-state.json` mtimes if the bootloader matters;
- then re-check that the previously reported findings are actually gone on the
  **new boot**, and say which ones are.

**On a hurunagus/omedora base bump, add the payload checks and the migration test.** The
upgrade is only half-done if the desktop-app set or the migration queue did not move:
`rpm -q omedora omedora-settings` (the NEVRA embeds the COPR build's git commit, so it tells you
*which* payload change landed), the apps the base added, the ones the image excludes, and the
commands the fork prunes (they must stay absent). For migrations, **do not trust the journal**:
after this box's 4.5 upgrade neither the system nor the user journal contained a single
`Running migration` line, yet the run had happened two minutes after boot. The authoritative
signal is the marker mtimes -
`ls -lt ~/.local/state/omarchy/migrations | head` and a count of markers newer than the boot
(103 of 220 here, matching the expected new-migration count), plus `omarchy-migrate --pending`
being empty. Note `--pending` exits **1** on this implementation even when it prints nothing, so
read its *output* (or the marker diff), not its exit code.

Rollback availability is worth one line: a second non-booted deployment means
`rpm-ostree rollback` is possible — but **compare the digests**, because two
deployments of the *same* version (one just carrying layered packages) give no rollback
to a previous build at all.

## Disk health (needs root — hand it to the user)

`nvme smart-log` / `smartctl` / `btrfs device stats` all need root, so have the
user run the skill's script — one password prompt, strictly read-only, output
written back to the agent's scratch dir as `user`:

```bash
sudo bash ~/.hermes/skills/machine-health-check/scripts/smart-report.sh
```

**On a remote host the script does not exist there**, so hand over an inline one-liner
instead, writing into his home dir on that box (`OUT=/var/home/user/smart-report-<host>.txt`,
then `chown user:user $OUT`) and read it back over ssh. Adapt the device: `/dev/nvme0` on
`mini` and `workstation`, `smartctl -d sat -a /dev/sda` on the `laptop`, `/dev/sdc` on
`desktop`.

What matters in that output:

- `critical_warning: 0`, `media_errors: 0`, `percentage_used`, `available_spare`
  vs threshold, `Warning/Critical Composite Temperature Time` (must be 0).
- `Unsafe Shutdowns` is the one counter that is often non-zero and is *not* a
  fault by itself — note it, check `media_errors` stayed 0.
- `Thermal Management T1 Total Time` is in **minutes** per spec (T1 = light
  self-throttling, below the Warning temp) — convert before reporting, and do not
  present throttling time as a temperature problem.
- `btrfs device stats`: `write/read/flush_io_errs`, `corruption_errs`,
  `generation_errs` all zero = clean; any non-zero is a genuine finding. On some hosts
  this reads **unprivileged** — try it before asking for root.
- `btrfs scrub status` saying `no stats available` means **no scrub has ever
  run** — on older deployments no `btrfs-scrub@.service`/`.timer` ships at all, so
  `no corruption` rests on device counters + journal, not on a checksum pass. Say that
  plainly and offer the scrub rather than claiming verification.
- Also grep the *whole* journal for `btrfs`/`nvme` error strings to cover earlier
  boots, not just `-b`.

## Filesystem maintenance (only when the user asks for it)

Order of business on `workstation` (numbers below are that machine's; the procedure is
general):

1. **Scrub — the one thing worth doing.** `discard=async` is on and `fstrim.timer`
   is enabled weekly, so trim is already covered; the gap was that the filesystem
   had never been scrubbed at all. Run the skill's script (one root prompt — starts
   the scrub, waits, and writes progress plus post-scrub `device stats` to the
   scratch dir for the agent to read):

   ```bash
   sudo bash ~/.hermes/skills/machine-health-check/scripts/btrfs-scrub.sh
   ```

   **Pitfalls (verified on this box, btrfs-progs 7.1):**

   - `btrfs scrub status <mnt>` is readable without root **only until the first
     scrub has ever been started**. Afterwards it fails with `failed to open status
     file: Permission denied`, because `/var/lib/btrfs/scrub.status.<fsid>` is
     created `root:root 0600`. Read status as root (the script does), or `chmod 644`
     that one file so polling works again — a change, so ask first. Before any scrub
     the same command innocently prints `no stats available`, which must not be
     mistaken for "clean".
   - `btrfs scrub start` can **block for the entire scrub** instead of returning, so
     background it explicitly — `( btrfs scrub start /var ) &` — or the wrapper
     stalls and logs no progress at all. When it does background, `-B` means the
     opposite of what it looks like: *do not* background (foreground).
   - The authoritative completion signal is the kernel log:
     `BTRFS info (device nvme0n1p3): scrub: finished on devid 1 with status: 0`.
     `status: 0` = no errors found and nothing uncorrected by the DUP metadata copy.
     Cross-check it against the tool's own `Error summary:` line.
   - Measured throughput here is **~2.96 GiB/s** (284.44 GiB of 408 GiB allocated,
     finished in 1 min 36 s), so a scrub costs minutes — cheap enough to run
     whenever asked. `mini` has 92.84 GiB to scrub and `desktop` 40.72 GiB.
   - A scrub can allocate a new `System,DUP` chunk (8 MiB → 40 MiB allocated seen),
     which barely moves `Device allocated`. Benign, not a finding.

   **Recurring scrub:** from the 2026-11-08 image build onward, `btrfsmaintenance`
   ships with `btrfs-scrub.timer` (monthly, `Persistent=true`) and
   `btrfsmaintenance-refresh.path` enabled, tuned by the repo's
   `system_files/etc/default/btrfsmaintenance`. Deployments older than that have
   nothing recurring — **and `mini`'s silverblue line has none at all**, not even the
   package. Check with `systemctl list-timers 'btrfs*'` and
   `systemctl cat btrfs-scrub.timer` (the generated drop-in carries the real
   `OnCalendar`).

   **Pitfall when configuring it:** the package defaults every job's
   `MOUNTPOINTS` to `/`, and on a composefs/ostree image `stat -f --format=%T /`
   is `overlayfs` — so the job logs `Path / is not btrfs, skipping`, exits 0, and
   looks like it ran. Set `BTRFS_SCRUB_MOUNTPOINTS="auto"` (resolves one
   mountpoint per btrfs *device*, collapsing the four mounts of the single btrfs
   device into one pass) and put the overrides in `/etc/default/btrfsmaintenance`:
   every job script *and* the scheduler source it **after**
   `/etc/sysconfig/btrfsmaintenance`, so it wins without touching the RPM-owned
   file. The package also ships a **weekly balance** — set
   `BTRFS_BALANCE_PERIOD="none"`.
2. **Balance — not needed here.** ~428 GiB allocated of ~951 GiB with ~523 GiB
   unallocated and ~67% of data chunks used is a healthy allocation, and a full
   balance is write-heavy. Only propose a filtered balance (`-dusage=` / `-musage=`)
   if allocation goes ragged or the fs reports ENOSPC while unallocated space remains.
3. **`btrfs check` must never be run against a mounted filesystem** — it wants the
   filesystem unmounted and can corrupt a live one. If asked for it, decline and
   explain rather than running it.

Set expectations before a scrub: the data profile is `single`, so the pass can
**repair metadata** (from the `DUP` copy) but can only **detect** data corruption —
one device, no second copy of data. It is a read pass, safe on a live filesystem,
cancellable with `btrfs scrub cancel` and resumable with `btrfs scrub resume`, and
on this ~408 GiB allocation it takes minutes, not hours.

## Report shape

1. One-line verdict first ("nothing urgent" / what is actually wrong).
2. Machine state in one paragraph (uptime, kernel, RAM, disk, temps).
3. **Real findings** as a table with cause + impact — separating what the evidence
   proves from what is inferred.
4. **Known noise** — collapsed to one line, referencing `references/known-benign.md`
   and the host's closed list in `references/hosts.md`.
5. **Coverage limits**: what you could not read (root-only data, restricted
   dmesg) and the one command that would fill the gap.
