# LAN chatter census (is my network noisy?)

Records what is broadcasting on the LAN. Procedure lives in
`scripts/lan-chatter-census.sh` — run it **with sudo** on the host that is on wifi
(`tcpdump` has no file capabilities on these images, so a non-root capture fails):

```bash
sudo bash ~/.hermes/skills/machine-health-check/scripts/lan-chatter-census.sh 75
```

It captures **broadcast/multicast + ARP only** for 75 s, chowns the pcap back, then
prints volume, per-protocol counts, top source/destination MACs, the mDNS service
census and an ARP sample. Chowns back so the agent can re-analyse the pcap
unprivileged with further `tcpdump -r` passes.

**Two mistakes that cost a confusing failure — both now handled in the script:**

- **Never hardcode the wifi interface.** `workstation` is `wlp4s0`, `mini` is
  `wlp0s20f3`. Auto-detect with `ls /sys/class/net | grep -m1 ^wl`.
- **Never `2>/dev/null` tcpdump's stderr.** That swallowed "no such device" and the
  only visible symptom was `chown: cannot access '...pcap': No such file or directory`,
  which reads like a permissions bug and is actually a wrong-host/wrong-interface bug.

## Baseline — workstation, 2026-11-10 (healthy, quiet)

75 s on `hurunagus` 5 GHz, 104 packets, **1.4 pkt/s**:

| protocol | packets |
|---|---|
| mDNS / Bonjour (5353) | 27 |
| SSDP / UPnP (1900) | 23 |
| IPv6 neighbour discovery (icmp6) | 14 |
| ARP | 13 |
| DHCP / WS-Discovery / NetBIOS | 0 |

Top senders: **the router `30:de:4b:62:b7:00` (<lan-ip>) at 48 %**, then
**workstation itself at 27 %** (its own mDNS/MLD announcements — this host is a notable
contributor), then a mesh/repeater cluster (`ec:a9:07:…`, `04:99:b9:…`), the MacBook
(`34:36:3b:…`) and **four `d8:a0:11:…` smart-home devices**.

Service types seen: `_matter._tcp`, `_hap._udp`/`_hap._tcp` (HomeKit/Matter),
`_companion-link._tcp` + `_rdlink._tcp` (Apple Continuity; an `iPad` advertises
Companion Link), `_raop._tcp` (AirPlay audio, e.g. "Kiva Room"). Destination MACs are
almost all IPv6 multicast (`33:33:…`) plus IPv4 mDNS (`01:00:5e:00:00:fb`); only 10
packets were true broadcast.

**Read:** ~1–2 pkt/s of mDNS+SSDP+MLD+ARP is normal for a house with Apple gear and
HomeKit/Matter devices, and it is **not** a source of congestion — the router relaying
multicast and MLD is expected to be the top talker. If wifi is slow, this rules the
LAN chatter out and points back at RF: channel overlap (their 2.4 GHz leg sits on
**ch 11, co-channel with `VM7074731` + its extender**; `SKYXZ4IA` owns ch 6, so ch 1 is
the free one) and power save.

## Channel plan (their TP-Link, 2026-11)

`hurunagus` is the user's own TP-Link (AP BSSID `72:de:4b:62:b6:ff` shares the router's
OUI `30:de:4b:…`). `VM7074731` / `VM7074731_EXT` is a **neighbour's** Virgin Media gear —
not theirs, so the only remedy is moving.

- **5 GHz is on ch 100 — a DFS channel** (`5500.0 MHz [100] … (no IR, radar detection)`;
  `iw reg get` = `country GB: DFS-ETSI`). If the AP hears radar it must vacate, dropping
  every 5 GHz client for minutes — and workstation, the MacBook and mini are *all* on
  5 GHz. Non-DFS options: **36/40/44/48** (UNII-1) and 149+. **Moving 5 GHz is zero risk
  to the smart devices, because WiZ lighting is 2.4 GHz only.** Recommend this first.
- **2.4 GHz sits on ch 11, which in 2026-11 carried FOUR networks** — theirs, `VM7074731`,
  `VM7074731_EXT`, and `SKYG82DB` (a third party that appeared between two scans).
  ch 6 = `SKYXZ4IA`; **ch 1 measured empty**. So ch 11 → 1 is the 2.4 fix, at 20 MHz width.
- **`SKYG82DB` is dual-band** — ch 11 (`50:70:43:39:B7:EA`) *and* ch 36
  (`50:70:43:39:B7:ED`), so its 5 GHz radio already occupies 36. If the 5 GHz move happens,
  prefer **40/44/48** over 36.
