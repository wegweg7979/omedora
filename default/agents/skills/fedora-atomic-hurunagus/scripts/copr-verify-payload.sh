#!/bin/bash
#
# copr-verify-payload.sh - prove what a COPR actually serves.
#
# Resolves the newest PUBLISHED NEVRA of a package in one chroot, downloads that
# RPM into a scratch dir, extracts ONE file from it, and diffs that file against
# a local copy. This answers "is the fix really in the artifact?" without
# unpacking a few-hundred-MB payload and without trusting a green CI run.
#
#   bash scripts/copr-verify-payload.sh <owner>/<project> <chroot> <pkg> <path-in-rpm> [local-file]
#
# Example - the hurunagus update checker inside the omedora RPM:
#   bash scripts/copr-verify-payload.sh wegweg7979/omedora-4 fedora-45-x86_64 \
#     omedora ./usr/bin/omarchy-ostree/update-available \
#     ~/omedora-inspect/bin/omarchy-ostree/update-available
#
# With no local file the extracted file is printed instead of diffed.
# Exit 0 = identical (or printed), 1 = differs / member missing / not published,
# 2 = bad usage. Read-only: no repo is enabled, nothing is installed. Safe on an
# immutable host (/usr untouched; the only writes are in a scratch tmpdir).

set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

owner_project=$1
chroot_name=$2
pkg=$3
rpm_path=$4
local_file=${5:-}

[[ $owner_project == */* ]] || { echo "first arg must be <owner>/<project>" >&2; exit 2; }
command -v dnf5 >/dev/null || { echo "dnf5 not found; this probe resolves the EVR through dnf" >&2; exit 2; }
# cpio stores RPM members as ./usr/... — normalise whatever the caller passes
# (/usr/..., ./usr/... or usr/...) instead of only the bare form. A leading
# slash used to match nothing, which printed a FALSE "MISSING" for a file that
# was in the package all along.
rpm_path="${rpm_path#./}"
rpm_path="${rpm_path#/}"
rpm_path="./$rpm_path"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/copr-verify.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

base="https://download.copr.fedorainfracloud.org/results/${owner_project}/${chroot_name}/"
echo "== repo: $base"

# Let dnf order newness: the EVR carries the source sha ("...-1.<stamp>git<sha>"),
# so the newest line is the newest commit. Never hand-pick the newest out of
# repodata - a COPR repo accumulates EVERY build, so primary.xml's first match is
# usually an old version.
nevra_url=$(dnf5 --setopt=cachedir="$scratch/cache" \
  --repofrompath=coprverify,"$base" --repo=coprverify \
  repoquery --available --latest-limit=1 \
  --qf '%{name} %{evr} %{location}\n' "$pkg" 2>/dev/null \
  | grep -E "^${pkg} .*https?://.*\.rpm$" | grep -v '\.src\.rpm$' | tail -1) || true

if [[ -z $nevra_url ]]; then
  echo "NOT PUBLISHED: no ${pkg} RPM visible in ${owner_project}/${chroot_name}" >&2
  exit 1
fi

nevra=${nevra_url%% *}
url=${nevra_url##* }
echo "== newest published: $nevra"

timeout 300 curl -fsSL -o "$scratch/pkg.rpm" "$url"
echo "== downloaded: $(stat -c %s "$scratch/pkg.rpm") bytes"

# One member only; the payload can be hundreds of MB. Test the OUTPUT, not cpio's
# exit code: a missing member prints noise and leaves an empty file.
extract() { # $1 = member path as cpio sees it ("./usr/...")
  rpm2cpio "$scratch/pkg.rpm" 2>/dev/null \
    | cpio -i --to-stdout --quiet "$1" >"$scratch/shipped" 2>/dev/null || true
}
extract "$rpm_path"

# A member that is a SYMLINK in the RPM extracts to nothing (cpio --to-stdout has
# no data to write), which used to read as "not in the RPM" on a path that is
# present. The omedora payload mirrors omarchy's layout — real files in /usr/bin,
# /usr/share/omarchy/bin/* as symlinks into them — so follow ONE link level and
# extract the target instead.
if [[ ! -s $scratch/shipped ]]; then
  # No `exit` inside awk: that SIGPIPEs rpm and `set -o pipefail` turns the
  # substitution itself into a 141 failure. Read the whole list; keep the first
  # match. (A 247 MB payload lists a few thousand members — cheap.)
  link_target=$(rpm -qp --qf '[%{FILENAMES}\t%{FILEMODES:perms}\t%{FILELINKTOS}\n]' "$scratch/pkg.rpm" 2>/dev/null \
    | awk -F'\t' -v p="/${rpm_path#./}" '{ if (t == "" && $1 == p && $2 ~ /^l/) t = $3 } END { print t }')
  if [[ -n $link_target ]]; then
    echo "== ${rpm_path} is a symlink in the RPM -> ${link_target} (extracting the target)"
    extract "./${link_target#/}"
  fi
fi

if [[ ! -s $scratch/shipped ]]; then
  echo "MISSING: ${rpm_path} is not in ${nevra}" >&2
  exit 1
fi
echo "== extracted ${rpm_path} ($(wc -l <"$scratch/shipped") lines, $(stat -c %s "$scratch/shipped") bytes)"

if [[ -z $local_file ]]; then
  cat "$scratch/shipped"
  exit 0
fi

if diff -u "$local_file" "$scratch/shipped"; then
  echo "IDENTICAL: ${rpm_path} in ${nevra} matches ${local_file}"
else
  echo "DIFFERS: ${rpm_path} in ${nevra} differs from ${local_file}" >&2
  exit 1
fi
