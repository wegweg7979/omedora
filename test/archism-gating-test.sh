#!/bin/bash
#
# L1: the menu-reachable Arch-ism bins gate cleanly on Fedora.
#
# Several upstream bins hard-errored on Fedora (pacman / mkinitcpio / AUR names)
# when reached from the menu. Each survivor has an additive top-of-file Fedora
# arm; the Arch path stays byte-identical (byte-identity-test enforces that).
# Here we check the Fedora behavior: the no-op gate exits 0 and emits NO
# pacman/mkinitcpio calls, the install gate dispatches to dnf (not pacman), and
# the Arch body still follows the gate. pacman, mkinitcpio, dracut, sudo, gum
# are stubbed as tracers; OMARCHY_DISTRO selects the path.
#
# The port pruned the boot stack (plymouth) and the pacman-channel family, so
# those bins are pinned ABSENT below instead of exercised: pinning them gone is
# the useful assertion, because an upstream merge that brings one back would
# ship an ungated Arch-ism with no Fedora arm.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
MOCK_LOG="$TMP/mock.log"; export MOCK_LOG

for c in pacman mkinitcpio limine-mkinitcpio dracut plymouth-set-default-theme \
         fprintd-enroll fprintd-verify authselect expac retroarch systemctl ufw; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 0\n' "$c" "$MOCK_LOG" >"$BIN/$c"
done
# sudo: log + run the rest (so a sudo'd pacman still hits the pacman tracer).
printf '#!/bin/bash\nprintf "sudo %%s\\n" "$*" >>"%s"\n"$@"\n' "$MOCK_LOG" >"$BIN/sudo"
# pkg helpers: tracer (so fingerprint/retroarch dnf installs are observable).
for c in omarchy-pkg-add omarchy-pkg-present omarchy-pkg-drop; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 1\n' "$c" "$MOCK_LOG" >"$BIN/$c"
done
chmod +x "$BIN"/*
export PATH="$BIN:$ROOT/bin:$PATH"

run() { : >"$MOCK_LOG"; ( export OMARCHY_DISTRO="$1"; shift; bash "$@" ) >"$TMP/out" 2>&1; echo $?; }
log_has() { grep -qF "$1" "$MOCK_LOG"; }

# --- the pruned Arch-ism families stay pruned -------------------------------
for gone in omarchy-refresh-pacman omarchy-refresh-plymouth omarchy-plymouth-set \
            omarchy-plymouth-reset omarchy-install-service-sunshine; do
  if [[ -e $ROOT/bin/$gone ]]; then
    fail "$gone is pruned on the port; if it comes back it needs its Fedora arm"
  else
    pass "$gone stays pruned (the image owns that stack on Fedora)"
  fi
done

# --- no-op gate: Fedora exits 0, emits NO pacman/mkinitcpio -----------------

rc=$(run fedora "$ROOT/bin/omarchy-channel-set")
assert_equals "omarchy-channel-set: Fedora exits 0" "$rc" "0"
if log_has pacman || log_has mkinitcpio; then
  cat "$MOCK_LOG" >&2; fail "omarchy-channel-set: Fedora path makes no pacman/mkinitcpio call"
else
  pass "omarchy-channel-set: Fedora path makes no pacman/mkinitcpio call"
fi
grep -qF "isn't available on Omedora" "$TMP/out" \
  && pass "omarchy-channel-set: Fedora says why instead of silently succeeding" \
  || { cat "$TMP/out" >&2; fail "omarchy-channel-set: Fedora says why instead of silently succeeding"; }

# --- install gates: Fedora dispatches to dnf names, not pacman --------------
run fedora "$ROOT/bin/omarchy-setup-security-fingerprint" >/dev/null || true
log_has 'pacman -Rdd' && { cat "$MOCK_LOG" >&2; fail "fingerprint: no pacman -Rdd on Fedora"; } \
  || pass "fingerprint: no pacman -Rdd on Fedora"
log_has 'omarchy-pkg-add fprintd fprintd-pam libfprint usbutils' \
  && pass "fingerprint: installs the Fedora package set" \
  || { cat "$MOCK_LOG" >&2; fail "fingerprint: installs the Fedora package set"; }

# --- Arch path preserved: the Fedora arm is additive ------------------------
# byte-identity proves byte-equality; here confirm the Arch body still follows
# the gate, using the shape the Fedora arms grow (exec the sibling inside the
# case, the untouched pacman body after it). omarchy-pkg-missing answers "yes,
# something is missing" so the install body is actually reached.
if sed -n '/^esac$/,$p' "$ROOT/bin/omarchy-pkg-add" | grep -q 'pacman -S'; then
  pass "omarchy-pkg-add: the pacman body still follows the Fedora gate"
else
  fail "omarchy-pkg-add: the pacman body still follows the Fedora gate"
fi
printf '#!/bin/bash\nexit 0\n' >"$BIN/omarchy-pkg-missing"
chmod +x "$BIN/omarchy-pkg-missing"
run arch "$ROOT/bin/omarchy-pkg-add" tracer-pkg >/dev/null || true
log_has 'pacman -S --noconfirm --needed -- tracer-pkg' \
  && pass "omarchy-pkg-add: Arch path still reaches pacman through sudo" \
  || { cat "$MOCK_LOG" >&2; fail "omarchy-pkg-add: Arch path still reaches pacman through sudo"; }

# --- debug: Fedora package list uses rpm/dnf, not the expac/pacman pipeline --
grep -q 'rpm -q omedora omedora-settings' "$ROOT/bin/omarchy-debug" \
  && pass "omarchy-debug: Fedora arm queries packages via rpm/dnf" \
  || fail "omarchy-debug: Fedora arm queries packages via rpm/dnf"

echo "# all archism-gating tests passed"
