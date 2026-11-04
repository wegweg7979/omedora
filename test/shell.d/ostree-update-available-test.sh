#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

CHECKER="$ROOT/bin/omarchy-ostree/update-available"

# Home that will receive the state files.
export HOME="$test_tmp/home"
export XDG_STATE_HOME="$test_tmp/home/.local/state"

fixture() {
  printf '%s' "$1" >"$test_tmp/status.json"
}

# A single booted deployment that is current (nothing staged, and skopeo would
# agree — here we never reach skopeo because staged-detect is authoritative
# once the newest == booted; with no skopeo_cmd seam we skip the network path
# by leaving the deployment timestamps equal, so up-to-date is decided purely
# from the staged check).
fixture '{"deployments":[{"booted":true,"timestamp":100,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"}]}'
out=$(OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" 2>/dev/null) || status=$?
[[ ${status:-0} -eq 1 ]] || fail "up-to-date deployment exits 1"
[[ $out == "System is up to date" ]] || fail "up-to-date prints the widget's up-to-date line"
[[ -f $XDG_STATE_HOME/omarchy/updates/available ]] || fail "state files are written"
[[ ! -s $XDG_STATE_HOME/omarchy/updates/available ]] || fail "available file is empty when up to date"
pass "up-to-date deployment: exit 1, empty available, state files written"

# A staged (non-booted) newer deployment: newest timestamp > booted. OSTree's
# own rollback sibling is also non-booted, so the check must compare timestamps,
# not count non-booted deployments — here the non-booted one is genuinely newer.
fixture '{"deployments":[{"booted":true,"timestamp":100,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"timestamp":200,"container-image-reference-digest":"sha256:new"}]}'
status=""
out=$(OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" 2>/dev/null) || status=$?
[[ ${status:-0} -eq 0 ]] || fail "staged newer deployment exits 0"
[[ -s $XDG_STATE_HOME/omarchy/updates/available ]] || fail "available file is non-empty when an update is staged"
grep -q 'omarchy-ostree-image' "$XDG_STATE_HOME/omarchy/updates/available" || fail "staged update writes a package line"
pass "staged deployment (newest ts > booted): exit 0, update listed"

# Fake up-to-date even when a non-booted rollback sibling is OLDER: newest ==
# booted timestamp must NOT fire just because a non-booted deployment exists.
fixture '{"deployments":[{"booted":true,"timestamp":200,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"timestamp":100,"container-image-reference-digest":"sha256:old"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 1 ]] || fail "older rollback sibling does not count as an update"
pass "older rollback sibling ignored (checks newest ts vs booted ts)"

# Real up-to-date on a genuine bootc host shape (no skopeo seam => skip network).
fixture '{"deployments":[{"booted":true,"timestamp":123,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 1 ]] || fail "current deployment exits 1"
pass "current deployment: up to date"
