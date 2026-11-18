#!/usr/bin/env python3
"""Report the merge surface between a fork and an upstream release tag.

Answers the question the fork-maintenance work always starts with: how much of the
upstream delta is my unique work, and how much is two projects having written the
same files? Prints counts, the both-sides file list, fork-only files, the fork's
deletions, and a migration classification.

Usage
-----
  upstream-delta-report.py --fork-dir ~/omedora-inspect \
      --upstream-url https://github.com/AndrewGaspar/omedora.git --tag v0.3.0-beta.1

  # add the two probes (both mutate only the SCRATCH clone):
  upstream-delta-report.py ... --merge-probe --cherry-pick-probe

Why a scratch clone: the merge/cherry-pick probes commit state. The user's clone is
never touched, not even for --merge-probe. All git output is read through pipes into
files/a script, never through a display-captured listing (a 5000-line listing gets
truncated and silently undercounts).
"""
import argparse
import collections
import os
import shutil
import subprocess
import sys
import tempfile


def git(work, *args, check=True):
    r = subprocess.run(["git", "-C", work, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed:\n{r.stderr[:400]}")
    return r.stdout


def paths(work, *args):
    return {l for l in git(work, *args).split("\n") if l.strip()}


def extract(work, rev, subdir, dest):
    """Unpack a subtree (git archive | tar) - robust where cat-file --batch byte
    accounting is easy to get wrong."""
    os.makedirs(dest, exist_ok=True)
    ar = subprocess.run(["git", "-C", work, "archive", rev, subdir], capture_output=True)
    subprocess.run(["tar", "-x", "-C", dest], input=ar.stdout, check=True)
    out = {}
    for root, _dirs, files in os.walk(dest):
        for fn in files:
            fp = os.path.join(root, fn)
            rel = os.path.relpath(fp, dest)
            try:
                out[rel] = open(fp, encoding="utf-8", errors="replace").read()
            except OSError:
                pass
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fork-dir", default=os.path.expanduser("~/omedora-inspect"))
    ap.add_argument("--upstream-url", default="https://github.com/AndrewGaspar/omedora.git")
    ap.add_argument("--tag", required=True, help="upstream release tag, e.g. v0.3.0-beta.1")
    ap.add_argument("--branch", default=None, help="fork branch to analyse (default: its HEAD)")
    ap.add_argument("--scratch", default=None, help="scratch clone dir (default: a temp dir)")
    ap.add_argument("--danger-tokens", default="pacman,mkinitcpio,limine,bootctl,snapper,"
                                              "kernel-install,systemd-boot,grub,omarchy-pkg-add,bootc,rpm-ostree")
    ap.add_argument("--guard-tokens", default="omarchy-distro,ostree-booted,/run/ostree-booted")
    ap.add_argument("--merge-probe", action="store_true", help="also run git merge --no-commit and count conflicts")
    ap.add_argument("--cherry-pick-probe", action="store_true",
                    help="also try the pure-fork commits on the tag (they mostly will not apply)")
    args = ap.parse_args()

    scratch = args.scratch or tempfile.mkdtemp(prefix="fork-delta-")
    if os.path.isdir(scratch) and not args.scratch:
        shutil.rmtree(scratch)
    if not os.path.isdir(os.path.join(scratch, ".git")):
        clone = ["git", "clone", "-q"]
        if args.branch:
            clone += ["--branch", args.branch]
        clone += [args.fork_dir, scratch]
        subprocess.run(clone, check=True)
    git(scratch, "fetch", "-q", "--no-tags", args.upstream_url,
        f"+refs/tags/{args.tag}:refs/tags/up-{args.tag}")
    tagc = git(scratch, "rev-parse", f"up-{args.tag}^{{commit}}").strip()
    fork = git(scratch, "rev-parse", "HEAD").strip()
    mb = git(scratch, "merge-base", "HEAD", tagc).strip()

    up_changed = paths(scratch, "diff", "--name-only", mb, tagc)
    fork_changed = paths(scratch, "diff", "--name-only", mb, "HEAD")
    both = up_changed & fork_changed
    fork_files = paths(scratch, "ls-tree", "-r", "--name-only", "HEAD")
    up_files = paths(scratch, "ls-tree", "-r", "--name-only", tagc)
    fork_only = fork_files - up_files
    fork_deleted = {l.split("\t")[1] for l in git(scratch, "diff", "--name-status", mb, "HEAD").splitlines()
                    if l.startswith("D\t")}

    print(f"# fork delta report — {os.path.basename(args.fork_dir.rstrip('/'))} vs {args.tag}")
    print(f"\nfork HEAD {fork[:8]} | tag {tagc[:8]} | merge-base {mb[:8]}")
    print(f"upstream-changed files {len(up_changed)} | fork-changed {len(fork_changed)} | BOTH {len(both)}")
    print(f"fork-only files {len(fork_only)} | files the fork deleted {len(fork_deleted)}")
    for area, n in collections.Counter(f.split("/")[0] for f in both).most_common(12):
        print(f"    both-sides {n:>4}  {area}/")
    for area, n in collections.Counter(f.split("/")[0] for f in fork_only).most_common(10):
        print(f"    fork-only  {n:>4}  {area}/")

    # ---- commit classification: pure-fork vs overlapping -------------------
    log = git(scratch, "log", "--no-merges", "--format=@@%H", "--name-only", f"{mb}..HEAD")
    commits, cur = [], None
    for line in log.split("\n"):
        if line.startswith("@@"):
            cur = {"sha": line[2:], "files": []}
            commits.append(cur)
        elif line.strip() and cur is not None:
            cur["files"].append(line.strip())
    pure = [c for c in commits if c["files"] and not (set(c["files"]) & up_changed)]
    print(f"\nfork commits since the fork point {len(commits)} | pure-fork {len(pure)} | overlapping {len(commits) - len(pure)}")

    # ---- migrations --------------------------------------------------------
    mig = {l.split("\t")[1] for l in git(scratch, "diff", "--name-status", mb, tagc, "--", "migrations/").splitlines()
           if l.startswith("A\t")}
    if mig:
        blobs = extract(scratch, tagc, "migrations", tempfile.mkdtemp(prefix="mig-"))
        danger = [t for t in args.danger_tokens.split(",") if t]
        guards = [t for t in args.guard_tokens.split(",") if t]
        gated, traps, benign = [], [], []
        for f in sorted(mig):
            body = blobs.get(f, "")
            if any(x in body for x in guards):
                gated.append(f)
            elif any(x in body for x in danger):
                traps.append(f)
            else:
                benign.append(f)
        print(f"\nnew upstream migrations {len(mig)} | already guarded {len(gated)} | "
              f"DANGER (need bake-or-guard) {len(traps)} | spot-check {len(benign)}")
        for f in traps:
            print(f"    {f}")

    # ---- optional: what a plain merge would cost ---------------------------
    if args.merge_probe:
        subprocess.run(["git", "-C", scratch, "merge", "--no-commit", "--no-ff", tagc],
                       capture_output=True, text=True)
        st = git(scratch, "status", "--porcelain")
        codes = collections.Counter()
        areas = collections.Counter()
        for line in st.splitlines():
            code = line[:2].strip()
            if code in ("UU", "AA", "DU", "UD", "AU", "UA"):
                codes[code] += 1
                areas[line[3:].split("/")[0]] += 1
        print(f"\nmerge conflicts {sum(codes.values())}: " + " ".join(f"{k} {v}" for k, v in codes.most_common()))
        print("  by area: " + " ".join(f"{k} {v}" for k, v in areas.most_common()))
        subprocess.run(["git", "-C", scratch, "merge", "--abort"], capture_output=True)

    if args.cherry_pick_probe and pure:
        clean = 0
        for c in pure:
            git(scratch, "checkout", "-q", "-B", "probe", tagc)
            git(scratch, "reset", "-q", "--hard", tagc)
            subprocess.run(["git", "-C", scratch, "cherry-pick", "--no-commit", c["sha"]],
                           capture_output=True)
            if not git(scratch, "diff", "--name-only", "--diff-filter=U", check=False).strip():
                clean += 1
            subprocess.run(["git", "-C", scratch, "cherry-pick", "--abort"], capture_output=True)
            git(scratch, "reset", "-q", "--hard", tagc)
        git(scratch, "checkout", "-q", "-B", "fork-report", fork)
        print(f"\npure-fork commits that cherry-pick cleanly onto the tag: {clean}/{len(pure)}")
        print("  (the rest are modify/delete for files the tag does not have: COPY those files, do not cherry-pick them)")

    print(f"\n[scratch clone: {scratch}]", file=sys.stderr)


if __name__ == "__main__":
    main()
