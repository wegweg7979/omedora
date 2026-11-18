#!/usr/bin/env bash
# LAN chatter census: capture broadcast/multicast + ARP on the wifi interface and
# summarise it. Answers "what is actually making noise on my network?"
#
# Run with sudo — tcpdump on these images has NO file capabilities, so a non-root
# capture fails with a permission error.
#
#   sudo bash lan-chatter-census.sh [seconds] [pcap-path]
#
# Deliberately filtered to broadcast/multicast/ARP: over wifi in managed mode the AP
# never forwards other clients' unicast to us anyway, so nothing useful is lost and
# no household unicast lands in the file.
#
# PITFALLS baked in (both cost a confusing failure once):
#   - NEVER hardcode the interface. workstation is `wlp4s0`, mini is `wlp0s20f3`.
#   - Never send tcpdump's stderr to /dev/null. That hid "no such device" and the
#     only symptom was a later `chown: cannot access ... No such file or directory`.

set -uo pipefail

SECS=${1:-75}
OUT=${2:-/var/home/user/wifi-census.pcap}
IF=$(ls /sys/class/net 2>/dev/null | grep -m1 ^wl || true)

[ -n "$IF" ] || { echo "ERROR: no wireless interface found in /sys/class/net"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "ERROR: run with sudo (tcpdump needs root on this image)"; exit 1; }

echo "capturing on $IF for ${SECS}s -> $OUT"
timeout "$SECS" tcpdump -i "$IF" -nn -s 0 -U -w "$OUT" ether broadcast or ether multicast or arp
rc=$?
[ -s "$OUT" ] || { echo "ERROR: NO CAPTURE (tcpdump exit $rc)"; exit 1; }

TARGET=${SUDO_USER:-user}
chown "$TARGET:$TARGET" "$OUT" 2>/dev/null || true
ls -lh --time-style=full-iso "$OUT"

echo
echo "=== volume + duration ==="
tcpdump -r "$OUT" -nn -tt -q 2>/dev/null \
  | awk 'NR==1{f=$1} {n++} END{printf "packets=%d   span=%.0fs   rate=%.1f pkt/s\n", n, $1-f, n/(($1-f)>0?($1-f):1)}'

echo
echo "=== protocol breakdown (packet counts) ==="
while IFS='|' read -r label filt; do
  n=$(tcpdump -r "$OUT" -nn $filt 2>/dev/null | wc -l)
  printf "%-30s %6d\n" "$label" "$n"
done <<'FILTERS'
ARP|arp
IPv6 neighbour disc|icmp6
mDNS / Bonjour|udp port 5353
SSDP / UPnP|udp port 1900
DHCP|udp port 67 or udp port 68
WS-Discovery|udp port 3702
NetBIOS|udp port 137 or udp port 138
FILTERS

echo
echo "=== top SOURCE MACs (who is talking) ==="
tcpdump -r "$OUT" -nn -e -q 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -rn | head -12

echo
echo "=== top DESTINATION MACs (ff:ff:ff:ff:ff:ff = broadcast; 33:33/01:00:5e = IPv6/v4 multicast) ==="
tcpdump -r "$OUT" -nn -e -q 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn | head -8

echo
echo "=== mDNS names + service types (dotted runs are binary-payload parse artifacts) ==="
tcpdump -r "$OUT" -nn -A 'udp port 5353' 2>/dev/null | grep -aoE '_[a-z0-9-]+\._(tcp|udp)' | sort | uniq -c | sort -rn | head -15
tcpdump -r "$OUT" -nn -A 'udp port 5353' 2>/dev/null | grep -aoE '[A-Za-z0-9_ -]{3,}\.local' | sort | uniq -c | sort -rn | head -15

echo
echo "=== ARP sample (IP claims) ==="
tcpdump -r "$OUT" -nn arp 2>/dev/null | tail -12
