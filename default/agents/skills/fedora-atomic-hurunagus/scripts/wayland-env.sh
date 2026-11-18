#!/bin/bash
# Print `export ...` lines for the user's live Wayland/Hyprland session.
#
#   eval "$(bash scripts/wayland-env.sh)"
#
# WHY this exists: the compositor exports WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE
# to its CHILDREN only, so a fresh agent shell has neither, and then every GUI call
# (grim, hyprctl, any Qt/GTK app) fails with "failed to create display" — which reads
# like a broken tool instead of a missing variable.
#
# Matching processes by NAME (`pgrep -f 'quickshell|Hyprland'`) and reading the first
# readable /proc/<pid>/environ is NOT enough: that candidate often carries
# XDG_RUNTIME_DIR but no WAYLAND_DISPLAY, so the export silently yields nothing.
# Scan for the VARIABLE itself, among processes owned by the current user.
set -u
for p in $(ls /proc | grep -E '^[0-9]+$'); do
    [ -r "/proc/$p/environ" ] || continue
    [ "$(stat -c %u "/proc/$p" 2>/dev/null)" = "$(id -u)" ] || continue
    dump=$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null) || continue
    case "$dump" in
        *$'\n'WAYLAND_DISPLAY=*|WAYLAND_DISPLAY=*)
            printf '%s\n' "$dump" \
                | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|HYPRLAND_INSTANCE_SIGNATURE|XDG_SESSION_TYPE)=' \
                | sed 's/^/export /'
            exit 0
            ;;
    esac
done
echo "echo 'wayland-env: no live Wayland session found for uid $(id -u)' >&2" >&2
exit 1
