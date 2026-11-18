#!/usr/bin/env python3
"""workstation (Minisforum NAB9) hardware-health watch.

Samples package/core temps, fan RPM, PROCHOT/throttle counters, Super-IO rails,
RAPL power and new kernel hardware errors once per tick; appends a CSV row and
prints ALERT lines on stdout ONLY when something crosses a threshold (empty
stdout => nothing is delivered). Alerts are keyed by category and re-printed at
most once per REALERT_MIN minutes, so a hot soak does not spam.

Unprivileged and read-only: no sudo, no writes outside ~/.hermes/state/hw-watch/.

Run:   python3 ~/.hermes/scripts/hw-watch.py
Test:  HW_WATCH_FORCE_ALERT=1 python3 ~/.hermes/scripts/hw-watch.py
"""

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

STATE = Path.home() / ".hermes/state/hw-watch"
CSV = STATE / "hw.csv"
ALERTS = STATE / "alerts.json"
LOG = STATE / "hw-watch.log"

REALERT_MIN = 60.0        # re-print a still-active alert after this many minutes
BASELINE_N = 96           # ticks of history used as the rail/thermal baseline (~8h)
RAIL_JUMP_PCT = 8.0       # % deviation from baseline for rails above 0.5 V
RAIL_JUMP_PCT_SMALL = 20.0
NOISY_SPREAD_PCT = 25.0   # a channel swinging this much inside its OWN baseline is
                          # floating/unconnected — never alert on it
PKG_ALERT_C = 92.0
CORE_ALERT_C = 96.0
SSD_ALERT_C = 70.0
IDLE_LOAD = 2.0
PKG_IDLE_C = 80.0

HW_PATTERN = (r"machine check|MCE|hardware error|AER:|PCIe Bus Error|I/O error|"
              r"nvme.*(error|reset|timeout)|thermal.*critical|"
              r"Core temperature above threshold|Package temperature above threshold")

# A clean shutdown on this host always leaves systemd's teardown as the final
# journal lines; an abrupt cut leaves whatever routine message was in flight.
CLEAN_END = re.compile(r"Unmounting|Unmounted|Stopping|Stopped|Reached target|Deactivated|"
                       r"systemd-shutdown|Shutting down|System is|Finalizing")
ONCE_KEYS = ("unclean_boot:",)


def previous_boot(prev_index=1):
    """(unclean?, last_line, timestamp) for the previous boot on this host."""
    try:
        out = subprocess.run(
            ["journalctl", "-b", f"-{prev_index}", "-n", "4", "-o", "short-iso", "--no-pager"],
            capture_output=True, text=True, timeout=30).stdout.strip().splitlines()
    except Exception as e:
        return None, f"could not read the previous boot: {e}", ""
    if not out:
        return None, "no previous boot in the journal", ""
    last = out[-1]
    stamp = last.split(" ", 1)[0] if " " in last else ""
    return (not CLEAN_END.search(last)), last[:170], stamp


def boot_id():
    return read("/proc/sys/kernel/random/boot_id", str, "") or "unknown"


def read(path, cast=float, default=None):
    try:
        with open(path) as fh:
            return cast(fh.read().strip())
    except Exception:
        return default


def hwmon_by_name(name):
    for d in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        if read(d / "name", str) == name:
            return d
    return None


def pkg_thermal_zone():
    for d in sorted(Path("/sys/class/thermal").glob("thermal_zone*")):
        if "x86_pkg_temp" in (read(d / "type", str) or ""):
            return d
    return None


def rapl_watts(interval=0.25):
    p = Path("/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj")
    a = read(p)
    if a is None:
        return None
    time.sleep(interval)
    b = read(p)
    if b is None or b < a:
        return None
    return round((b - a) / (interval * 1_000_000), 1)


