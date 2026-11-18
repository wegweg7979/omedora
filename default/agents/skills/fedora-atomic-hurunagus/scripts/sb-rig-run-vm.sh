#!/bin/bash
# Boot an ESP built by sb-rig-mk-esp.sh under OVMF with Secure Boot ENFORCING,
# capture the serial console to a file, then quit. Linux's own log is the proof
# that the kernel executed; grub/shim refusals also land on serial here.
#
#   usage: sb-rig-run-vm.sh <esp.img> <vars.fd> <label> [seconds]
# Expects /work mounted from the host (see references/secure-boot-signing.md),
# a rig image with qemu-kvm+edk2-ovmf, and `--device /dev/kvm`.
# Note: with Secure Boot on, an unsigned/unknown-key kernel must produce
#   kern/efi/sb.c:shim_lock_verifier_write:192:bad shim signature.
#   loader/i386/efi/linux.c:grub_cmd_initrd:260:you need to load the kernel first
# and zero kernel output -- that is the negative control, not a failure.
set -uo pipefail
W=/work
ESP="$1"; VARS="$2"; LABEL="$3"; RUNFOR="${4:-75}"

rm -f "$W/serial-$LABEL.log" "$W/mon-$LABEL.sock"

qemu-system-x86_64 \
  -machine q35,smm=on -m 3072 -smp 2 -accel kvm \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE.secboot.fd \
  -drive if=pflash,format=raw,unit=1,file="$W/$VARS" \
  -drive file="$W/$ESP",format=raw,if=none,id=hd0 \
  -device virtio-blk-pci,drive=hd0 \
  -display none -vga std \
  -serial "file:$W/serial-$LABEL.log" \
  -monitor "unix:$W/mon-$LABEL.sock,server=on,wait=off" \
  -boot order=c &
QPID=$!

python3 - "$W/mon-$LABEL.sock" "$LABEL" "$RUNFOR" <<'PY'
import os, socket, sys, time
sock_path, label, runfor = sys.argv[1], sys.argv[2], int(sys.argv[3])
def connect(path, tries=60):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(path); return s
        except OSError:
            time.sleep(0.5)
    raise SystemExit("monitor socket never appeared")
mon = connect(sock_path)
time.sleep(1); mon.recv(65536)
serial = f"/work/serial-{label}.log"
markers = ("Linux version", "dracut", "systemd", "bad shim signature",
           "you need to load the kernel first", "Security Violation")
seen, t0 = [], time.time()
while time.time() - t0 < runfor:
    if os.path.exists(serial):
        txt = open(serial, errors="replace").read()
        for m in markers:
            if m in txt and m not in seen:
                seen.append(m); print(f"[{time.time()-t0:5.0f}s] serial marker: {m}")
    time.sleep(3)
print("serial markers seen:", seen or "NONE")
mon.sendall(b"quit\n")
PY
wait "$QPID" 2>/dev/null

echo "=== serial log ($LABEL): $(wc -c < "$W/serial-$LABEL.log" 2>/dev/null || echo 0) bytes ==="
grep -aoE 'Linux version [0-9][^ ]*' "$W/serial-$LABEL.log" 2>/dev/null | head -1
echo "kernel log lines: $(grep -ac dracut "$W/serial-$LABEL.log" 2>/dev/null)  |  refusals: $(grep -ac 'bad shim signature' "$W/serial-$LABEL.log" 2>/dev/null)"
