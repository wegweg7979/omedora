#!/bin/bash
# about-logo-probe.sh — what the About launcher measures for a logo file.
#
# The About window's SIZE and the logo's sheen both come from measurements of
# ~/.config/omarchy/branding/about.txt. A logo that carries its own colour (SGR
# runs, which any per-cell-coloured art has) breaks them unless the launcher
# strips escapes first: the width probe then reports the escapes' own width, and
# the landmark probe returns a line that is never on screen. Both failures are
# silent — the window maps at the theme default and never corrects itself, and
# the sheen never builds a frame.
#
# Prints what the probes answer today (raw vs stripped), whether the landmark is
# findable in fastfetch's render, and whether the remembered fit is honoured.
# Read-only: it sources the launcher TRUNCATED at its launch tail, the same trick
# test/shell.d/launch-about-test.sh uses, so nothing opens.
#
#   bash scripts/about-logo-probe.sh [launcher] [logo]

set -u

launcher=${1:-/usr/bin/omarchy-launch-about}
logo=${2:-$HOME/.config/omarchy/branding/about.txt}
fit=${OMARCHY_ABOUT_FIT:-$HOME/.local/state/omarchy/windows/about.fit}
config="${OMARCHY_FASTFETCH_DIR:-/etc/fastfetch}/config.jsonc"

strip() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'; }

[[ -r $launcher ]] || { echo "no launcher at $launcher" >&2; exit 1; }
[[ -r $logo ]] || { echo "no logo at $logo" >&2; exit 1; }

cells=$(strip <"$logo" | LC_ALL=C.UTF-8 wc -L)

echo "launcher : $launcher"
echo "logo     : $logo"
printf 'width    : raw %s   stripped %s   rows %s\n' \
  "$(wc -L <"$logo")" "$cells" "$(wc -l <"$logo")"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
sed '/^presize_window$/,$d' "$launcher" >"$tmp/about.bash" || exit 1
# shellcheck disable=SC1090
source "$tmp/about.bash" 2>/dev/null || { echo "could not source the launcher head" >&2; exit 1; }
LOGO_FILE=$logo

measured=""
if measured=$(logo_dimensions); then
  read -r w h <<<"$measured"
  printf 'probe    : logo_dimensions -> %s x %s cells\n' "${w:-?}" "${h:-?}"
  [[ ${w:-} == "$cells" ]] \
    || echo "           ^ not the cell width: the width probe is measuring bytes, so no remembered fit can match"
else
  echo "probe    : logo_dimensions failed"
fi

IFS=$'\t' read -r at needle < <(logo_landmark) || true
if [[ -n ${needle:-} ]]; then
  esc=$'\e'
  case $needle in *"$esc"*) esc_state=carries-escapes ;; *) esc_state=clean ;; esac
  printf 'landmark : row %s, %s chars, %s\n' "${at:-?}" "${#needle}" "$esc_state"
  if [[ -r $config ]]; then
    render=$(fastfetch -c "$config" --pipe false 2>/dev/null | strip)
    case $render in
      *"$needle"*) echo "render   : landmark FOUND -> measure_layout answers: fit and sheen can proceed" ;;
      *)           echo "render   : landmark NOT found -> measure_layout fails: no fit, no sheen" ;;
    esac
  fi
else
  echo "landmark : none (logo_landmark found nothing)"
fi

if [[ -r $fit ]]; then
  read -r fit_w fit_h fit_px_w fit_px_h <"$fit" || true
  printf 'fit file : %s -> %s %s %s %s\n' "$fit" "${fit_w:-?}" "${fit_h:-?}" "${fit_px_w:-?}" "${fit_px_h:-?}"
  [[ -z ${w:-} || ${fit_w:-} == "$w" ]] \
    || echo "           logo_w differs from the measured logo -> the remembered fit is IGNORED (theme default wins)"
else
  echo "fit file : none at $fit (no remembered size)"
fi
