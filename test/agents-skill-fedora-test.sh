#!/bin/bash
#
# L1 test: the shipped agent skill tells the truth about Fedora hosts.
#
# default/agents/skills/omarchy/ is not documentation on the side: the omedora
# RPM ships it to /usr/share/omarchy/default/agents/skills/omarchy, and
# omarchy-provision-user symlinks it into every agent's skill directory
# (~/.agents, ~/.claude, ~/.codex, ~/.pi, ~/.gemini, ~/.hermes), so it is the
# file an agent on a Fedora host actually reads before touching the desktop.
# Upstream's copy is Arch-only — it sent package installs to pacman/AUR, implied
# a writable /usr and reset configs with a bare `omarchy reinstall` — and this
# checkout carries the Fedora corrections in place. This gate keeps them there.
#
# Static only: it reads the skill text and asserts the Fedora claims against the
# code that implements them. It never runs the CLI against the live system.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SKILL_DIR="$ROOT/default/agents/skills/omarchy"
SKILL="$SKILL_DIR/SKILL.md"
CONTRIBUTING="$SKILL_DIR/contributing.md"

[[ -f $SKILL ]] || fail "the shipped omarchy skill is present at $SKILL"
[[ -f $CONTRIBUTING ]] || fail "the skill's contributing guide is present at $CONTRIBUTING"
pass "the shipped skill and its contributing guide are present"

# --- the distro reality is stated, and stated before the Arch instructions ---

grep -q 'omarchy-distro' "$SKILL" || fail "the skill tells the agent to ask omarchy-distro first"
pass "the skill points at the distro dispatcher"

grep -q 'fedora-ostree' "$SKILL" || fail "the skill names the immutable distro token"
grep -q 'composefs' "$SKILL" || fail "the skill says / is a read-only composefs mount on a bootc image"
pass "the skill names fedora-ostree and the read-only root"

distro_line=$(grep -n '^## Which distro is this?' "$SKILL" | head -1 | cut -d: -f1 || true)
commands_line=$(grep -n '^## Command Discovery' "$SKILL" | head -1 | cut -d: -f1 || true)
[[ -n $distro_line ]] || fail "the skill carries a 'Which distro is this?' section"
[[ -n $commands_line ]] || fail "the skill still carries Command Discovery"
(( distro_line < commands_line )) ||
  fail "the distro section must precede the Arch instructions it qualifies (line $distro_line vs $commands_line)"
pass "the Fedora reality is read before the first Arch instruction"

# --- the three per-distro commands are no longer misdescribed -----------------

grep -q 'bake it into the image build' "$SKILL" ||
  fail "the skill quotes what 'omarchy pkg add <rpm>' actually answers on an immutable host"
grep -q 'fedora.toml' "$SKILL" || fail "the skill names the Fedora package map as the place to bake"
grep -q 'no AUR at all' "$SKILL" || fail "the skill states that Fedora has no AUR"
grep -qi 'reboot to apply' "$SKILL" || fail "the skill states that an image update only takes effect after a reboot"
pass "package installs, the package map and the update semantics are described for Fedora"

! grep -qF 'for AUR-only packages' "$SKILL" ||
  fail "the decision framework must not offer AUR-only packages unconditionally any more"
grep -q 'Arch: `omarchy pkg add' "$SKILL" ||
  fail "the decision framework scopes the pacman/AUR route to Arch"
pass "the package route is scoped per distro in the decision framework"

! grep -qx 'omarchy reinstall' "$SKILL" ||
  fail "the nuclear reset must name its subcommand: the reinstall group ships only 'configs'"
grep -q 'omarchy reinstall configs' "$SKILL" || fail "the skill names 'omarchy reinstall configs'"
[[ -x $ROOT/bin/omarchy-reinstall-configs ]] || fail "bin/omarchy-reinstall-configs exists and is executable"
[[ ! -e $ROOT/bin/omarchy-reinstall ]] || fail "there is no bare bin/omarchy-reinstall for the skill to name"
pass "the reset command matches the reinstall group that actually ships"

! grep -qF '| **Arch Linux** | Base OS |' "$SKILL" ||
  fail "the architecture table must not claim Arch Linux as the base OS of the Fedora port"
! grep -qF 'This directory is owned by the omarchy package' "$SKILL" ||
  fail "the /usr/share/omarchy ownership note must not stop at the Arch package"
grep -q 'assume `sudo` ALWAYS prompts' "$SKILL" ||
  fail "the privilege section says Fedora sudo always prompts"
grep -q 'no NOPASSWD rules' "$SKILL" ||
  fail "the privilege section says omedora installs no NOPASSWD rules"
pass "the Arch-only architecture, ownership and privilege claims are corrected for Fedora"

# --- the claims match the code that implements them ---------------------------

grep -q 'fedora-ostree' "$ROOT/bin/omarchy-distro" ||
  fail "bin/omarchy-distro emits the token the skill's table documents"
pass "the distro token the skill documents is the one bin/omarchy-distro emits"

# --- the guides stay distro-neutral ------------------------------------------

for guide in capture.md hyprland.md plugins.md theming.md; do
  [[ -f $SKILL_DIR/$guide ]] || fail "topic guide $guide is present"
  ! grep -qE 'pacman|\bAUR\b|\bArch\b' "$SKILL_DIR/$guide" ||
    fail "$guide must stay distro-neutral; the Fedora deltas live in SKILL.md"
done
pass "the topic guides carry no distro-specific routes"

# --- Fedora bug reports are routed to the port, not only upstream -------------

grep -q 'wegweg7979/omedora' "$CONTRIBUTING" ||
  fail "contributing.md routes port bugs to the omedora repository"
grep -q 'hurunagus-hyprland' "$CONTRIBUTING" ||
  fail "contributing.md routes image bugs to the image repository"
grep -q 'rpm-ostree' "$CONTRIBUTING" ||
  fail "contributing.md asks for the deployment when reporting"
pass "contributing.md routes Fedora bugs to the port and the image"
