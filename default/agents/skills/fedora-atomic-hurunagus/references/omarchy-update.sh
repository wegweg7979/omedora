#!/bin/bash
# omarchy-update — Fedora/rpm-ostree variant for hurunagus projects
#
# Replaces the Arch/pacman-based omarchy-update on immutable Fedora systems.
# Detects the distribution and runs ujust update (rpm-ostree + flatpak + distrobox).
#
# Install: copy to system_files/usr/local/bin/omarchy-update in the repo
# (installed to /usr/local/bin/omarchy-update in the built image).
# The /usr/local/bin prefix takes precedence over /usr/sbin in PATH.

set -uo pipefail

# ---------------------------------------------------------------------------
# Detect distribution (same logic as omsarchy-distro)
# ---------------------------------------------------------------------------
OMARCHY_DISTRO="${OMARCHY_DISTRO:-}"

if [[ -z "${OMARCHY_DISTRO:-}" ]]; then
  id=""
  id_like=""
  if [[ -r /etc/os-release ]]; then
    while IFS='=' read -r key value; do
      # Strip surrounding quotes from value
      value="${value%"}"
      value="${value#"}"
      case "$key" in
        ID)      id="$value" ;;
        ID_LIKE) id_like="$value" ;;
      esac
    done < /etc/os-release
  fi

  case "$id" in
    arch)   OMARCHY_DISTRO=arch ;;
    fedora) OMARCHY_DISTRO=fedora ;;
  esac

  # Fallback: check ID_LIKE
  for token in $id_like; do
    case "$token" in
      fedora) OMARCHY_DISTRO=fedora; break ;;
      arch)   OMARCHY_DISTRO=arch; break ;;
    esac
  done
fi

echo "omarchy-update: detected OMARCHY_DISTRO=${OMARCHY_DISTRO:-unknown}"

# ---------------------------------------------------------------------------
# Fedora (rpm-ostree) path — run ujust update (rpm-ostree + flatpak + distrobox)
# ---------------------------------------------------------------------------
if [[ "${OMARCHY_DISTRO:-}" == "fedora" ]]; then
  echo -e "\e[32mRunning ujust update (rpm-ostree + flatpak + distrobox)...\e[0m"

  if ! command -v ujust &>/dev/null; then
    echo "ERROR: ujust command not found. Please install 'just'." >&2
    exit 1
  fi

  ujust update
  exit $?
fi

# ---------------------------------------------------------------------------
# Arch / other path — fall back to original Omarchy updater
# ---------------------------------------------------------------------------
echo -e "\e[33mRunning Arch-style omarchy update (fallback)...\e[0m"
exec /usr/sbin/omarchy-update "$@"
