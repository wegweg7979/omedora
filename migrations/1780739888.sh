echo "Use dua for Disk Usage TUI"

# omedora: Arch-only. The 4.5 line replaced dua with disktree, and the swap on
# omedora is already the work of migrations/1791345484.sh ("Replace the Disk
# Usage TUI with Disktree"): disktree is baked into the image, dua-cli is not.
# The pkg helper therefore exits 1 on the add below, which aborts the whole
# migration run on the immutable host. Skipped whole, not just the add: the
# desktop entry it would re-point at `dua i` is disktree's by the time this runs.
[[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == fedora* ]] && exit 0

omarchy-pkg-add dua-cli
omarchy-pkg-drop dust

APP_DIR="$HOME/.local/share/applications"
ICON_DIR="$APP_DIR/icons"

if [ -f "$APP_DIR/Disk Usage.desktop" ]; then
  rm "$APP_DIR/Disk Usage.desktop"
  omarchy-tui-install "Disk Usage" "dua i" float "$ICON_DIR/Disk Usage.png"
fi
