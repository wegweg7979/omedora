# Rig image for the Secure Boot VM tests (see references/secure-boot-signing.md).
#
#   podman build -t localhost/sbvm-tools:1 -f sbvm-rig.Containerfile .
#
# Run it with --device /dev/kvm (0666 here) and --security-opt label=disable
# (SELinux otherwise refuses to read bind mounts from $HOME). Needs no root and
# touches no host state: qemu + OVMF live entirely in this image.
#
# Contents: qemu-system-x86_64, OVMF_CODE.secboot.fd + OVMF_VARS.secboot.fd
# (/usr/share/OVMF/), mtools + dosfstools to assemble an ESP by hand, cpio for
# initramfs work, python3, and virt-firmware for virt-fw-vars (--add-db for the
# firmware-trust path, --add-mok for the path the enroll helper prepares).
FROM registry.fedoraproject.org/fedora:45
RUN dnf install -y --setopt=install_weak_deps=False \
        qemu-kvm edk2-ovmf mtools dosfstools cpio python3 virt-firmware \
    && dnf clean all