- **Verifying a channel change from the client side:** `nmcli dev wifi list` can serve
  NetworkManager's *cached* BSS list, so force a fresh one (`nmcli dev wifi rescan`, wait
  ~10 s, re-list) and check the AP's 2.4 BSSID `7A:DE:4B:62:B6:F8` reports the new channel.
  Two independent forced scans on 2026-11-10 still showed ch 11 with **nothing at all on
  ch 1** — a 2.4 change the user believed he had applied had not applied (both radios
  unchanged: 2.4 = 11, 5 = 100). Likely causes, in order: the band left on **Auto** so the
  router re-picked 11 itself; a value edited but never Applied/Saved; the wrong band or a
  guest SSID edited; or a mesh node other than the one serving `hurunagus`. Also: **signal
  readings from a scan taken while associated are unreliable** — `VM7074731_EXT` read
  29 dBm and 74 dBm seconds apart. Trust the channel numbers, not the signal deltas.
- **Outcome (2026-11-10):** he re-applied and it took. The 2.4 BSSID
  `7A:DE:4B:62:B6:F8` moved to **ch 1 with the BSSID unchanged**, leaving ch 1 to
  `hurunagus` alone while `SKYG82DB` (54), `VM7074731` (64) and `VM7074731_EXT` (74) all
  pile onto ch 11, and `SKYXZ4IA` keeps ch 6. **Nothing needed re-pairing.** A repeatable
  root-free proof that the IoT gear came back: their live mDNS/Matter replies still
  arrive (`_matter._tcp` records under fabric `1BD5CD80881D7FCD-…`) — WiZ gear is
  2.4-only and receiving it requires being *associated*, not merely powered on.
  **Corrections, both verified 2026-11-10.** (1) A `TP-Link_Guest_B700_5G` BSSID seen in
  one scan round was a **transient beacon** while the AP re-applied the channel change —
  the guest network is genuinely disabled and the SSID is absent from later forced scans.
  Do not infer router config from a single scan taken right after a wireless change.
  (2) **Do NOT recommend moving 5 GHz off ch 100.** Every host that is up reports
  **zero** radar/CSA/channel-switch lines, and he reports no DFS disconnects at this
  address — at his *previous* address, a few miles away, the same router dropped
  constantly at high channel widths. DFS is geographic radar exposure, and 80/160 MHz
  bonds reach into DFS sub-channels by construction, which is why "high MHz" was the
  trigger there and 40 MHz is fine here. Staying on 100 is arguably better anyway: UNII-1
  (36–48) is the consumer default and `SKYG82DB` already occupies 36.
- **Disconnect reasons are the DFS tell.** `reason=3`/`reason=8` are clean *leaving*
  deauths (suspend/resume, NM reconfig, reboot), whereas a radar event shows as beacon
  loss plus a driver CSA/channel-switch line. workstation carries 156
  `CTRL-EVENT-DISCONNECTED` lines in its journal with **zero** CSA lines — i.e. not DFS.
  Always pair a disconnect count with its reasons before calling it interference.
- **Host roles for latency controls:** `desktop` is on **wired Ethernet**
  (`iw dev … link` → down), which is why it measures ~1.2 ms. Do not use it as a
  "same wifi" control when comparing wifi latency — use the MacBook or mini.
- **A channel change does NOT require re-provisioning bulbs.** WiFi clients store SSID +
  password + security, never the channel; they rescan and rejoin. What *would* force the
  painful re-pair: changing the **SSID**, the **password**, or the **security mode**
  (keep plain WPA2 — many WiZ bulbs are 2.4-only b/g/n and choke on WPA3 or
  WPA2/WPA3-mixed), disabling 2.4 GHz or legacy/802.11b rates, or toggling AP/client
  isolation. Bulbs usually rejoin in under a minute; a stubborn one needs a power cycle,
  not a re-pair.
- **Before/after verification:** re-run the census and diff the MAC list. Known WiZ
  (mains-powered, always visible): `d8:a0:11:50:88:78`, `d8:a0:11:4e:11:58`,
  `d8:a0:11:50:9f:44`, `d8:a0:11:4e:27:8c`, `44:4f:8e:8c:3f:d4`. **Battery devices sleep
  and will not appear in a 75 s window** — the census can only prove the mains-powered
  ones came back.

## Limits

- Wi-fi in managed mode sees **broadcast/multicast plus this host's own traffic only** —
the AP never forwards other clients' unicast, so a busy neighbour is invisible here.
- `iw dev <dev> survey dump` returns **nothing** on the AX210 and `/proc/net/wireless`
reports `noise -256` ("not reported"), so **RF noise floor is not measurable** on this
hardware — interference has to be inferred from channel overlap and retry/drop counters.
- The mDNS name grep over `-A` output also matches binary payload bytes, so dotted runs
like `............._rdlink._tcp.local` are parse artifacts, not hostnames. Only trust
clean names (`iPad._companion-link._tcp.local`, `PTR fedora.local`).
