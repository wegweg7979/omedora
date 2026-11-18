#!/usr/bin/env bash
# Read-only disk / filesystem health probe for workstation.
#
# Run as root (it is the ONLY part of the health check that needs root):
#     sudo bash ~/.hermes/skills/machine-health-check/scripts/smart-report.sh
#
# Writes a report to the agent's scratch dir and hands ownership back to `user`
# so the agent can read it with read_file. Starts no scrub, changes no state.
set -uo pipefail

NVME="${1:-/dev/nvme0}"
BTRFS_MOUNT="${2:-/var}"
OUT="${OUT:-/var/home/user/.hermes/cache/scratch/smart-report.txt}"

mkdir -p "$(dirname "$OUT")"

{
  echo "### nvme-cli smart-log ($NVME)"
  nvme smart-log "$NVME" 2>&1
  echo
  echo "### smartctl -a"
  smartctl -a -d nvme "$NVME" 2>&1
  echo
  echo "### smartctl error log"
  smartctl -l error -d nvme "$NVME" 2>&1
  echo
  echo "### btrfs device stats ($BTRFS_MOUNT)"
  btrfs device stats "$BTRFS_MOUNT" 2>&1
  echo
  echo "### btrfs scrub status (last run only - does not start one)"
  btrfs scrub status "$BTRFS_MOUNT" 2>&1
  echo
  echo "### btrfs filesystem usage"
  btrfs filesystem usage "$BTRFS_MOUNT" 2>&1
} > "$OUT" 2>&1

chown user:user "$OUT" 2>/dev/null || true
echo "wrote $OUT"
