#!/bin/bash
# Build a minimal UEFI boot disk for Secure Boot testing: a real MBR + one EFI
# System Partition holding the actual Fedora chain (shim -> grub -> a kernel).
#
#   usage: sb-rig-mk-esp.sh <kver> <source-vmlinuz> <output-img-name>
#
# Expected layout inside the rig container (see references/secure-boot-signing.md):
#   /work   writable dir holding the kernel(s), cert, initramfs and outputs
#   /probe  read-only tree of the EXTRACTED shim/grub RPMs, i.e. containing
#           usr/lib/efi/shim/16.1-7/EFI/fedora/{shimx64,mmx64}.efi and
#           usr/lib/efi/grub2/1:2.12-83.fc45/EFI/fedora/grubx64.efi
#   /work/initramfs.img  the image's real initramfs (podman cp it out; the
#                        in-image copy is mode 0600 root)
#   /work/hurunagus-kernel.der  cert for the varstore (--add-db / --add-mok)
# Requires: python3, mkfs.vfat, mtools, virt-fw-vars, OVMF_VARS.secboot.fd.
set -euo pipefail
W=/work
PROBE=/probe
KVER="$1"
VMLINUZ="$2"
OUT="$3"
SIZE_MB=400

cd "$W"
rm -f "$OUT"

# 1. raw disk: MBR + one EFI System Partition (type 0xEF) starting at LBA 2048
python3 - "$W/$OUT" "$SIZE_MB" <<'PY'
import sys, struct
path, mb = sys.argv[1], int(sys.argv[2])
total = mb*1024*1024//512
start = 2048
size = total - start - 2048
mbr = bytearray(512)
mbr[446 + 0] = 0x80
mbr[446 + 1:446 + 4] = bytes([0x00, 0x02, 0x00])
mbr[446 + 4] = 0xEF
mbr[446 + 5:446 + 8] = bytes([0xFE, 0xFF, 0xFF])
struct.pack_into('<II', mbr, 446 + 8, start, size)
mbr[510:512] = b'\x55\xaa'
with open(path, 'wb') as f:
    f.truncate(total * 512)
    f.seek(0)
    f.write(mbr)
print(f"disk: {total} sectors, ESP at LBA {start} size {size}")
PY
mkfs.vfat --offset=2048 -F 32 "$W/$OUT" >/dev/null
IMG="$W/$OUT@@1048576"
mmd -i "$IMG" ::/EFI ::/EFI/BOOT ::/EFI/fedora

# 2. shim (Microsoft-signed, so firmware trusts it) + MokManager
SHIM="$PROBE/usr/lib/efi/shim/16.1-7/EFI/fedora/shimx64.efi"
MMX="$PROBE/usr/lib/efi/shim/16.1-7/EFI/fedora/mmx64.efi"
mcopy -i "$IMG" "$SHIM" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$IMG" "$SHIM" ::/EFI/fedora/shimx64.efi
mcopy -i "$IMG" "$MMX" ::/EFI/fedora/mmx64.efi
mcopy -i "$IMG" "$MMX" ::/EFI/BOOT/mmx64.efi

# 3. Fedora-signed grub, everywhere shim may look for it
GRUB="$PROBE/usr/lib/efi/grub2/1:2.12-83.fc45/EFI/fedora/grubx64.efi"
mcopy -i "$IMG" "$GRUB" ::/EFI/fedora/grubx64.efi
mcopy -i "$IMG" "$GRUB" ::/EFI/BOOT/grubx64.efi

# 4. the kernel under test + the real initramfs
mcopy -i "$IMG" "$VMLINUZ" "::/vmlinuz-$KVER"
mcopy -i "$IMG" "$W/initramfs.img" "::/initramfs-$KVER.img"

# 5. grub config: kernel output on serial, survive the missing root with a shell
cat > /tmp/grub.cfg <<EOF
set timeout=3
set default=0
menuentry 'hurunagus SB probe' {
  linux /vmlinuz-$KVER console=ttyS0,115200 root=/dev/vda9 rd.shell panic=5
  initrd /initramfs-$KVER.img
}
EOF
mcopy -i "$IMG" /tmp/grub.cfg ::/EFI/fedora/grub.cfg
mcopy -i "$IMG" /tmp/grub.cfg ::/EFI/BOOT/grub.cfg

mdir -i "$IMG" ::/ ::/EFI/fedora

# 6. varstores: SB enforcing, with and without our cert where shim looks
if [[ ! -f "$W/vars-with-our-cert.fd" ]]; then
    cp /usr/share/OVMF/OVMF_VARS.secboot.fd "$W/vars-with-our-cert.fd"
    cp /usr/share/OVMF/OVMF_VARS.secboot.fd "$W/vars-stranger.fd"
    virt-fw-vars --input "$W/vars-with-our-cert.fd" --output "$W/vars-with-our-cert.fd" \
        --add-db d9bee56e-75dc-49d9-b4d7-b534210f637a "$W/hurunagus-kernel.der"
    virt-fw-vars --input "$W/vars-with-our-cert.fd" --output /dev/null --print 2>/dev/null \
        | grep -iE 'SecureBoot|db |PK|KEK' | head || true
fi
