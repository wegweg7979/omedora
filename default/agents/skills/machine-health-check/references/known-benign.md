# Known-benign log noise on this machine

Everything here has been investigated and is **not** a finding. Match against it
before reporting, so real changes stand out. If one of these *stops* appearing,
that is not a problem either — silence is fine.

## Failed units that are expected

| Unit | Log line | Why it is harmless |
|---|---|---|
| `systemd-remount-fs.service` | `mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure` | `/` is the read-only composefs overlay; `/etc`, `/var`, `/home` are separate mounts, so nothing needs remounting. Fails on every boot of every composefs/bootc image. **Silencing it on a host:** back up `/etc/fstab`, comment out its `/` line (`UUID=… / btrfs subvol=root,…`), run `sudo findmnt --verify`, then `systemctl reset-failed systemd-remount-fs.service`; it stops at the next boot. The line is redundant — the initramfs mounts the root from the kernel cmdline's `rootflags=subvol=root`, and ostree's `sysroot.readonly` makes the rootfs ro. Do NOT mask the unit: the failure is a real signal, just a no-op on this layout. Host-side only — the image still ships the installer's fstab line, so a fresh install reproduces it. |
| `plocate-updatedb.service` | `/var/lib/plocate/: No such file or directory` | Seen once when the image shipped plocate without its state dir; `locate` loses its DB, nothing else. Fixed in later builds — recheck rather than assume. |

## Boot-time kernel noise (ACPI/firmware)

- `ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PC00.TXHC.RHUB.SS0x], AE_NOT_FOUND` — four of them, BIOS table bug on the Venus-series board. Benign.
- `hpet_acpi_probe: no address or irqs in _CRS`, `ENERGY_PERF_BIAS: Set to 'normal', was 'performance'`, `virt/tdx: TDX not supported`, `Bluetooth: hci0: No support for _PRR ACPI method`.
- `resource sanity check ... igen6_edac mapping multiple BARs` — EDAC driver on this platform.
- `spi-nor spi0.0: supply vcc not found, using dummy regulator`, `block nvme0n1: No UUID available providing old NGUID`.
- `systemd-tmpfiles: "/home" already exists and is not a directory` (+ `/srv`, `/root`) — normal for this sysroot layout.
- `SELinux: mount invalid. Same superblock, different security settings for (dev cgroup2...)` — container/virt cgroup mounting; recurring, harmless.
- `kauditd_printk_skb: N callbacks suppressed` — audit ring buffer, informational.
- `kernel.tainted = 512` (`TAINT_UNSIGNED_MODULE`) — expected; the image loads external modules.
- N x `Failed to resolve group '<g>'` from `/usr/lib/udev/rules.d/*-udev-default.rules`
  and `/usr/lib/tmpfiles.d/{var,static-nodes-permissions}.conf` (`disk`, `video`, `lp`,
  `tty`, `kvm`, `render`, `audio`, `utmp`, `sgx`, `clock`) — a boot-ordering race:
  udev/tmpfiles run before `systemd-sysusers` (fed by
  `bootc-sysusers-shadow-sync.service` on bootc) has created the groups, so those
  rules are skipped. **Identical count and distribution on every boot** (52 lines,
  `disk` ×10, `video` ×7, `kvm` ×7, `lp` ×6, `audio` ×5, `utmp` ×4), and every one of
  those groups does exist afterwards (`getent group`) — so permissions are fine. Not
  the plugdev-style one-off it resembles.
- 9 × `SELinux: Permission <p> in class <c> not defined in policy` (`firmware_load`,
  `kexec_image_load`, `kexec_initramfs_load`, `policy_load`, `allowed` in class io,
  `map_create_as` / `prog_load_as` in class bpf) — Fedora's policy simply does not
  define permission bits the kernel advertises; logged at policy load and never
  enforced. Same 9 on every boot, stock or CachyOS kernel.

### Constant, not a finding: i915 DMC warning on EVERY kernel this box has booted

`i915 ... [drm] DMC 1 mmio[0]/0x5f074 incorrect (expected 0x96fc0, current 0x0)` plus
`WARNING: drivers/gpu/drm/i915/display/intel_dmc.c:<NNN> at assert_dmc_loaded` at ~2 s
into boot, **2 occurrences per boot**. Verified identical on all three kernels this
machine has run: `7.2.15-200.fc44` (stock), `7.2.15-300.fc45` (stock) and
`7.3.3-1.cachyos1.fc45` (the CachyOS swap). It is a driver WARNING: the DMC firmware
still finishes loading (`i915/adlp_dmc.bin (v2.20)`), GuC/HuC load and authenticate,
zero GPU hangs or ring resets follow, and the desktop runs on it.