def journal_hw_errors(since_min=6):
    try:
        out = subprocess.run(["journalctl", "-k", "--since", f"-{since_min}min", "--no-pager"],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    hits = []
    for ln in out.splitlines():
        m = re.search(HW_PATTERN, ln, re.I)
        if m:
            hits.append(ln.split(" ", 4)[-1][:160])
    return hits[:8]


def csv_history():
    if not CSV.exists():
        return []
    with open(CSV) as fh:
        lines = [ln for ln in fh.read().splitlines() if ln.strip()]
    if len(lines) < 2:
        return []
    hdr = lines[0].split(",")
    hist = []
    for ln in lines[1:]:
        parts = ln.split(",")
        if len(parts) == len(hdr):
            hist.append(dict(zip(hdr, parts)))
    return hist


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).astimezone()
    ts = now.isoformat(timespec="seconds")

    coretemp, nct, nvme, tz = (hwmon_by_name("coretemp"), hwmon_by_name("nct6798"),
                               hwmon_by_name("nvme"), pkg_thermal_zone())

    pkg_c = round(read(tz / "temp", default=0.0) / 1000, 1) if tz else None

    cores = []
    if coretemp:
        for f in sorted(coretemp.glob("temp*_input")):
            lab = read(f.with_name(f.name.replace("_input", "_label")), str) or ""
            v = read(f)
            if v is not None and not lab.lower().startswith("package"):
                cores.append(v / 1000)
    core_max = round(max(cores), 1) if cores else None

    fans, rails = {}, {}
    if nct:
        for f in sorted(nct.glob("fan*_input")):
            v = read(f)
            if v is not None:
                fans["fan_" + f.name.replace("_input", "")] = int(v)
        for f in sorted(nct.glob("in*_input")):
            v = read(f)
            if v is not None:
                rails["rail_" + f.name.replace("_input", "")] = round(v, 4)

    ssd_c = round(read(nvme / "temp1_input", default=0.0) / 1000, 1) if nvme else None
    ssd_alarm = int(read(nvme / "temp1_alarm", default=0) or 0) if nvme else 0

    thr_pkg = int(read("/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count", default=0) or 0)
    thr_core = int(read("/sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count", default=0) or 0)
    try:
        load1 = float(read("/proc/loadavg", str, "0").split()[0])
    except Exception:
        load1 = None
    freq = read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", int)
    watts = rapl_watts()
    tainted = read("/proc/sys/kernel/tainted", int, 0)
    pl1_uw = read("/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw", int)
    pl2_uw = read("/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw", int)
    max_perf = read("/sys/devices/system/cpu/intel_pstate/max_perf_pct", int)

    row = {"ts": ts, "pkg_c": pkg_c, "core_max_c": core_max, "ssd_c": ssd_c,
           "ssd_alarm": ssd_alarm, "thr_pkg": thr_pkg, "thr_core": thr_core,
           "load1": load1, "freq_mhz": (freq // 1000 if freq else None),
           "rapl_w": watts, "pl1_w": (round(pl1_uw / 1e6, 1) if pl1_uw else None),
           "pl2_w": (round(pl2_uw / 1e6, 1) if pl2_uw else None),
           "pstate_max_pct": max_perf, "tainted": tainted}
    row.update(fans)
    row.update(rails)

    hist = csv_history()
    base = hist[-BASELINE_N:]
    prev = hist[-1] if hist else None

    def col(name):
        vals = []
        for r in base:
            try:
                vals.append(float(r.get(name)))
            except (TypeError, ValueError):
                pass
        return vals

    # ---- checks: list of (stable_key, message) ----
    found = []
    if pkg_c is not None and pkg_c >= PKG_ALERT_C:
        found.append(("pkg_temp", f"package {pkg_c}C >= {PKG_ALERT_C}C"))
    if core_max is not None and core_max >= CORE_ALERT_C:
        found.append(("core_temp", f"hottest core {core_max}C >= {CORE_ALERT_C}C"))
    if ssd_c is not None and ssd_c >= SSD_ALERT_C:
        found.append(("ssd_temp", f"NVMe composite {ssd_c}C >= {SSD_ALERT_C}C"))
    if ssd_alarm:
        found.append(("ssd_alarm", "NVMe temperature alarm asserted"))

    if prev and pl1_uw:
        try:
            prev_pl1 = float(prev.get("pl1_w") or 0)
        except (TypeError, ValueError):
            prev_pl1 = 0.0
        if prev_pl1 and abs(pl1_uw / 1e6 - prev_pl1) / prev_pl1 > 0.10:
            found.append(("pl_change",
                          f"CPU long-term power limit changed: {prev_pl1:.0f}W -> "
                          f"{pl1_uw / 1e6:.0f}W (was this you, or the EC/firmware clamping?)"))

    if prev:
        try:
            d_core = thr_core - int(prev.get("thr_core") or 0)
            d_pkg = thr_pkg - int(prev.get("thr_pkg") or 0)
        except ValueError:
            d_core = d_pkg = 0
        if d_core > 0:
            found.append(("thr_core", f"{d_core} new core-thermal-throttle event(s)"))
        if d_pkg > 0 and (load1 is None or load1 < IDLE_LOAD) and (pkg_c or 0) < PKG_IDLE_C:
            found.append(("thr_pkg_idle",
                          f"{d_pkg} new package PROCHOT event(s) while idle "
                          f"(load {load1}, pkg {pkg_c}C) - board/VRM-side PROCHOT, not CPU temp"))
        if fans.get("fan_fan2") == 0 and (pkg_c or 0) > 65:
            found.append(("fan_stall", f"fan2 stalled at 0 RPM with package at {pkg_c}C"))

    noisy = []
    for k, v in rails.items():
        vals = col(k)
        if len(vals) < 6:
            continue
        mean = sum(vals) / len(vals)
        if mean <= 0.05:
            continue
        # A real rail is stable across its own baseline; an unconnected/floating Super-IO
        # input wanders (in0 here swings between ~344 and ~664 mV). Judge stability first,
        # so a chronic wanderer is never reported as "drift" — while a rail that steps away
        # from a previously tight baseline still alerts, because that baseline is tight.
        spread = (max(vals) - min(vals)) / mean * 100
        if spread >= NOISY_SPREAD_PCT:
            noisy.append(f"{k.replace('rail_', '')} (swings {spread:.0f}%)")
            continue
        lim = RAIL_JUMP_PCT if mean > 0.5 else RAIL_JUMP_PCT_SMALL
        if abs(v - mean) / mean * 100 >= lim:
            found.append((f"rail_{k}",
                          f"{k.replace('rail_', '')} {v:.3f}V is "
                          f"{abs(v - mean) / mean * 100:.0f}% off its baseline "
                          f"({mean:.3f}V) - rail drift"))

    for msg in journal_hw_errors():
        found.append((f"journal_{msg[:60]}", "kernel: " + msg))

    unclean, last_line, stamp = previous_boot()
    if unclean:
        found.append((f"unclean_boot:{boot_id()}",
                      f"previous boot ended with NO shutdown sequence ({stamp}): "
                      f"{last_line!r} — hard power cut or hardware fault, not a clean reboot"))

    if os.environ.get("HW_WATCH_FORCE_ALERT"):
        found.append(("test", "TEST ALERT (forced) - delivery path check"))

    # ---- persist sample ----
    header = list(row.keys())
    if CSV.exists() and _header(CSV) != header:
        try:
            CSV.rename(CSV.with_suffix(".csv.old"))
        except Exception:
            pass
    if not CSV.exists():
        with open(CSV, "w") as fh:
            fh.write(",".join(header) + "\n")
    with open(CSV, "a") as fh:
        fh.write(",".join("" if row[k] is None else str(row[k]) for k in header) + "\n")

    # ---- dedupe by key, re-print stale ones, report clears once ----
    state = {"seen": {}, "printed": {}}
    if ALERTS.exists():
        try:
            loaded = json.loads(ALERTS.read_text())
            state = {"seen": loaded.get("seen", {}), "printed": loaded.get("printed", {})}
        except Exception:
            pass

    keys_now = [k for k, _ in found]
    out_lines = []
    for k, msg in found:
        if k not in state["seen"] or (time.time() - state["printed"].get(k, 0)) > REALERT_MIN * 60:
            out_lines.append(msg)
            # a once-only key (an unclean boot is a past event, not a live condition)
            # must never re-print, even though the condition stays true all boot
            state["printed"][k] = (time.time() + 10 ** 9 if k.startswith(ONCE_KEYS)
                                   else time.time())
        state["seen"][k] = time.time()
    cleared = []
    for k in list(state["seen"]):
        if k not in keys_now:
            state["seen"].pop(k, None)
            state["printed"].pop(k, None)
            cleared.append(k.replace("rail_", "").replace("_", " "))
    ALERTS.write_text(json.dumps(state, indent=1))

    with open(LOG, "a") as fh:
        fh.write(f"{ts} pkg={pkg_c} core_max={core_max} ssd={ssd_c} thr_pkg={thr_pkg} "
                 f"thr_core={thr_core} load={load1} w={watts} rails={len(rails)} "
                 f"alerts={len(found)} noisy={'|'.join(noisy)}\n")

    if out_lines or cleared:
        print(f"HARDWARE WATCH - workstation (NAB9) - {now.strftime('%a %d %b %H:%M')}")
        for m in out_lines:
            print(f"  ! {m}")
        if cleared:
            print("  ok now: " + ", ".join(cleared))
        if noisy:
            print("  not alerting on (floating/unnamed channel, logged only): "
                  + ", ".join(noisy))
        print(f"  state: pkg {pkg_c}C, hottest core {core_max}C, SSD {ssd_c}C, "
              f"fan {fans.get('fan_fan2', '?')} RPM, load {load1}, {watts}W, "
              f"throttle pkg/core {thr_pkg}/{thr_core} (CSV: {CSV})")
    return 0


def _header(path):
    try:
        with open(path) as fh:
            return fh.readline().strip().split(",")
    except Exception:
        return []


if __name__ == "__main__":
    sys.exit(main())
