#!/usr/bin/env python3
"""Count Hyprland socket2 events for N seconds, splitting out one prefix.

usage: hypr-ipc-watch.py [seconds] [prefix]

The compositor pushes every event onto `$XDG_RUNTIME_DIR/hypr/<sig>/.socket2.sock`.
Counting them is how you prove state that has no other visible trace:

  # is a daemon that injects a Lua watcher (hyprglaze and friends) still installed?
  hypr-ipc-watch.py 6 hg:        # nonzero with the daemon STOPPED = watcher still there
  hypr-ipc-watch.py 6            # any events at all = something is pushing state

A watcher of this kind is only removed when the Lua state is recreated, so
`hyprctl reload` is the cleanup, and a reloaded compositor shows 0 afterwards.

Run it from a shell that has HYPRLAND_INSTANCE_SIGNATURE/XDG_RUNTIME_DIR set, or
let it find the newest instance directory itself (it does).
"""
import os
import socket
import sys
import time

base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "hypr")
if not os.path.isdir(base):
    sys.exit("no Hyprland instance dir at %s" % base)
cands = [d for d in os.listdir(base) if os.path.exists(os.path.join(base, d, ".socket2.sock"))]
if not cands:
    sys.exit("no .socket2.sock under %s" % base)
sig = sorted(cands, key=lambda d: os.path.getmtime(os.path.join(base, d, ".socket2.sock")))[-1]
path = os.path.join(base, sig, ".socket2.sock")

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
prefix = sys.argv[2] if len(sys.argv) > 2 else ""

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(path)
sock.settimeout(1.0)
end = time.time() + secs
total = matched = 0
kinds = {}
while time.time() < end:
    try:
        data = sock.recv(1 << 16)
    except socket.timeout:
        continue
    if not data:
        break
    for line in data.decode(errors="replace").splitlines():
        if not line.strip():
            continue
        total += 1
        if prefix and prefix in line:
            matched += 1
            kind = line.split(">>", 1)[-1].split(":", 2)
            key = ":".join(kind[:2])
            kinds[key] = kinds.get(key, 0) + 1

print("socket2=%s  window=%.0fs  prefix=%r" % (path, secs, prefix))
print("  events total  %d" % total)
if prefix:
    print("  matching      %d  %s" % (matched, kinds if kinds else ""))
    print("  => %r state is being pushed: %s" % (prefix, "YES" if matched else "no"))
