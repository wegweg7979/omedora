echo "Skip Chromium's new first-run EULA on machines already on Quattro"

# Chromium 151 flipped MasterPrefs::eula_required from false to true, so an
# unconfigured first run now stops on a blank terms-of-service dialog before the
# browser opens. Omarchy answers that in the seed it writes next to the Chromium
# binary, but that seed is only laid down by a fresh install and by the one-time
# 3.x upgrade, so machines already on Quattro never receive it. Retrofit it here.
#
# The literal is deliberately duplicated rather than sourced: a migration repairs
# the state of its own moment, and must not drift when the seed later changes.

# omedora: Arch-only, and impossible on the immutable host in any case.
# /usr/lib/chromium/initial_preferences is the Arch chromium binary's path:
# install/config/theme-system-fedora.sh deliberately does not seed it (Fedora's
# chromium reads its initial prefs from /usr/lib64/chromium-browser/, still an
# open TODO there). And / is composefs mounted ro, so the write below fails with
# EROFS even as root — /etc and /var are writable, /usr is not. Guarded rather
# than baked because the fork has not yet decided the Fedora-side seed path.
[[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == fedora* ]] && exit 0

chromium_prefs="/usr/lib/chromium/initial_preferences"
chromium_seed='{"distribution":{"require_eula":false},"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'

if [[ $(cat "$chromium_prefs" 2>/dev/null) != "$chromium_seed" ]]; then
  sudo mkdir -p "$(dirname "$chromium_prefs")"
  echo "$chromium_seed" | sudo tee "$chromium_prefs" >/dev/null
fi
