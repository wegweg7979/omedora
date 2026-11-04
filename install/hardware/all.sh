# omedora: Fedora runs the portable subset only (all-fedora.sh); the Arch list
# below is byte-identical to upstream. See omedora/architecture.md
# §"Omarchy 4 setup-system gating map" for the per-file decisions.
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]]; then
  source "$OMARCHY_INSTALL/hardware/all-fedora.sh"
  return 0 2>/dev/null || exit 0
fi

run_logged "$OMARCHY_INSTALL/hardware/network.sh"
run_logged "$OMARCHY_INSTALL/hardware/set-wireless-regdom.sh"
run_logged "$OMARCHY_INSTALL/hardware/fix-fkeys.sh"
run_logged "$OMARCHY_INSTALL/hardware/fix-synaptic-touchpad.sh"
run_logged "$OMARCHY_INSTALL/hardware/bluetooth.sh"
run_logged "$OMARCHY_INSTALL/hardware/vulkan.sh"

run_logged "$OMARCHY_INSTALL/hardware/intel/video-acceleration.sh"
run_logged "$OMARCHY_INSTALL/hardware/intel/lpmd.sh"
run_logged "$OMARCHY_INSTALL/hardware/intel/thermald.sh"
run_logged "$OMARCHY_INSTALL/hardware/intel/ipu7-camera.sh"
run_logged "$OMARCHY_INSTALL/hardware/intel/fix-wifi7-eht.sh"
run_logged "$OMARCHY_INSTALL/hardware/intel/sof-firmware.sh"

run_logged "$OMARCHY_INSTALL/hardware/fix-bcm43xx.sh"
run_logged "$OMARCHY_INSTALL/hardware/fix-yt6801-ethernet-adapter.sh"
run_logged "$OMARCHY_INSTALL/hardware/speaker-tuning.sh"
run_logged "$OMARCHY_INSTALL/hardware/pacman.sh"
