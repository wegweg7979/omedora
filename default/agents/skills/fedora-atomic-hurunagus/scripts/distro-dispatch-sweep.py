#!/usr/bin/env python3
"""Classify every distro-dispatch site in a tree, for the omedora re-port sweep.

Usage: distro-dispatch-sweep.py [repo] [rev]

Prints the sites grouped by what happens on `fedora-ostree`:

  A) `case ... fedora) exec .../fedora/<helper>`  -> on fedora-ostree the arm does NOT
     match and execution FALLS THROUGH TO THE ARCH BODY (pacman/yay). Each needs a
     `fedora-ostree)` arm: same fedora/ helper when the body only writes /etc or reads
     the package db; `omarchy-ostree/pkg.py <verb>` for the package family; a refusal
     when there is nothing to install into a read-only /usr.
  B) `== "fedora"` comparisons                 -> FALSE on the image, so Fedora-isms
     silently do not run. Extend to `== fedora || == fedora-ostree` where the Fedora
     behaviour is wanted on the image.
  C) inverted (`== fedora || exit/return`)     -> runs on non-Fedora only; usually fine.
  D) `!= "arch"` comparisons                   -> TRUE on the image and usually CORRECT
     ("runs on non-arch"); do NOT "fix" these. `!= "fedora"` is the opposite case.

Read-only: opens files from the worktree, runs no mutating command. Cite the site count
in the plan so the sweep is auditable, then verify with `bash -n` plus the read-only
paths only (`omarchy-pkg-present`, the refusals) under OMARCHY_DISTRO=fedora-ostree.
"""
from __future__ import annotations

import collections
import os
import re
import subprocess
import sys

REPO = sys.argv[1] if len(sys.argv) > 1 else "."
REV = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
SKIP = (".git/", "themes/", "test/", "docs/", "shell/", "applications/",
        "omedora/packaging/", "migrations/")

EXEC_ARM = re.compile(r"fedora\)\s*(exec|$)")
COMPARE = re.compile(r'==\s*"?fedora"?')
INVERTED = re.compile(r"\|\|\s*(exit|return)")
NOT_ARCH = re.compile(r'!=\s*"?arch"?')


def tracked_files(repo: str, rev: str) -> list[str]:
    out = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", rev],
                         capture_output=True, text=True, check=True).stdout
    return [p for p in out.split("\n") if p and not p.startswith(SKIP)]


def main() -> int:
    arms, compares, inverted, not_arch = [], [], [], []
    for path in tracked_files(REPO, REV):
        try:
            lines = open(os.path.join(REPO, path), encoding="utf-8", errors="replace").read().split("\n")
        except OSError:
            continue
        if "fedora" not in "\n".join(lines) and "OMARCHY_DISTRO" not in "\n".join(lines):
            continue
        for i, line in enumerate(lines):
            s = line.strip()
            if s.startswith("#"):
                continue
            ctx = "\n".join(x.strip() for x in lines[i:i + 3])
            if EXEC_ARM.search(s) and "fedora/" in ctx and "fedora-ostree" not in ctx:
                target = re.search(r"/fedora/([A-Za-z0-9._-]+)", ctx)
                arms.append((path, i + 1, target.group(1) if target else "?"))
            elif COMPARE.search(s) and "fedora-ostree" not in s:
                (inverted if INVERTED.search(s) else compares).append((path, i + 1, s[:100]))
            elif NOT_ARCH.search(s) and "fedora-ostree" not in s:
                not_arch.append((path, i + 1, s[:100]))

    def dump(title: str, rows, note: str) -> None:
        print(f"\n=== {title} ({len(rows)}) ===\n{note}")
        for row in sorted(rows):
            print("   " + "  ".join(str(x) for x in row))

    dump("A) case arms exec'ing an upstream fedora/ helper", arms,
         "   -> falls through to the ARCH body on fedora-ostree; add a fedora-ostree) arm")
    dump("B) '== fedora' comparisons (not inverted)", compares,
         "   -> false on the image; extend where the Fedora behaviour is wanted there")
    dump("C) inverted '== fedora || exit/return'", inverted,
         "   -> runs on non-Fedora only; usually correct")
    dump("D) '!= arch' comparisons", not_arch,
         "   -> TRUE on the image and usually CORRECT; do not 'fix' these")

    print(f"\ntotals: A {len(arms)}, B {len(compares)}, C {len(inverted)}, D {len(not_arch)}")
    by_file = collections.Counter(p for p, *_ in arms + compares)
    print("files touched most (A+B):", dict(by_file.most_common(10)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
