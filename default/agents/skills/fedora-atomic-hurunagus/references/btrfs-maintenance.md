# btrfs maintenance in the hurunagus bootc image

Goal: maintenance that happens on its own. The stock image ships no
`btrfs-scrub@.service`/`.timer` and no `btrfsmaintenance`, so nothing verifies
checksums over time. The **host-side one-off scrub** lives in the
`machine-health-check` skill (`scripts/btrfs-scrub.sh`) together with the
timeit/status traps; this file is about making the IMAGE carry the schedule.

## What to add, and where it goes

1. `btrfsmaintenance` → `EXTRA_PACKAGES` in `build_files/build.sh` (it is a Fedora
   tool, so it belongs with `sddm`/`lm_sensors`/`firefox`, not in the vendored
   Omarchy lists that `fedora-resolve.py` processes).
2. NEW `system_files/etc/default/btrfsmaintenance` — the override file. `build.sh`
   copies `system_files/` AFTER the package install, so ordering is already right.
3. The enable/refresh steps → the "Enabling services" block of `build.sh`.

## Why an override file, and why that path

The package ships the rpm-owned `/etc/sysconfig/btrfsmaintenance`. Every job script
**and the scheduler** source, in this order:

```sh
. /etc/sysconfig/btrfsmaintenance
. /etc/default/btrfsmaintenance
```

Last sourced wins. So `/etc/default/btrfsmaintenance` is the unowned override seam:
your values win, the package's file stays pristine, and a future package update
cannot clobber the settings. (Generalized for any sysconfig-era Fedora package: ship
the override in the path the scripts read LAST.)

## Why the stock defaults silently do nothing here

Every job defaults to `MOUNTPOINTS="/"`. On a composefs/bootc host `/` is an
overlay — `stat -f --format=%T /` returns `overlayfs` — so `btrfs-scrub.sh` prints
`Path / is not btrfs, skipping`, **exits 0**, and the timer looks healthy while zero
blocks get verified. Trap: an installed-but-inert maintenance package reads as
success in every status check.

All the real mounts are subvolumes of ONE device:

```
findmnt --types btrfs --output TARGET,SOURCE --noheading
/etc, /sysroot, /var, /var/home   →  /dev/nvme0n1p3
```

Use `BTRFS_SCRUB_MOUNTPOINTS="auto"`: `expand_auto_mountpoint` dedupes by *device*
(`findmnt --types btrfs --output SOURCE | sort | uniq`, then the first mountpoint per
device), giving exactly ONE scrub pass instead of four over the same filesystem.
Hardcode `/var` instead when you want the log line to be deterministic.

## Settings to ship

| Setting | Value | Reason |
|---|---|---|
| `BTRFS_SCRUB_MOUNTPOINTS` | `"auto"` | one pass per btrfs device; never `/` (overlayfs → skipped) |
| `BTRFS_SCRUB_PERIOD` | `"monthly"` | upstream default; a full pass here is ~1 min 36 s |
| `BTRFS_SCRUB_PRIORITY` | `"idle"` | ionice idle; the service also sets `IOSchedulingClass`/`CPUSchedulingPolicy=idle` |
| `BTRFS_SCRUB_READ_ONLY` | `"false"` | let it repair metadata from its `DUP` copy (data is `single`, so detect-only) |
| `BTRFS_BALANCE_PERIOD` | `"none"` | stock default is **weekly** balance — write churn for nothing on a healthy single-device allocation |
| `BTRFS_DEFRAG_PERIOD` | `"none"` | defrag re-COWs for no gain here |
| `BTRFS_TRIM_PERIOD` | `"none"` | `/var` already mounts `discard=async` and `fstrim.timer` runs weekly — don't double-trim |
| `BTRFS_LOG_OUTPUT` | `"journal"` | logs via `systemd-cat -t btrfs-scrub` so runs are identifiable, instead of bare stdout |

## How the schedule is actually created

`btrfsmaintenance-refresh.path` watches `/etc/sysconfig/btrfsmaintenance` and runs
`btrfsmaintenance-refresh-cron.sh systemd-timer`, which per job calls
`refresh_timer(<period>, <job>)`:

- any period other than `none` → writes
  `/etc/systemd/system/btrfs-<job>.timer.d/schedule.conf` containing
  `OnCalendar=<period>`, then `systemctl enable` + `start` the timer.
- `none`/`uninstall` → `systemctl stop` + `disable` + `rm -rf` that drop-in. This is
the supported way to switch a job off. Note the shipped timer units already carry
`OnCalendar=monthly`, so a job you never disable still runs.

In a container build the script's internal `systemctl` calls are silenced, therefore:

1. run the refresh **once at build time** —
   `/usr/share/btrfsmaintenance/btrfsmaintenance-refresh-cron.sh systemd-timer` — to
   bake `schedule.conf` into the image so first boot is deterministic;
2. still enable explicitly through the guarded wrapper:
   `enable_unit btrfs-scrub.timer` and `enable_unit btrfsmaintenance-refresh.path`;
3. explicitly `systemctl disable btrfs-balance.timer btrfs-trim.timer
   btrfs-defrag.timer` as belt-and-braces in case a future preset enables them (the
   `none` periods already handle it).

## Post-deploy verification

- `systemctl list-timers 'btrfs*'` → scrub present with a next elapse; balance/trim/
  defrag absent.
- `systemctl cat btrfs-scrub.timer` → shows the generated `schedule.conf` drop-in.
- The end-to-end proof the mountpoint resolution is right: run
  `/usr/share/btrfsmaintenance/btrfs-scrub.sh` by hand once and confirm it logs
  `Running scrub on <btrfs path>` and **not** `... is not btrfs, skipping`. Then
  `journalctl -u btrfs-scrub.service` (service) and `btrfs scrub status /var`.
- Host measurement for costing the period: 284 GiB verified in 1 min 36 s
  (~2.96 GiB/s) on the OM3PGP41024P-A0.
