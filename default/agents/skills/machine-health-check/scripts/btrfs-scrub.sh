#!/usr/bin/env bash
# Btrfs scrub with progress + post-check report (workstation).
#
# Run as root:
#     sudo bash ~/.hermes/skills/machine-health-check/scripts/btrfs-scrub.sh [mount]
#
# Deliberately does NOT run `btrfs check` (corrupting on a mounted fs) or
# `btrfs balance` (unnecessary on this allocation). Read-only pass; safe on a live
# filesystem, cancellable with `sudo btrfs scrub cancel <mnt>`.
set -uo pipefail

MOUNT="${1:-/var}"
OUT="${OUT:-/var/home/user/.hermes/cache/scratch/btrfs-scrub.txt}"
TIMEOUT="${SCRUB_TIMEOUT:-7200}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

log()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT"; }
emit() { "$@" 2>&1 | sed 's/^/    /' | tee -a "$OUT"; }
# Root can read /var/lib/btrfs/scrub.status.<fsid>; non-root cannot (root:root 0600).
st()         { btrfs scrub status "$MOUNT" 2>&1; }
is_running() { st | grep -Eq "Status:[[:space:]]*running"; }
is_done()    { st | grep -Eq "Status:[[:space:]]*finished"; }

log "btrfs scrub on $MOUNT - $(btrfs --version 2>&1 | head -1)"
log "usage before scrub:"; emit btrfs filesystem usage -h "$MOUNT"

if is_running; then
  log "a scrub is already running - attaching instead of starting another"
else
  log "starting read-only scrub (metadata repairable from its DUP copy; data is single = detect only)"
  # Background it explicitly: `scrub start` can block for the whole scrub in some
  # btrfs-progs builds, which would stall this script and log no progress at all.
  ( btrfs scrub start "$MOUNT" >>"$OUT" 2>&1 ) &
  sleep 3
fi

deadline=$(( $(date +%s) + TIMEOUT ))
while ! is_done; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "TIMEOUT after ${TIMEOUT}s and the scrub is still running - NOT cancelled; check: btrfs scrub status $MOUNT"
    break
  fi
  sleep 15
  is_running && log "running: $(st | grep -E 'Status:|Rate:|Time left:|ETA:' | tr -s ' ' | tr '\n' ' ')"
done

# The kernel's own line is authoritative: "scrub: finished on devid 1 with status: 0"
# (status 0 = no errors found and nothing uncorrected).
log "kernel log outcome:"; emit bash -c "journalctl -k --no-pager | grep -F 'scrub:' | tail -4"
log "final status:"; emit btrfs scrub status "$MOUNT"
log "device stats after scrub (all five counters must read 0):"; emit btrfs device stats "$MOUNT"
log "usage after scrub:"; emit btrfs filesystem usage -h "$MOUNT"

chown user:user "$OUT" 2>/dev/null || true
log "report written to $OUT"
