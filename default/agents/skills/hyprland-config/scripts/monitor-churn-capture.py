# Timestamped capture for "one screen sleeps and another wakes" churn on Hyprland/Omarchy.
#
# Read-only: sysfs reads, one hyprctl call per heartbeat, udevadm monitor. It dispatches nothing,
# so it is safe to leave running while the user reproduces the trigger, and safe to kill anywhere.
#
#   CAPTURE_SECONDS=1800 python3 monitor-churn-capture.py          (background it, then wait)
#
# Run it, have the user reproduce, then read the log top to bottom: the ORDER of the lines is the
# evidence. A STATE/CHURN pair on one connector right after a DPMS transition means the blank is
# generating the link drop; drops with no DPMS transition anywhere near them are link/hardware-side.
# A run of heartbeats with unchanged counters proves the churn was dormant in that window - say that
# instead of implying the storm was ongoing.

import glob, json, os, re, subprocess, sys, threading, time
from datetime import datetime

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
OUT = os.path.join(os.environ.get("BH_AGENT_WORKSPACE", RUNTIME), "monitor-churn-capture.log")
DURATION = int(os.environ.get("CAPTURE_SECONDS", "1800"))


def ts():
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S%z")


def hypr_log():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    cands = ([f"{RUNTIME}/hypr/{sig}/hyprland.log"] if sig else []) + \
            sorted(glob.glob(f"{RUNTIME}/hypr/*/hyprland.log"))
    for p in cands:
        if os.path.exists(p):
            return p
    sys.exit("no hyprland.log found - is the compositor running? set HYPRLAND_INSTANCE_SIGNATURE")


def connectors():
    """Every real DRM connector: /sys/class/drm/card<N>-<NAME> with a status file."""
    found = []
    for path in sorted(glob.glob("/sys/class/drm/card*-*")):
        name = os.path.basename(path).split("-", 1)[1]
        if "Writeback" in name or not os.path.exists(f"{path}/status"):
            continue
        found.append((name, path))
    return found


CONNS = connectors()
LOG = hypr_log()


# connector_id maps each connector to the 'Connector NNNN' numbers in hyprland.log.
def cid(path):
    try:
        return open(f"{path}/connector_id").read().strip()
    except OSError:
        return "?"


IDS = {name: cid(path) for name, path in CONNS}
PATTERNS = {
    "hotplug": r"Got a hotplug event",
    "modeset": r"Modesetting HDMI",
    "disabling_output": r"Disabling output",
    "released_crtc": r"released crtc",
    "pageflip_err": r"Cannot commit when a page-flip is awaiting",
}
PATTERNS.update({f"disc_{n}": rf"Connector {i} connection state: 2" for n, i in IDS.items()})


def log(line):
    with open(OUT, "a") as fh:
        fh.write(line + "\n")
        fh.flush()


def state():
    out = {}
    for name, path in CONNS:
        def rd(f):
            try:
                return open(f"{path}/{f}").read().strip()
            except OSError:
                return "?"
        out[name] = (rd("status"), rd("dpms"), rd("enabled"))
    return out


def counters():
    try:
        text = open(LOG, errors="replace").read()
    except OSError:
        return {k: -1 for k in PATTERNS}
    return {k: len(re.findall(p, text)) for k, p in PATTERNS.items()}


def dpms_now():
    """Hyprland's own per-output dpmsStatus, parsed as JSON (do not regex the -j output)."""
    try:
        mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"],
                                         capture_output=True, text=True).stdout)
        return {m["name"]: m["dpmsStatus"] for m in mons}
    except Exception:
        return {}


def udev_watcher():
    p = subprocess.Popen(["udevadm", "monitor", "--subsystem-match=drm", "--property"],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    rec = []
    for raw in p.stdout:
        line = raw.rstrip("\n")
        if line:
            rec.append(line)
            continue
        keep = [l for l in rec if l.startswith(("UDEV", "KERNEL", "ACTION", "DEVLINKS"))
                or "HOTPLUG" in l or "CONNECTOR" in l]
        keep = [l for l in keep if " - the " not in l]  # drop udevadm's own help banner
        if keep:
            log(f"{ts()} udev " + " | ".join(keep))
        rec = []


def main():
    open(OUT, "w").close()
    log(f"{ts()} start log={LOG} duration={DURATION}s connector_ids={IDS}")
    threading.Thread(target=udev_watcher, daemon=True).start()
    prev_state, prev_counts, last_hb = state(), counters(), time.time()
    log(f"{ts()} baseline state={prev_state} counters={prev_counts} "
        f"logsize={os.path.getsize(LOG)}")
    end = time.time() + DURATION
    while time.time() < end:
        time.sleep(1)
        st = state()
        if st != prev_state:
            for name in st:
                if st[name] != prev_state[name]:
                    log(f"{ts()} STATE {name}: status {prev_state[name][0]}->{st[name][0]} "
                        f"dpms {prev_state[name][1]}->{st[name][1]} "
                        f"enabled {prev_state[name][2]}->{st[name][2]}")
            prev_state = st
        ct = counters()
        if ct != prev_counts:
            moved = {k: ct[k] - prev_counts.get(k, ct[k]) for k in ct if ct[k] != prev_counts.get(k, ct[k])}
            log(f"{ts()} CHURN {moved}")
            prev_counts = ct
        if time.time() - last_hb > 30:
            log(f"{ts()} heartbeat dpms={dpms_now()} counters={ct} "
                f"logsize={os.path.getsize(LOG)}")
            last_hb = time.time()
    log(f"{ts()} end")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log(f"{ts()} interrupted")
