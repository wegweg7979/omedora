#!/bin/bash
#
# L1 test: the menu's package guards answer through the Fedora package map.
#
# The menu evaluates every `when:` / `disabled:` in one bash batch built by
# shell/plugins/menu/MenuModel.js guardScript(). Upstream shadows
# omarchy-pkg-present / -missing there with a set read from pacman, which on
# Fedora is empty: every Remove row gated on a package hid itself and no
# Install row ever read as installed. The carried Fedora branch rebuilds the
# set from `bin/fedora/pkg.py installed`, so the guards agree with the real
# helpers.
#
# The batch runs as the menu runs it, from this checkout's bin/, with stub
# rpm/flatpak (test/mocks) that report packages installed, and a pacman that
# records any call and knows nothing, so an answer that came from pacman would
# hide the rows asserted to show.
#
# ROWS must name rows the SHIPPED menu still has: guardScript() exits 1 on an id
# that is not there, which aborts the whole L1 job before the later gates (the
# byte-identity audit among them) get to run. That is how this test went red when
# the OpenClaw rows were pruned as dead 4.5 additions — prune a row, drop it here
# in the same change. Each id below also carries a distinct guard mechanism: a
# mapped RPM (voxtype-bin → voxtype), a names-aliased RPM (vim → vim-enhanced), a
# package with no map entry at all (firefox, resolved natively), a Flathub app
# (slack-desktop), and two skip-mapped names.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

# node builds the batch from MenuModel.js, as the menu does. It is not an
# Omarchy base package, so an installed system (the L3 smoke reruns this suite
# there) may lack it: skip there, but never in CI, where it is preinstalled.
if ! command -v node >/dev/null; then
  [[ -z ${CI:-} ]] || fail "node is required to build the menu guard batch"
  echo "ok - # SKIP node is not installed; the menu guard batch needs it"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cp "$ROOT/test/mocks/rpm" "$ROOT/test/mocks/flatpak" "$STUBS/"
cat >"$STUBS/pacman" <<'STUB'
#!/bin/bash
echo "pacman $*" >>"$PACMAN_LOG"
case "$1" in
-Qq) [[ -z ${PACMAN_INSTALLED:-} ]] || printf '%s\n' $PACMAN_INSTALLED ;;
-Qi) ;;
*) exit 1 ;;
esac
STUB
cat >"$STUBS/pacman-conf" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$STUBS"/*

export MOCK_LOG="$TMP/mock.log"
export PACMAN_LOG="$TMP/pacman.log"
export OMEDORA_FEDORA_VERSION=44
export OMARCHY_FEDORA_MAP="$ROOT/install/packages/fedora.toml"
# No stored snapshot: the batch builds its set fresh every run.
export XDG_RUNTIME_DIR=""

# The guard batch for the named rows of the shipped menu.
guard_script() {
  ROWS="$*" node -e '
    const fs = require("fs")
    const path = require("path")
    const root = process.env.ROOT
    const menu = require(path.join(root, "shell/plugins/menu/MenuModel.js"))
    const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
    const wanted = process.env.ROWS.split(" ")
    const picked = {}
    for (const id of wanted) {
      const item = items.find(entry => entry.id === id)
      if (!item) { console.error(`no menu row ${id}`); process.exit(1) }
      picked[id] = item
    }
    process.stdout.write(menu.guardScript(picked))
  '
}
export ROOT

# Runs a batch under the given distro and prints its sorted answers.
run_batch() {
  local distro="$1" script="$2"
  : >"$MOCK_LOG"
  : >"$PACMAN_LOG"
  OMARCHY_DISTRO="$distro" PATH="$STUBS:$ROOT/bin:$PATH" bash -c "$script" | sort
}

ROWS=(remove.dictation remove.dictation.voxtype remove.dictation.superwhisper install.editor.vim remove.browser.firefox install.ai.grok-bot remove.ai.grok-bot install.service.slack)
script=$(guard_script "${ROWS[@]}")

# --- Fedora: every RPM and Flatpak reports installed ------------------------

answers=$(MOCK_RPM_INSTALLED="*" MOCK_FLATPAK_INSTALLED="com.slack.Slack" run_batch fedora "$script")

assert_output_contains "Fedora: Remove > Dictation shows with voxtype installed" "$answers" "remove.dictation:w:1"
assert_output_contains "Fedora: Remove > Dictation > Voxtype shows (voxtype-bin → voxtype RPM)" "$answers" "remove.dictation.voxtype:w:1"
assert_output_contains "Fedora: Install > Editor > Vim is disabled once vim-enhanced is installed (vim → vim-enhanced)" "$answers" "install.editor.vim:d:1"
assert_output_contains "Fedora: Remove > Browser > Firefox shows (no map entry: resolved natively through rpm)" "$answers" "remove.browser.firefox:w:1"
assert_output_contains "Fedora: a Flathub-mapped app reads as installed (slack-desktop → com.slack.Slack)" "$answers" "install.service.slack:d:1"

# A skip-mapped package has nothing installed on Fedora, so its Remove row must
# not show even when every RPM query answers yes.
assert_output_contains "Fedora: skip-mapped superwhisper-bin never shows Remove > Dictation > Superwhisper" "$answers" "remove.dictation.superwhisper:w:0"
assert_output_contains "Fedora: skip-mapped grok-bot never shows Remove > AI > Grok Bot" "$answers" "remove.ai.grok-bot:w:0"
assert_output_contains "Fedora: skip-mapped grok-bot never reads as installed" "$answers" "install.ai.grok-bot:d:0"

