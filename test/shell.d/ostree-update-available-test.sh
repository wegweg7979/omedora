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
fixture '{"deployments":[{"booted":true,"staged":false,"timestamp":123,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 1 ]] || fail "current deployment exits 1"
pass "current deployment: up to date"

# Real rpm-ostree shape with a pending .staged deployment (the authoritative
# flag): non-booted + staged=true => update pending, regardless of timestamps.
fixture '{"deployments":[{"booted":true,"staged":false,"timestamp":100,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"staged":true,"timestamp":200,"container-image-reference-digest":"sha256:new"}]}'
status=""
out=$(OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" 2>/dev/null) || status=$?
[[ ${status:-0} -eq 0 ]] || fail "staged flag deployment exits 0"
grep -q 'omarchy-ostree-image' "$XDG_STATE_HOME/omarchy/updates/available" || fail "staged flag deployment writes a package line"
pass "pending .staged=True deployment: exit 0, update listed"

# A deployment that WAS staged but is now the booted one (post-reboot), with
# staged cleared, MUST NOT be reported again — the original lexicographic '>'
# compare could misfire here.
fixture '{"deployments":[{"booted":true,"staged":false,"timestamp":200,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"staged":false,"timestamp":100,"container-image-reference-digest":"sha256:old"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 1 ]] || fail "post-reboot booted deployment (staged cleared) is up to date"
pass "post-reboot deployment with staged=False: up to date"

# The live host shape that produced a phantom badge (studiobox2, rpm-ostree
# 2026.3): BOTH deployments carry an explicit staged=False, but the non-booted
# ROLLBACK sibling has a NEWER commit timestamp than the booted deployment
# (a rebuilt image off the same git commit keeps the older commit time, and the
# host is booted into that older-commit deployment). The pre-fix checker fell
# into the timestamp fallback because `select(.staged==true) | length` is a
# non-empty "0", and fired newest_ts > booted_ts -> exit 0 "update available"
# forever, on a host where bootc/rpm-ostree had nothing to apply.
fixture '{"deployments":[{"booted":true,"staged":false,"timestamp":1794458360,"version":"latest.20261112-95e6a12","container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:3f8f72f9"},{"booted":false,"staged":false,"timestamp":1794496296,"version":"latest.20261112-6ad8d5a","container-image-reference-digest":"sha256:42aca5cf"}]}'
status=""
out=$(OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" 2>/dev/null) || status=$?
[[ ${status:-0} -eq 1 ]] || fail "explicit staged=False on both deployments is up to date (newer rollback sibling must not fire)"
[[ $out == "System is up to date" ]] || fail "phantom shape prints the up-to-date line"
[[ ! -s $XDG_STATE_HOME/omarchy/updates/available ]] || fail "phantom shape leaves available empty"
pass "explicit staged=False + newer rollback sibling: up to date (no phantom update)"

# Same shape, but the sibling IS staged: the field still wins over timestamps.
fixture '{"deployments":[{"booted":true,"staged":false,"timestamp":1794458360,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:3f8f72f9"},{"booted":false,"staged":true,"timestamp":1794496296,"container-image-reference-digest":"sha256:42aca5cf"}]}'
status=""
out=$(OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" 2>/dev/null) || status=$?
[[ ${status:-0} -eq 0 ]] || fail "staged sibling still exits 0"
grep -q 'omarchy-ostree-image' "$XDG_STATE_HOME/omarchy/updates/available" || fail "staged sibling writes a package line"
pass "explicit staged=True sibling: update listed"

# Legacy shape with NO staged field anywhere keeps the timestamp fallback: a
# newer non-booted deployment is the only signal such rpm-ostree gives.
fixture '{"deployments":[{"booted":true,"timestamp":100,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"timestamp":200,"container-image-reference-digest":"sha256:new"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 0 ]] || fail "legacy host (no staged field) with newer ts still reports an update"
pass "legacy host without the staged field: timestamp fallback still works"

# Legacy shape with no staged field and nothing newer: up to date.
fixture '{"deployments":[{"booted":true,"timestamp":200,"container-image-reference":"ostree-image-signed:docker://ghcr.io/acme/im:latest","container-image-reference-digest":"sha256:abc"},{"booted":false,"timestamp":100,"container-image-reference-digest":"sha256:old"}]}'
status=""
OMEDORA_OSTREE_JSON="$test_tmp/status.json" "$CHECKER" >/dev/null 2>&1 && status=0 || status=$?
[[ $status -eq 1 ]] || fail "legacy host (no staged field) with older sibling is up to date"
pass "legacy host without the staged field: older sibling ignored"