**Do not report a recurrence as a new hardware finding.** An earlier version of this
file claimed the warning was "gone on 7.2.15-300.fc45" — that was a sampling artifact
of a `journalctl -k | grep -iE 'i915|dmc' | tail -10`, which drops the ~2 s warning out
of the window. To decide whether a kernel warning is new, count it **per boot across
several boots** (`journalctl -b N -k | grep -c assert_dmc_loaded` for N = 0, -1, -2)
and identify each boot's kernel first (`journalctl -b N -k | grep -m1 'Linux version'`)
— never conclude from one filtered tail.

## Session / PAM / dbus noise

- `gnome-keyring-daemon` assertion bursts (`gkd_secret_service_get_objects`,
  `G_IS_DBUS_CONNECTION`, `G_IS_DBUS_INTERFACE_SKELETON`) at session start — **per-boot
  variable, traced across three boots as 34 / 8 / 23 lines**, so a jump is not a
  regression. `gnome-keyring-daemon.service` reads `disabled; preset: disabled` in the
  user manager while the daemon runs anyway (started by the session, not the unit).
  Do not report either as new; the per-boot count is what makes them baseline.
- `omarchy-shell` QML warnings from 4.5's shell: `WARN scene: QML ShellIpc` (~19/boot),
  `@Ui/Panel.qml` (~4), `Qt.atob(string)` deprecations, one binding loop in
  `plugins/notifications/Service.qml`, and `Unrecognized pragma "OmarchyLoadPatch"` —
  the last one is **upstream's own** `/usr/share/omarchy/shell/shell.qml`, not the
  image's config (`system_files/` has no match), so it is not ours to fix.
- `systemd-logind: Failed to open '/boot/loader/entries'` — the wording varies by host
  and boot (`Remote address changed` on mini, `Too many levels of symbolic links`
  here); it is a transient during early boot, and afterwards `readlink -f
  /boot/loader/entries` resolves to `/boot/loader.0/entries` which exists. Cosmetic
  enumeration failure either way.

- `PAM unable to dlopen(/usr/lib64/security/pam_fprintd.so): cannot open shared object file` on every `sudo`, `sddm-helper`, and `quickshell` auth — `fprintd` is installed but `fprintd-pam` is not, so fingerprint auth is silently unavailable. Cosmetic; would be fixed by installing `fprintd-pam` (ask first — package change).
- `/usr/lib/udev/rules.d/70-u2f.rules:NN Failed to resolve group 'plugdev', ignoring` — group not defined on Fedora; U2F rules skipped.
- `Ignoring duplicate name 'org.gnome.NautilusPreviewer' in service file` — duplicate dbus service file in the image.
- `systemd-logind: Failed to open '/boot/loader/entries': Remote address changed`, `Existing logind session ID 1 used by new audit session`.
- `AVC avc: denied { mac_admin } for comm="chcon" ... tuned_t` — tuned, 2 per boot, no impact.
- `Trying to measure BzFeaturedTile ... but it needs at least N` — GTK measurement warnings from an app in the user session.
- `user : a password is required ; PWD=*** ; COMMAND=/usr/sbin/true` — the user's own sudo attempts, not an intrusion signal.

## Application-level chatter (looks alarming, isn't)

- `uwsm_start-hyprland[PID]: > Warning: Unsupported maximum keycode 709 ...` / `Virtual modifier Hyper multiply defined` / `Key <LFSH> added to map for multiple modifiers` — xkbcomp output from **Xwayland clients**, one short-lived process per X11 app. Thousands per day is normal and does **not** mean Hyprland is restarting. Confirm with `ps -eo pid,etimes,comm | grep Hyprland`: a healthy session shows Hyprland's uptime equal to system uptime.
- `bluetoothd: src/profile.c:ext_io_disconnected() Unable to get io data for Hands-Free unit: getpeername: ENOTCONN` repeated every few seconds, plus `avdtp_connect_cb ... Connection timed out` / `policy.c:reconnect_timeout ... Device or resource busy` — a paired phone (`C4:C1:7D:EE:EF:2B`, "the user's iPhone") is trusted but out of range, so bluetoothd retries its HFP profile forever. This is the single largest source of err-level lines on this machine (~90% of a typical 100+ count). Silence it by untrusting/removing the device, or ignore it.
- `systemd-hostnamed` / `systemd-timedated` start/stop pairs — agents (including Hermes) calling hostname/time setters.
- `hermes[...]: WARNING agent.message_sanitization: Normalized provider-minted parallel tool-call ids` — Hermes' own log line.

## virt/libvirt

`virtnetworkd: Unable to find 'dnsmasq' binary in $PATH` and `virtnodedevd: internal error: Missing udev property 'ID_VENDOR_ID' on 'usbN'`. `libvirt-daemon-driver-network` and `virsh` are not installed, so the default NAT network cannot work — irrelevant unless the user starts VMs expecting networking. The `virtnodedevd` udev complaints are cosmetic.