grep -q '^rpm -q --qf' "$MOCK_LOG" || fail "Fedora: the guard batch asks rpm once, batched"
(( $(grep -c '^rpm ' "$MOCK_LOG") == 1 )) || { cat "$MOCK_LOG" >&2; fail "Fedora: the guard batch makes exactly one rpm query"; }
pass "Fedora: one batched rpm query answers every package guard"
(( $(grep -c '^flatpak list' "$MOCK_LOG") == 1 )) || { cat "$MOCK_LOG" >&2; fail "Fedora: the guard batch lists Flatpaks once"; }
pass "Fedora: one flatpak listing answers every Flathub-mapped guard"

# --- Fedora: nothing installed ----------------------------------------------

answers=$(MOCK_RPM_INSTALLED="" MOCK_FLATPAK_INSTALLED="" run_batch fedora "$script")
assert_output_contains "Fedora: Remove > Dictation > Voxtype hides without voxtype" "$answers" "remove.dictation.voxtype:w:0"
assert_output_contains "Fedora: Install > Editor > Vim stays enabled without vim" "$answers" "install.editor.vim:d:0"
assert_output_contains "Fedora: Remove > Browser > Firefox hides without the firefox RPM" "$answers" "remove.browser.firefox:w:0"

# --- Fedora: the shadows agree with the real helpers ------------------------
# A name no guard spelled out (built at run time) goes to the real helper.

dynamic=$(ROWS=x node -e '
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  process.stdout.write(menu.guardScript({
    dyn: { id: "dyn", when: "p=voxtype-bin; omarchy-pkg-present $p" },
    lit: { id: "lit", when: "omarchy-pkg-present openclaw" },
    miss: { id: "miss", when: "omarchy-pkg-missing openclaw superwhisper-bin" }
  }))
')
answers=$(MOCK_RPM_INSTALLED="voxtype openclaw" run_batch fedora "$dynamic")
assert_equals "Fedora: literal, run-time and missing guards agree with the real helpers" \
  "$(tr '\n' ' ' <<<"$answers")" "dyn:w:1 lit:w:1 miss:w:1 "

# --- Arch: the upstream pacman snapshot, unchanged --------------------------

answers=$(PACMAN_INSTALLED="voxtype-bin vim" MOCK_RPM_INSTALLED="*" run_batch arch "$script")
assert_output_contains "Arch: Remove > Dictation > Voxtype shows from pacman" "$answers" "remove.dictation.voxtype:w:1"
assert_output_contains "Arch: Install > Editor > Vim is disabled from pacman" "$answers" "install.editor.vim:d:1"
assert_output_contains "Arch: firefox absent from pacman hides Remove > Browser > Firefox" "$answers" "remove.browser.firefox:w:0"
assert_output_contains "Arch: superwhisper-bin absent from pacman hides its Remove row" "$answers" "remove.dictation.superwhisper:w:0"
grep -q '^pacman -Qq' "$PACMAN_LOG" || fail "Arch: the guard batch reads pacman"
pass "Arch: the guard batch reads its package set from pacman"
[[ ! -s $MOCK_LOG ]] || { cat "$MOCK_LOG" >&2; fail "Arch: the guard batch never asks rpm or flatpak"; }
pass "Arch: the guard batch never asks rpm or flatpak"

# --- Fedora immutable: installability answers through the ostree helper ------
# An immutable host cannot dnf install, so a dnf-mapped package is installable
# there only once the image baked it. The guard has to ask the helper that
# knows that, not the mutable sibling it shares the batch with.

immutable=$(guard_script install.editor.helix install.editor.vim)

grep -q 'omarchy-ostree/pkg.py" installable-list' <<<"$immutable" || fail "immutable: the installability guard does not pick the ostree helper"
pass "immutable: the installability guard picks the helper for the host kind"
grep -q 'omarchy-pkg-installable helix' <<<"$immutable" || fail "immutable: the row's installability guard is missing from the batch"
pass "immutable: the row's installability guard reaches the batch"

answers=$(MOCK_RPM_INSTALLED="vim-enhanced" run_batch fedora-ostree "$immutable")
assert_output_contains "Immutable: Helix hides while it is a dnf package the image never baked" "$answers" "install.editor.helix:w:0"
assert_output_contains "Immutable: baked Vim still shows, and reads as installed" "$answers" "install.editor.vim:d:1"

answers=$(MOCK_RPM_INSTALLED="vim-enhanced helix" run_batch fedora-ostree "$immutable")
assert_output_contains "Immutable: Helix shows once the image carries it" "$answers" "install.editor.helix:w:1"

# --- the Fedora branch is one guarded block --------------------------------

arch_script=$(guard_script remove.dictation.voxtype)
grep -q 'pacman -Qq' <<<"$arch_script" || fail "the batch still carries upstream's pacman snapshot"
pass "the batch still carries upstream's pacman snapshot"
(( $(grep -c 'fedora/pkg.py" installed' <<<"$arch_script") == 1 )) || fail "the batch asks pkg.py once"
pass "the batch asks pkg.py once, inside the Fedora branch"
