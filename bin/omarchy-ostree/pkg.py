#!/usr/bin/env python3
"""
Immutable (bootc/ostree) package helper for omedora.

Fedora's mutable pkg.py installs/removes RPMs with dnf — which cannot persist
into the read-only /usr of a baked image. On an immutable host the RPM set is
fixed at build time; only Flatpak (which installs to $HOME/.local/share/flatpak
and /var/lib/flatpak) is a live, persistent install target.

On immutable the "installed" test is the same read-only rpm + flatpak query the
mutable helper uses — so present/missing/installed and the add/drop baked-check
delegate to fedora/pkg.py's semantics rather than re-implementing them.

Subcommands (same contract as fedora/pkg.py so the dispatcher wrappers agree):
  present/missing/installed  Read-only rf rpm + flatpak — relay to fedora/pkg.py.
  add <pkg> [<pkg>...]       - already installed (baked rpm / flatpak)  -> OK
                             - source == flathub                         -> flatpak install
                             - source in dnf|copr (missing)              -> tell user to
                               bake it into the image at build; exit 1
                             - source == skip                            -> explain
  drop <pkg> [<pkg>...]      Flatpak apps uninstall; dnf/copr RPMs cannot be
                             removed from a baked image -> message + exit 1

Seams (mirror fedora/pkg.py):
  OMARCHY_FEDORA_MAP, OMARCHY_PKG_DRY_RUN, OMARCHY_PATH (tree root resolution).
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "fedora"))
from package_map import resolve_mapping  # noqa: E402


def _resolve_tree_root() -> Path:
    script_root = Path(__file__).resolve().parent.parent.parent
    candidates = [script_root]
    if os.environ.get("OMARCHY_PATH"):
        candidates.append(Path(os.environ["OMARCHY_PATH"]))
    candidates.append(Path("/usr/share/omarchy"))
    for root in candidates:
        if (root / "install" / "packages" / "fedora.toml").is_file():
            return root
    return script_root


ROOT = _resolve_tree_root()
MAP_PATH = Path(
    os.environ.get("OMARCHY_FEDORA_MAP", ROOT / "install" / "packages" / "fedora.toml")
)
DRY_RUN = bool(os.environ.get("OMARCHY_PKG_DRY_RUN"))
FEDORA_PKG = Path(__file__).resolve().parent.parent / "fedora" / "pkg.py"


def _load_map() -> dict:
    with open(MAP_PATH, "rb") as fh:
        return tomllib.load(fh)


def _relay(fedora_args: list[str]) -> int:
    """Run the mutable helper's subcommands (read-only ones, and the baked-check)."""
    if not FEDORA_PKG.exists():
        print(f"mutable pkg helper missing: {FEDORA_PKG}", file=sys.stderr)
        return 1
    env = dict(os.environ)
    if DRY_RUN:
        env["OMARCHY_PKG_DRY_RUN"] = "1"
    return subprocess.call([sys.executable, str(FEDORA_PKG), *fedora_args], env=env)


def _entry_of(pkg: str) -> tuple[dict | None, bool]:
    return resolve_mapping(pkg, _load_map())


def cmd_present(args: argparse.Namespace) -> int:
    return _relay(["present", *args.pkgs])


def cmd_missing(args: argparse.Namespace) -> int:
    return _relay(["missing", *args.pkgs])


def cmd_installed(args: argparse.Namespace) -> int:
    return _relay(["installed", *args.pkgs])


def cmd_add(args: argparse.Namespace) -> int:
    failed = False
    for pkg in args.pkgs:
        mapping, active = _entry_of(pkg)
        if not active:
            reason = (mapping or {}).get("reason") or "no reason given"
            print(f"skipping '{pkg}' on immutable Fedora: {reason}")
            continue
        source = (mapping or {}).get("source", "dnf")  # absence == plain dnf name
        # Already installed/baked covers both rpm and flatpak and satisfied_by.
        if _relay(["present", pkg]) == 0:
            print(f"'{pkg}' is already baked into the image (or a satisfying flatpak).")
            continue
        if source == "flathub":
            app_id = (mapping or {}).get("app_id")
            if not app_id:
                print(f"flathub entry '{pkg}' has no app_id", file=sys.stderr)
                failed = True
                continue
            print(f"Installing (flatpak, persists on immutable): {app_id}")
            if not DRY_RUN:
                if subprocess.call(["flatpak", "install", "-y", "flathub", app_id]) != 0:
                    failed = True
            continue
        print(
            f"'{pkg}' is not in the image. On an immutable host bake it into the image "
            f"build (fedora.toml / Containerfile) and rebase — dnf install cannot ",
            file=sys.stderr,
        )
        failed = True
    return 1 if failed else 0


def cmd_drop(args: argparse.Namespace) -> int:
    failed = False
    for pkg in args.pkgs:
        mapping, active = _entry_of(pkg)
        source = (mapping or {}).get("source") if active else None
        if source == "flathub":
            app_id = (mapping or {}).get("app_id")
            if app_id:
                print(f"Removing (flatpak): {app_id}")
                if not DRY_RUN and subprocess.call(["flatpak", "uninstall", "-y", app_id]) != 0:
                    failed = True
            continue
        if _relay(["present", pkg]) == 0:
            print(
                f"'{pkg}' is baked into the image and cannot be removed at runtime; "
                f"take it out of the build (fedora.toml / Containerfile) and rebase.",
                file=sys.stderr,
            )
            failed = True
        else:
            print(f"'{pkg}' is not installed.")
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="ostree-pkg")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("present", "missing", "installed", "add", "drop"):
        p = sub.add_parser(name)
        p.add_argument("pkgs", nargs="*")
    args = ap.parse_args()
    fn = {
        "present": cmd_present,
        "missing": cmd_missing,
        "installed": cmd_installed,
        "add": cmd_add,
        "drop": cmd_drop,
    }[args.cmd]
    return fn(args)


if __name__ == "__main__":
    sys.exit(main())
