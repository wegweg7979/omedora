#!/usr/bin/env python3
"""Classify a live ~/.config against the shipped baselines, read-only.

Answers "what did the user actually change from the omarchy defaults?" before any
payload is designed. Prints ADDED (live-only), MODIFIED (differs from /etc/skel, tagged
with whether the shipped default is itself stock-omarchy or a hurunagus/omedora
override), and DELETED (in skel, gone from live).

Usage:
    python3 config-delta.py [--live D] [--skel D] [--omarchy D]

Defaults: ~/.config, /etc/skel/.config, /usr/share/omarchy/config.
ALWAYS `diff -u` each MODIFIED hit before believing it: a byte diff is often upstream
version drift or a theme-generated file, not a user edit (see
references/user-config-delta-capture.md).
"""
import filecmp
import os
import sys
from collections import defaultdict

HOME = os.path.expanduser("~")

# App/runtime/credential state that is never a "look and feel / shell setting".
NOISE = {
    "BraveSoftware", "google-chrome", "google-chrome-beta", "google-chrome-for-testing",
    "google-chrome-unstable", "microsoft-edge", "microsoft-edge-beta", "microsoft-edge-dev",
    "chromium", "mozilla", "pulse", "systemd", "dconf", "gtk-3.0", "gtk-4.0", "ibus", "mozc",
    "fcitx", "fcitx5", "qt6ct", "menus", "glib-2.0", "goa-1.0", "evolution", "nautilus",
    "obsidian", "opencode", "herdr", "gsconnect", "libvirt", "var", "user-share",
    "gnome-initial-setup-done", "rclone", "rclone-browser", "GIMP", "tiling-assistant",
}
# Backup suffixes adopt-user / omarchy-refresh leave behind — never capture them.
BACKUP_MARKERS = (".pre-omedora-", ".pre-hurunagus-", ".bak.")


def parse_args(argv):
    opts = {"live": os.path.join(HOME, ".config"),
            "skel": "/etc/skel/.config",
            "omarchy": "/usr/share/omarchy/config"}
    for flag, key in (("--live", "live"), ("--skel", "skel"), ("--omarchy", "omarchy")):
        if flag in argv:
            opts[key] = argv[argv.index(flag) + 1]
    return opts


def read_tree(root):
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            if os.path.islink(full):
                out[rel] = ("link", os.readlink(full))
            else:
                try:
                    out[rel] = ("file", os.path.getsize(full))
                except OSError:
                    out[rel] = ("err", 0)
    return out


def same_file(a, b):
    a_link, b_link = os.path.islink(a), os.path.islink(b)
    if a_link and b_link:
        return os.readlink(a) == os.readlink(b)
    if a_link or b_link:
        return False
    try:
        return filecmp.cmp(a, b, shallow=False)
    except OSError:
        return False


def main():
    opts = parse_args(sys.argv[1:])
    live, skel, omarchy = (read_tree(opts["live"]), read_tree(opts["skel"]),
                           read_tree(opts["omarchy"]))

    added, modified = defaultdict(list), defaultdict(list)
    for rel in sorted(live):
        top = rel.split("/")[0]
        if top in NOISE or any(m in rel for m in BACKUP_MARKERS):
            continue
        if rel not in skel:
            added[top].append(rel)
            continue
        if same_file(os.path.join(opts["live"], rel), os.path.join(opts["skel"], rel)):
            continue
        # Is the shipped default itself stock omarchy, or already a fork override?
        if rel in omarchy:
            skel_equals_omarchy = same_file(os.path.join(opts["skel"], rel),
                                            os.path.join(opts["omarchy"], rel))
        else:
            skel_equals_omarchy = None  # not in omarchy's payload at all
        tag = ("hurunagus+user" if skel_equals_omarchy is False
               else "omarchy-default" if skel_equals_omarchy
               else "not-in-omarchy")
        modified[top].append((rel, tag))

    print("##### ADDED (in live, absent from shipped skel) #####")
    for top in sorted(added):
        print(f"\n## {top}/  ({len(added[top])})")
        for rel in added[top][:25]:
            print("   +", rel)
        if len(added[top]) > 25:
            print(f"   ... +{len(added[top]) - 25} more")

    print("\n\n##### MODIFIED (differ from shipped skel) — diff each one #####")
    for top in sorted(modified):
        print(f"\n## {top}/  ({len(modified[top])})")
        for rel, tag in modified[top]:
            print(f"   M [{tag}] {rel}")

    print("\n\n##### DELETED (in skel, missing from live) #####")
    missing = defaultdict(list)
    for rel in sorted(skel):
        if rel.split("/")[0] in NOISE or any(m in rel for m in BACKUP_MARKERS):
            continue
        if rel not in live:
            missing[rel.split("/")[0]].append(rel)
    for top in sorted(missing):
        print(f"## {top}/  ({len(missing[top])})")
        print("\n".join(f"   - {rel}" for rel in missing[top][:15]))


if __name__ == "__main__":
    main()
