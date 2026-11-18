#!/usr/bin/env python3
"""Count Hyprland socket2 events for N seconds, grouped by kind.

    hyprland-ipc-events.py <seconds> [substring]

Why this exists: socket2 is push-only, and daemons/plugins that inject a Lua
watcher into the compositor identify themselves by emitting `custom>>…` events
(hyprglaze emits `hg:hb2` heartbeats ~every 2 s plus cursor/geometry pushes).
Counting them is how you prove such a watcher is still INSTALLED after its daemon
died, or GONE after `hyprctl reload` recreated the Lua state — with no pixels and
no guessing. Measured on 0.56.2: daemon dead → 3 events in 6 s; after a reload →
0 in 8 s.

Needs the session environment; run it as:
    eval "$(bash scripts/wayland-env.sh)" && python3 scripts/hyprland-ipc-events.py 8 hg:

Takes the newest signature directory that actually holds `.socket2.sock` (a
`ls -t` over the parent can pick a directory without one).
"""
import os
import socket
import sys
import time

base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"), "hypr")
cands = [d for d in os.listdir(base) if os.path.exists(os.path.join(base, d, ".socket2.sock"))]
if not cands:
    sys.exit("no .socket2.sock under %s — is HYPRLAND_INSTANCE_SIGNATURE/hypr a live session?" % base)
path = os.path.join(base, sorted(cands, key=lambda d: os.path.getmtime(os.path.join(base, d, ".socket2.sock")))[-1], ".socket2.sock")

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
needle = sys.argv[2] if len(sys.argv) > 2 else None

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(path)
sock.settimeout(1.0)
end = time.time() + secs
total = 0
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
        kind = line.split(">>", 1)[-1].split(":", 2)[0:2]
        kinds[":".join(kind)] = kinds.get(":".join(kind), 0) + 1

print("socket2=%s  window=%.0fs" % (path, secs))
print("  events total  %d" % total)
if needle:
    hits = sum(n for k, n in kinds.items() if needle in k)
    print("  matching %-6s %d" % (needle, hits))
for k in sorted(kinds, key=lambda k: -kinds[k])[:10]:
    print("  %-28s %d" % (k, kinds[k]))
if not kinds:
    print("  (nothing — a quiet session, or the watcher is not installed)")
