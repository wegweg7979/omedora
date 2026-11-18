# Keeping the omedora fork current (upstream delta analysis + re-port)

The fork is `wegweg7979/omedora` (branch `omedora-4`); upstream is
`AndrewGaspar/omedora`, SAME branch name, "No fuss Omarchy-on-Fedora!". The
inspection clone is `~/omedora-inspect` (HEAD = the commit the booted image
bakes, e.g. `git2c68f33`). The fork serves its own COPR (`wegweg7979/omedora-4`),
so the fork's version — not upstream's — is what the images consume.

## Procedure (in this order)

1. **Survey read-only.** `git fetch --no-tags https://github.com/AndrewGaspar/omedora.git omedora-4`
   writes `FETCH_HEAD` only — no remote, no branch, nothing in the user's clone config.
2. **Read upstream's `omedora/CHANGELOG.md` first.** One `## vX.Y.Z — date (Omarchy A.B.C)`
   section per release, each with a prose digest plus the commit list; that IS the summary
   (per-commit subjects are ~60% unprefixed noise and the history includes vendored Omarchy
   commits, e.g. 403 DHH ones).
3. **Measure against the TAG, not the branch tip.** Upstream keeps pushing XR snapshot
   bumps after tagging, so a tip is a moving target; the release tag is a fixed decision
   point. Also pin the merge target by sha, not by tag *name* (`git fetch ... +refs/tags/vX:refs/tags/up-vX`
   then `rev-parse up-vX^{commit}`) — a bare `git show vX:path` against a clone that only has
   `FETCH_HEAD` fails with `invalid object name`, which silently reads as "the file is empty".
4. **Do the whole analysis in ONE sequential script** (`scripts/upstream-delta-report.py`).
   See the measurement traps below — this step is where the numbers go wrong.
5. **Decide merge vs re-port from two numbers:** how many fork commits are *pure* (touch only
   files upstream does not have) versus how many files BOTH sides changed. See the decision rule.
6. **Deliver the plan as a file in the fork** (`PLAN-<version>-delta.md`, uncommitted, for
   review) with per-phase items and one-line reasons; then execute on a branch off the tag,
   one commit per phase, verifying each. Pushing the work branch is fine once the workflow
   triggers are checked (SKILL.md §"Pushing a work branch"); the default branch is untouchable
   from a side branch, but stop before anything that PUBLISHES.

## Measurement traps (these produced wrong numbers once)

- **Never count a git listing that came back through a tool capture.** A
  `git diff --name-only` over a 3-month upstream delta is thousands of lines and the capture
  truncates it, so `set(...split("\n"))` silently undercounts — that is how "357 files changed
  on both sides" was reported when the real figure is **828**. Write listings to a file (or run
  inside a script with `capture_output=True`) and count from disk.
- **Never fan out parallel git commands against one clone.** 40 concurrently-issued git calls
  on a single worktree race on `.git/index.lock` (`fatal: Unable to create ... index.lock`) and
  half of them fail — and the partial failures hide which numbers are trustworthy.
- **Do not parse `git cat-file --batch` by hand.** Its header size is BYTES, not lines, so
  line-based body accounting walks off into unrelated records. To read many files at a revision,
  `git archive <rev> <dir>` and `tar -x` into a temp dir, then read them normally.
- **`git diff --name-only <tag>...<branch>` direction matters.** `HEAD...origin/main` in a
  `git status` sense is not `git diff --stat A B`; state which side is which before quoting a
  number.

## Release-mechanism pitfall (cost a wrong answer to the user)

**Upstream releases by annotated tag + COPR build, NOT GitHub Releases.** Its Releases page
stops at `v0.1.8`; the 4.5 work exists as tag `v0.3.0-beta.1` → commit `5ecb9a6`, published to
`agaspar/omedora-4` as `omedora-0:0.3.0~beta.1-…git5ecb9a6` for **both** fedora-44 and fedora-45,
along with the 4.5 base apps (omasnap 1.24.0, owe 0.2.12, hype 0.6.0, monologue 0.3.1,
signed 0.3.1, disktree 0.11.0) and kitty 0.50.0. So do NOT conclude "nothing released for
Omarchy 4.5 yet" from the Releases page or from a quiet `pushed_at`; check
`git ls-remote --tags <upstream>` and the COPR repo metadata
(`dnf5 repoquery --repofrompath=…,https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-<ver>-x86_64/ --repoid=… <pkg>`).
The daily `Sync translations` workflow being red is an upstream bot job, not a signal that the
release is unfinished — read `Test` / `COPR build` conclusions instead.

## Decision rule: merge or re-port?

Measure, then choose. If pure-fork commits are few and both-sides files are many, **re-port as a
thin delta on the tag; do not merge.** Merging buys you the fork's unique work at the price of
hand-resolving every conflict — including files where both projects independently wrote the same
thing.

Measured for the 4.0.6 → 4.5.0 move (calibration for the next survey):

| metric | value |
|---|---|
| upstream files changed since the fork point | 4993 |
| fork files changed | 938 |
| **files changed by BOTH** (the merge surface) | **828** |
| fork-side lines changed inside those shared files | 63,563 |
| plain `git merge` <tag> → conflicts | **179** (85 both-modified, 43 both-created, 42 fork-deleted, 9 upstream-deleted) |
| conflicts by area | `bin/` 104, `test/` 66, `default/` 6, `.github/` 2, `config/` 1 |
| cherry-picking the 9 pure-fork commits onto the tag | **2 of 9 clean** — the rest are `modify/delete` (the tag has no such file) → **copy those files, do not cherry-pick** |
| fork-only files | 187 (`bin/` 10, `themes/` 87, `test/` 76, `install/` 3, `shell/` 3, `applications/` 2, `default/` 2, `docs/` 2) |
| files the fork deleted outright (re-assert list) | 118 |
| new upstream migrations | 143 = 35 already guarded + **20 calling `omarchy-pkg-add`** + 88 spot-check |
| migrations both sides changed | 68 = 24 mechanical gates + 44 needing review |
| `install/packages/fedora.toml` | tag 837 lines / ~337 entries vs fork 516 / ~197 → +323/−2 |

The 43 both-created (`AA`) files are the tell that a merge is the wrong frame: both projects
independently wrote `bin/fedora/pkg.py`, `bin/omarchy-distro`, `bin/omedora-copr`,
`bin/omedora-upgrade-fedora`, `bin/omedora-upgrade-to-4`, `bin/omarchy-cmd-default-browser`,
`default/hypr/apps/hermes.lua`, both workflows and ~20 shell tests.

Reading the conflict codes tells you the SHAPE of the divergence, and the two halves need
opposite handling: `DU` (deleted by us) is the fork's own pruning being re-asserted; `UD`
(deleted by them) is upstream retiring something the fork had touched — check the fork's own
call sites before keeping it. "Modify/delete on a file the target base never had" is NOT a
content clash: copy the file.

## Phases of the re-port (branch off the tag, one commit per phase)

One commit per phase, and **write each commit message to a file**, then
`git commit -F <file>`. A multi-line message interpolated into `git commit -m` from Python or a
shell heredoc loses its body: backticks inside it are executed as commands and `\n` stays
literal, so the subject line swallows the whole text. Fixing it afterwards is a `git commit
--amend -F <file>`.

1. **Carry the immutable layer as-is** — copy, do not cherry-pick: `bin/omarchy-ostree/{update,update-available,pkg.py}`,
   `bin/omarchy-system-{logout,reboot,shutdown}` (upstream retired them and the ostree update path
   calls `omarchy-system-reboot`), the fixture-only `test/shell.d/ostree-update-available-test.sh`.
2. **Sweep the distro dispatch** (below).
3. **Migration guards** — the 20 `omarchy-pkg-add` migrations first (they are the boot-time abort),
   then the 24 mechanical gates, then the 44 upstream rewrites. Script the guard transform
   (idempotent, `--dry-run`) instead of hand-editing 92 files, and show its intended diff on a few
   files before applying.
4. **Re-assert the prune** from the `git diff --diff-filter=D` list, plus `bin/omarchy`'s
   `GROUP_DESCRIPTIONS` (coupled to the pruned command list) and the COPR `SPECS` prune.
5. **Packaging** — take upstream's `fedora.toml` and re-apply the fork's extra entries; the 4.5
   base apps; the 4.5 drop-ins (mise, XKB, sudo timeout, WirePlumber camera, docker-group change).
6. **Identity payload** — the fork-only `themes/`, `install/`, `applications/`, `default/`, `docs/`,
   plus the hurunagus payload in the image repo.
7. **Gates** — upstream's test suite, then the fork's own gates, then the COPR build for f44+f45,
   then an image build with the baked-NEVRA check, then a VM boot, then a non-primary box.

## The dispatch sweep (phase 2) — run `scripts/distro-dispatch-sweep.py`

Every `OMARCHY_DISTRO` / `fedora` site in the tree, classified. The sweep on 4.5 found 157 sites;
the non-migration ones fall into four groups with different right answers:

- **`case … fedora) … exec "$(dirname …)/fedora/<helper>"`** — the DANGEROUS group. On
  `fedora-ostree` the arm does not match, so execution **falls through to the ARCH body
  (pacman/yay)**. Add a `fedora-ostree)` arm. Which target depends on what the helper does:
  - send it to the **same** `fedora/` helper when the body only writes `/etc` (persistent under
    bootc) or reads the RPM/flatpak db: `omarchy-apply-lock` → `fedora/setup-lock` (writes
    omarchy-namespaced PAM files only), `omarchy-locale-generate`, `omarchy-remove-security-fido2`,
    `omarchy-remove-security-fingerprint`;
  - send it to the **ostree sibling** for the package family: `omarchy-pkg-present|missing` →
    `omarchy-ostree/pkg.py <verb>` (relays the read-only query against the BAKED set),
    `add|drop` → the same sibling (flatpak-or-bake semantics);
  - `omarchy-pkg-aur-add` → `omarchy-ostree/pkg.py add`: on Fedora the AUR tier fallback IS
    `add`, so the immutable "flatpak it or bake it" answer is the correct equivalent, not a refusal;
  - **refuse** where there is nothing to install into a read-only `/usr`:
    `omarchy-pkg-install`, `omarchy-pkg-remove` (point at the build), `omarchy-update-system-pkgs`
    (point at `omarchy update`). Exit 1 BEFORE reaching fzf/pacman/dnf.
- **`== "fedora"` comparisons** — the SILENT group: false on the image, so Fedora-isms quietly do
  not happen. Extend to `== "fedora" || == "fedora-ostree"`. Which ones matter is not obvious from
  the name — extend `omarchy-migrate` (skip the pacman-lock wait), `omarchy-provision-user` (the
  Fedora coexistence shims: default apps, powerprofilesctl/tensaku-edit shims, nvim bootstrap),
  `omarchy-system-lock`, `install/user/{mise-work,xcompose,nvim-fedora}.sh` (mise-work's Arch branch
  would hard-fail the ISO-style path), and the fastfetch About line (it printed the Arch string).
- **`!= "arch"` comparisons are usually CORRECT** — they mean "runs on non-arch", which on
  `fedora-ostree` is what you want. Do not "fix" them. `!= "fedora"` is the opposite and does need
  extending.
- **Leave alone, with the reason recorded**: `bin/omarchy-update`'s Fedora branch (dead code — the
  dispatch arm execs the sibling first), `omarchy-update-confirm`/`-restart` (Arch pipeline; the
  sibling never calls them — re-check only if the menu exposes them), the installer-only
  `install/config/*` + `install/hardware/*` (never run on the image), and the os-release
  `ID=fedora` readers (`omedora-copr`, `omedora-upgrade-fedora`) which need no change because
  bootc still ships `ID=fedora`.

`bin/omarchy-ostree/pkg.py` mirrors `bin/fedora/pkg.py`'s verb contract on purpose
(`present`/`missing`/`installed` relay the mutable query; `add`/`drop` are flatpak-or-refuse), and
it imports `resolve_mapping` from `bin/fedora/package_map.py` via `sys.path.insert(…/fedora)` — so
carrying the sibling means carrying its `bin/fedora/` sibling too.

Verification for the sweep: `bash -n` every touched shell file, JSON-validate the JSONC, and run
ONLY the read-only or refusing paths live under `OMARCHY_DISTRO=fedora-ostree`
(`omarchy-pkg-present bash` → rc 0, `present bogus` → rc 1, `add bash` → "already baked",
`drop bash` → cannot-remove + rc 1, the three refusals → rc 1). Never run `omarchy-migrate`,
`omarchy-apply-lock` or `omarchy-locale-generate` as a test — they write `/etc`.

**Editing the fastfetch JSONC line: escape the ADDED fragment at the same level as its
neighbours.** The `"text"` value is a shell one-liner inside a JSON string, so every `"` in the new
`|| "$(omarchy-distro …)" == fedora-ostree` fragment needs `\"`. Inserting raw quotes breaks the
string, and a naive `json.loads` after stripping `//` will not tell you (it also strips `https://`
inside strings) — validate by dropping only comment-ONLY lines, then parse.

## Porting rules per file (each cost time)

- **Take upstream's body; re-apply ONLY the fork's change.** Diff the fork against the tag
  per file and read every hunk — some of those hunks are the fork *lacking* an upstream
  improvement, and carrying them is a regression. Real instances:
  `bin/omarchy-version-channel` needed only the `fedora|fedora-ostree` arm (its ARM-aware mirror
  regex is upstream's improvement); `bin/omarchy-pkg-drop` needed only the arm (upstream's
  `pacman -Qq` error handling + `EUID` root check are newer than the fork's rewrite);
  `omarchy-show-done $?` → `omarchy-show-done` in the fork is unrelated drift.
- **`bin/omarchy`'s `GROUP_DESCRIPTIONS` pruning is coupled to the pruned command list** —
  upstream adds groups every release, so re-apply those deletions in the PRUNE phase
  (from the `git diff --diff-filter=D` list), never carry the whole file.
- **`bin/omarchy-update-status`: the fork's version reverts upstream's newer "just clear the
  indicator" implementation.** Prefer upstream's; carry the revert only if the bar badge
  genuinely needs the refresh call.
- **The migrations that call `omarchy-pkg-add` ARE the gate list.** Grep the new migrations for
  `omarchy-pkg-add` (and `pacman`) rather than reading all 143; each one needs either the
  package baked (`EXCLUDED_PACKAGES` / the map) or the `fedora-ostree` guard, and the Arch-only
  ones (pacman repo config, `xorg-xsetroot`, `omarchy-hyprland-titlebars`, Gliff/aarch64) are
  skipped on Fedora. A migration's first non-shebang `#` line is a usable one-line description
  when building the decision table.
- **Sibling commands executed by a glass of the dispatch arm must exist on the new base.**
  The ostree update path calls `omarchy-system-reboot`, which upstream retired — so the port
  carries `bin/omarchy-system-{logout,reboot,shutdown}` or retargets the ~6 call sites.
- **A fork file upstream REPLACED with a differently-named one is not "deleted" — carrying it
  reverts the new design.** `install/user/git.sh` is gone from 4.5, but
  `install/user/first-run/git.sh` is its successor: the fork's version wrote `user.name`/
  `user.email` unconditionally from the install-input env vars, whereas 4.5 checks whether a
  global identity already exists and otherwise raises a first-run notification that launches
  `omarchy-setup-git`. The absence of the old path on the target is therefore NOT the test —
  query the tag for the same JOB under another name
  (`git ls-tree -r --name-only <tag> | grep -i <topic>`, then read the candidate) before
  ruling a fork file droppable.
- **Verify a fork-only helper has a CALLER on the target tree before carrying it.**
  `install/config/fix-powerprofilesctl-shebang.sh` is fork-only with zero references anywhere
  in 4.5's `install/`, `bin/`, `default/` — carrying it ships dead code.
  `git grep -n '<basename>' <tag> -- install/ bin/ default/` is the check; an empty result
  means drop.

## Where the 4.5 port got to

Branch `omedora-4.5` — **twelve commits on tag `v0.3.0-beta.1` (`5ecb9a6`), pushed to `origin`
(`3d3e8a85b`); `omedora-4` still at `2c68f335`, untouched.** All seven phases are done, and the
COPR side is done with them: dispatching `copr-build.yml` on the branch with an explicit package
list published all eight names for f44+f45 (`omedora`/`omedora-settings` at
`0.3.0~beta.1-1.202611111733gite6cd77e`, plus `omasnap 1.24.0 owe 0.2.12 hype 0.6.0
monologue 0.3.1 signed 0.3.1 disktree 0.11.0`). The image half is the PR
`wegweg7979/hurunagus-hyprland#3` (`main` ← `omedora-4.5-base`, 4 commits, green PR build,
MERGEABLE/CLEAN) — **merged 2026-11-11 as squash `992f85b27`**, and the image it built
(`run 43101357111`, digest `sha256:feb90a9a…`, signed) is published as `latest` +
`latest.20261111` with `omedora`/`omedora-settings 0.3.0~beta.1-1.202611111733gite6cd77e`
baked from the fork's COPR. **A VM boot of that image validated the whole port** (4.5 loaded,
the baked apps present, `omarchy update` succeeding), a second boot of the republished image
(`git3d3e8a8`, rechunked) confirmed the dangling-reference fixes (no nvidia module error), a third
(`git56ea396`) carried the pkg-helper skip fix, and the fourth (`6ad8d5a58`, `latest.20261112`) ran the
**full migration queue to the end** - so the 4.5 base is proven on real boot with migrations complete,
not just in CI. Remaining: rolling the other boxes over (pending, user's),
and the fork's own `omedora-4` branch
still sits on base 4.0.6 / `0.2.0-beta.9` while the COPR publishes 4.5 — deciding how
the branch line catches up is an open question, not a pending task.

- `phase 1` — carried as-is: `bin/omarchy-ostree/{update,update-available,pkg.py}`,
  `bin/omarchy-system-{logout,reboot,shutdown}`, `test/shell.d/ostree-update-available-test.sh`;
  merged (upstream body + one arm each): `bin/omarchy-distro` (the `fedora-ostree` token +
  `OMARCHY_OSTREE_MARKER`), `bin/omarchy-update`, `bin/omarchy-update-available`,
  `bin/omarchy-version` (+ the fork's branding), `bin/omarchy-version-channel`.
- `phase 2` — the dispatch sweep: 13 arms (9 routed, 3 new refusals, plus the one from phase 1),
  7 comparisons extended.
- `phase 3` — 60 migration gates turned into pattern compares (`== "fedora"` → `== fedora*`).
- `phase 4` — the prune re-asserted (110 files) plus the pruned feature set (52 XR/openclaw/
  hyprpad), COPR `SPECS` pruned (44 names re-verified present; the 4.5 app specs KEPT — they are
  the bake path for the phase-3 worklist), `omarchy-menu.jsonc` −41 rows (383 valid rows, no
  double commas), the `run_logged` lines whose targets are gone dropped from `install/*/all.sh` +
  `omarchy-reinstall-configs`, and `default/systemd/user/omarchy-recover-internal-monitor.service`
  `git rm`'d (a fork bug: its `ExecStart` named a command the prune had deleted).
  **This phase also closed a phase-2 gap: 14 `case … fedora)` arms whose body is INLINE, not an
  `exec` of a `fedora/` helper** (`channel-current`/`channel-set`, `debug`, `install-and-launch`,
  `pkg-aur-accessible`/`-install`, `reinstall-configs`, `setup-security-fingerprint`,
  `update-{aur-pkgs,keyring,orphan-pkgs,pkg-prune,time}`, `version-pkgs`) — mirrored to
  `fedora-ostree`. A sweep keyed on `exec` cannot see that class; grep `^\s*fedora)` inside the
  `case` blocks as well.
- `phase 5` — packaging followed upstream: its `install/packages/fedora.toml` is a SUPERSET
  (176 entries vs the fork's 106, zero fork-only), so nothing needed re-applying and all 20
  migrations' packages resolve. Tidy-ups: `omarchy-provision-owner.service`'s `After=` reduced to
  `systemd-user-sessions.service`.
- `phase 6` — payload: 87 theme files (verified complete), `docs/AUDIO-TUNING.md`,
  `docs/migrations.md`, the old plan doc. REFUSED: the 7 voxtype shims and the 6 files upstream
  deleted in 4.5 (`NotificationLogic.js`, `NotificationCard.qml`, two retired `.desktop` files,
  `xournalpp/settings.xml`, `qemu.lua`) — resurrecting removed code is the failure mode.
- Branch total: **365 files, +1454/−12,589** vs the tag. `PLAN-4.5-delta.md` is committed with it
  so the branch documents its own reasoning.
- Image-repo handoff: branch **`omedora-4.5-base`** in `~/hurunagus-hyprland`, two commits — the
  map+list move, then the dead `EXCLUDED_PACKAGES` cleanup — 3 files, +358/−21, `main` left at
  `55b2c72`, unpublished, patch re-tested with `git apply --check` against a fresh clone of `main`.
  This repo's `build.yml` is `branches: [main]`, so the branch is inert until it is merged.
- Decisions: adopt 4.5's voxtype path and retire the fork's shims (the PACKAGE stays); keep
  `bin/omarchy-system-*`; keep upstream's `update-status`; fixture-only/static tests; drop
  `install/user/git.sh` (superseded by `first-run/git.sh`) and
  `install/config/fix-powerprofilesctl-shebang.sh` (no caller).
- Verified: `bash -n` on every touched shell file, `py_compile` on `pkg.py`, the distro token in all
  four cases (marker present / **explicitly empty** / arch / unset), the carried fixture test 6/6,
  live read-only dispatcher + pkg-verb runs under `OMARCHY_DISTRO=fedora-ostree`, and the 44 COPR
  SPECS names confirmed to exist.
- **Phase 7 (user):** COPR dispatch with an EXPLICIT spec list (`omedora omedora-settings` first,
  then `omasnap owe hype monologue signed disktree` once the stack they need is green — a blank
  dispatch builds nothing) → image build + baked-NEVRA check → the image repo's package list →
  VM boot → a non-primary box. **Check the COPR's actual build state before an image build**, with
  the public API rather than a guess: `curl -s 'https://copr.fedorainfracloud.org/api_3/build/list/?ownername=<o>&projectname=<p>&limit=8'`
  lists each recent build's package and chroots. For 4.5 it showed only `omedora` and
  `omedora-settings`, i.e. the six app specs had never been built — which is exactly the set an
  image build would abort on, so the dispatch is a hard prerequisite, not a nicety.

### An image-side exclusion can break a migration too

Same class as the skip entry, one layer out: the *image* excludes a package (its own
`EXCLUDED_PACKAGES` in `build_files/build.sh`) while upstream ships a migration whose entire body
is `omarchy-pkg-add <that package>`. The call hits the bake-it refusal, exits 1, and `set -e` takes
the rest of the migration run down with it - the VM stopped at `1790539857` "Install Monologue".
Exactly three migrations are affected (`hype`, `monologue`, `signed`), and all three are
`if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then omarchy-pkg-add <app>; fi`, i.e.
nothing *after* the add, so touching their markers loses nothing on this line.

Upstream's contract is "ship the preinstalls, honour a user who removed them". That works on mutable
Fedora; on an immutable image it is broken from both ends, because `omarchy-pkg-drop` also refuses to
remove a baked RPM - so excluding the three would not have made them removable, only absent, at the
cost of a stalled queue. Decision taken: **bake them** (they are published in the COPR for f44/f45),
which is one line in the image repo instead of teaching two layers about image-side exclusions.
The general rule for next time: before excluding a name the base list carries, check
`git grep -l "omarchy-pkg-add.*\b<name>\b" <branch> -- migrations/` - if a migration adds it, the
exclusion is not a size saving, it is a migration outage.

### The immutable pkg helper must mirror the mutable helper's skip handling

First real 4.5 migration run on the image stopped after ~10 of 102:

```
'owe-lockfeed' is not in the image. On an immutable host bake it into the image
build (fedora.toml / Containerfile) and rebase - dnf install cannot
```

`bin/omarchy-ostree/pkg.py`'s `cmd_add` only special-cased `not active` (the since/until filter), so
a **`skip` entry — which is active and is never present** — fell through to the bake-it message and
`exit 1`. The mutable `bin/fedora/pkg.py` documents the case (`is_entry_installed` returns False for a
skip entry on purpose) and its own `add` collects skip entries and *warns* instead of failing. Mirror
that: report the skip, continue, exit 0. Six pending migrations were failing this way (`owe-lockfeed`,
`base-devel`, `asus-proart-p14-speaker-firmware`, `omarchy-hyprland-titlebars`, `gliff` x2).

Two consequences worth knowing:

- **`omarchy-migrate` is `set -euo pipefail` and runs migrations in filename order, so the first
  failure aborts every later one.** One bad package name can hide ~90 migrations. When a VM reports
  "N tried, ~10 went through then failed", that is this shape, not a corrupt migration set.
- **A migration is marked complete only *after* it succeeds** (`bash -euo pipefail "$file"` then
  `touch "$marker"`), so re-running `omarchy-migrate` resumes at the failure, and the first entry in
  `omarchy-migrate --pending` is exactly the culprit. Markers live in
  `$HOME/.local/state/omarchy/migrations/` (`$OMARCHY_MIGRATION_STATE` overrides); touching the
  marker for a no-op migration unblocks the backlog without waiting for a rebuild - but re-run by hand
  whatever sat *after* the failing line in that migration, since a failure skips the rest of its body.

Reproduce any of this locally before rebuilding: this host is itself immutable, so
`OMARCHY_PATH=$PWD python3 bin/omarchy-ostree/pkg.py add <name>` exercises the real path (run it from
inside `bin/omarchy-ostree/` - the script resolves its `fedora/` sibling from its own directory, so a
copy in `/tmp` cannot import it). A skip-mapped name is safe to probe (no installs); avoid probing
flathub-mapped names, which would really install.

### Upstream's additions can reference what the fork pruned

This is the one that reaches the running desktop. A 4.5 VM session came up with Hyprland config
errors naming nvidia: `default/hypr/envs.lua` did `require("default.hypr.nvidia")` while
`default/hypr/nvidia.lua` is in the fork's prune set. The Lua loader fails on the missing module
and the `hl.config` block *below* the require never applies, so it breaks behaviour, not just logs.

Taking upstream's file body wholesale is what brings the call along, and it cannot be found by a
diff/rename sweep. The four shapes seen, all with the same cause:

| shape | example | fix |
|---|---|---|
| a shared file's Lua `require` | `default/hypr/envs.lua` → pruned `nvidia.lua` | drop the require (match the fork) |
| a shared config's suppression list | `etc/fastfetch/config.jsonc` → the fork's `"hideFS": ["overlay","tmpfs","devtmpfs","squashfs","squashfs.overlay"]` on the disk module | re-apply it: without it the panel advertises the composefs root as `34.27 MiB / 34.27 MiB (100%) - overlay [Read-only]` beside the real `/var` |
| a menu row | `install.ai.openclaw`, `remove.ai.openclaw` → pruned installers | drop the row (match the fork) |
| a whole NEW upstream file whose body calls a pruned command | `bin/omarchy-hw-dell-xps13-dx13260-ptl` → pruned `omarchy-hw-intel-ptl` | delete the file; its callers skip when absent |
| a NEW migration calling a pruned command | `migrations/1792965062.sh` → pruned `omarchy-hibernation-setup` | `command -v X >/dev/null \|\| exit 0` before the call, or it fails and stays pending forever |

Two measurement traps, both hit here:

- **Compute the prune set as fork point → fork HEAD, never tag → fork.** The tag is 1713 commits
ahead, so `git diff --diff-filter=D <tag> <fork>` reports 3767 "deletions" that are really files
upstream added. The real number is 118, and against those the prune is complete (zero survivors) —
which is the opposite of the conclusion the wrong baseline gives.
- **A menu row's guard can report a pruned package as present.** `omarchy-pkg-present` treats a
`skip`-mapped name as satisfied, so a row for a skipped package looks usable, launches a pruned
command, and does nothing. "Dead row" is not only about text.

Sweep: `git grep -n -F -f <pruned basenames> <branch> -- bin/ default/ install/ shell/ migrations/`,
then discard comment lines, `.md`/`.json`/reason strings, installer-only `install/hardware/*`, and
the legacy `retire` manifests in `bin/omedora-upgrade-to-4` / `bin/omarchy-upgrade-to-quattro` (those
correctly delete old copies). Also check the row *set* against the fork's menu, but expect noise:
the row-level difference is dominated by upstream renaming groups (`appearance.*` → `style.*`), so
filter to rows whose action names a command that no longer exists — that leaves one row, not 135.
Validate menu edits structurally (row count ±1, count of `,\n}` shapes unchanged): upstream's own
`omarchy-menu.jsonc` is not strict JSON, so a `json.loads` test fails on it before and after the edit.

### A Fedora arm that reads mutable-Fedora state is not an arm for the image

The phase-2 sweep extends `case … fedora)` arms to `fedora-ostree` by copying the Fedora body.
That is right for /etc writers and RPM-db readers, and wrong when the body reads state only a
mutable install has. Real instance: `bin/omarchy-version-pkgs` derives the last upgrade time from
`dnf history list`, and a composefs image **installs nothing at runtime**, so the copied arm found
nothing and answered `unknown` - which is what fastfetch's Update line then showed. (The pre-4.5
line was no better: the case did not match, execution fell through to the Arch path, and it printed
`now` - the file's own comment admits it.) The right answer on the image is the running
deployment's composition time: `rpm-ostree status --json` → the deployment with `"booted": true` →
`timestamp` (an epoch; 1794476450 = the image build that produced it). Keep dnf history as the
fallback and say `unknown` only when both are empty.

So when copying a Fedora arm, ask what it reads: package db or `/etc` (fine), dnf history, pacman,
or any runtime-install record (needs a deployment-aware rewrite).

## Two classes the sweeps miss (both cost a red COPR build)

### The fork's identity, not its file set

Files both sides *created* (the AA conflicts) look like upstream's to take, so a diff/rename sweep
walks past the fork's delta inside them. The fork's delta there is its own owner, and taking
upstream's version silently points the build at **upstream's** COPR:
`bin/omedora-copr` (the owner default the COPR workflow derives the project from — on the 4.5
branch it answered `agaspar/omedora-4`, so a dispatch would have tried to build into someone
else's project), `.github/workflows/copr-build.yml` (the comment naming the derived project),
`omedora/packaging/copr/quickshell.spec` (`-DDISTRIBUTOR`), the two COPR tests' expectations,
and `icon.txt` (the fork's ASCII banner).

Detect it with an identity grep, both ways: `git grep -l wegweg7979 omedora-4` vs the branch (and
the same for `hurunagus`). Then take the fork's file wholesale — verified safe here because the
branch's copies were byte-identical to the tag, so the fork's version is exactly tag+identity.
Confirm with the fork's own test (`test/copr-chroot-probe-test.sh`, 11 checks) and by running
`OMARCHY_PATH=$PWD bin/omedora-copr`, which must print the fork's project.

### The packaging `%files` is a THIRD enumeration of the file set

Beside the code references and the menu, the spec's `%files` names files explicitly, and a prune
that misses it fails the **build** rather than the session:
`File not found: .../BUILDROOT/usr/lib/systemd/user/omarchy-recover-internal-monitor.service`
(omedora-settings, both chroots). With 163 files deleted, check every deletion against every spec's
non-comment lines in one pass — never fix the reported file and re-dispatch, because rpmbuild stops
at the first missing file and the rest are unchecked.

- `omedora.spec` survived because its `%files` uses globs (`%{_datadir}/omarchy/bin/omarchy-*`) —
  the brittle one is `omedora-settings.spec`, which names each unit.
- The same prune has to reach the *runtime* lists too: `install/user/first-run/enable-user-units.sh`
  enabled the deleted unit, and a missing unit there sets `failed=1` and fails the whole first-run
  hook (its loop is per-unit, so it is silent otherwise).
- Expected false positives in the audit: `omarchy-update-user-notify.service` is a symlink the spec
  creates in `%install` (to `omarchy-migrate-notify.service`), and `owed.service` ships inside the
  owe RPM. `openclaw.spec` still names a pruned command — pruned from `SPECS`, never built.
- Legacy `retire <path> <sha>` manifests in `bin/omedora-upgrade-to-4` and
  `bin/omarchy-upgrade-to-quattro` are correct as-is (they delete old copies), and that helper
  `enable_user_unit` `return 0`s when it finds none of its three locations.

## Image-repo handoff (after the branch is pushed)

The image repo keeps its own copies of the two files that encode the package knowledge,
and they are what actually has to move — the branch alone changes nothing on disk. A PR there
is genuinely useful before merging: `build.yml`'s push/login steps are gated on
`github.event_name != 'pull_request'`, so a PR build resolves and installs the whole package set
without publishing an image — free evidence, roughly 17 minutes.

**A green build is not a verified build.** The first green PR build was installing `libreoffice`,
which an earlier commit of ours had wrongly un-excluded; only the `+ dnf5 install -y …` line in
the log showed it. Always compare the installed set against intent, name by name.
 Check
provenance first: `build_files/fedora.toml` and `build_files/omarchy-base.packages` in
`~/hurunagus-hyprland` were byte-identical to the fork's `omedora-4` versions, so the
handoff was two whole-file replacements plus `build_files/fedora-baseline.packages`, which
was already identical to 4.5 and did not move.

- **Move the map and the list together** (106→176 entries, 147→162 packages in the 4.5
  case). The new list names 24 packages the old map has never heard of; the map is what
  turns each Arch name into a Fedora name. Diff the list with a set difference, not a
  line diff, so additions and removals come out separately.
- **The resolver dry-run is the acceptance gate for the whole handoff — run it both ways.**
  `python3 build_files/fedora-resolve.py --map <map> --fedora-version {44,45} build_files/omarchy-base.packages`
  is read-only (it also consults the host's `rpm` db for `satisfied_by`) and settles every
  packaging claim: new map + new list gives the RPM count (138 for 4.5, same for f44 and f45);
  **old map + new list gives the proof that the two files must move together** — the set
  difference against the new run is exactly the names no enabled repo has (`qt6-{base,…}` that
  the map rewrites to `qt6-qt*-devel`, `vi`→`vim-minimal`, `xorg-xsetroot`→`xsetroot`,
  `disktree-bin`→`disktree`, plus the skip-mapped four), and `dnf install` aborting on the first
  missing name is what fails the build. A `repoquery` over the difference confirms it.
- **An empty `--copr-out` is not a missing-COPR problem.** The 4.5 map has no `source = "copr"`
  entries, so the helper writes nothing and the build.sh loop over that file does nothing — the
  COPR is enabled by a hardcoded `dnf5 -y copr enable <owner>/<project>` earlier in build.sh.
  Check for that line before reporting that the build cannot see the COPR-built packages.
- **`source = "skip"` counts as satisfied** — a skip-mapped name installs nothing, fails
  nothing, and keeps the migration that swaps it from ever being reached. `base-devel`,
  `gliff`, `omarchy-hyprland-titlebars`, `omarchy-power-profiles-daemon`, `owe-lockfeed`,
  `superwhisper-bin` are all skip-mapped in 4.5, so their presence in the base list is
  inert: keep them, do not "fix" them.
- **A name can leave the base list while the map entry stays identical.** 4.5 dropped
  `power-profiles-daemon` and added the skip-mapped `omarchy-power-profiles-daemon`, and the
  `[power-profiles-daemon]` entry is byte-identical in both maps (Fedora ships `tuned-ppd` as
  the ppd-service provider; omedora supplies the CLI via
  `install/user/powerprofilesctl-shim-fedora.sh`). Read the entry before reporting an impact —
  the first read here said "the image loses power profiles", which was wrong.
- **A skip-mapped name the IMAGE needs is the image's own job to add.** `sddm` is in 4.5's
  list but skip-mapped ("Omedora stays on GDM on Fedora"), so the hyprland image's
  `EXTRA_PACKAGES` entries for `sddm` and `sddm-wayland-generic` are the *compensation* for
  that skip, not duplicates — and `sddm-wayland-generic` is not in 4.5's list at all.
- **After taking upstream's list, re-audit `EXCLUDED_PACKAGES` in `build_files/build.sh` against
  it — a name belongs there only while it is still in `omarchy-base.packages`.** Removing a name
  from the list silently turns its exclusion into a no-op that *reads* as intentional, and this
  block has gone stale on two bumps running (4.5 dropped `kdenlive`, `obs-studio`, `lazydocker`,
  `xournalpp`; `libreoffice` was already dead before that, in neither list). Script it: parse
  the array, test each name against both the old and the new list, delete the dead ones. Then
  say the rule out loud in the comment above the array, because the next bump will need it too.
- **Bake-vs-exclude for each new upstream app is a two-question test, not a coin flip.**
  1. **Is it wired in with no fallback?** Grep the caller and read its tail: `omarchy-capture-screenshot`
     ends in `exec omasnap …`, so without the package Print Screen is simply dead; the wallpaper
     engine is the same shape (`omarchy-theme-bg-boot-intro` drives `owe warm/intro-prepare/refresh/status/intro`,
     one path a hard `owe refresh || exit 1`, others `|| return 0`). Bake anything whose caller has
     no fallback.
  2. **Does upstream itself offer to remove it?** An app listed in `omarchy-install-preinstalls` /
     `omarchy-remove-preinstalls` is upstream's own "removable preinstall" class (`hype` slides,
     `monologue` webcam recorder, `signed` PDF signing) — the same class this image already
     excludes (`omacut`, `omawrite`). Excluding is coherent, with the caveat to state plainly:
     installing later needs an rpm-ostree layer or a rebuild, not a click.
  A tool that replaces something upstream dropped from the list (`disktree` replacing `dua-cli`)
  is a base tool, not a preinstall. Report the verdicts as that table (app / what it does / what
  breaks if absent) so the user can overrule one item instead of the whole list.
- **Deliver it as a commit on a SIDE BRANCH of the image repo, off `main`** (the user's standing
  instruction for image-repo changes of this size) and leave `main` at its old sha. Check the
  repo's own triggers before pushing the branch: `build.yml` is `branches: [main]` (+ schedule
  and PR-to-main) and `build-disk.yml` is dispatch-only, so a side-branch push cannot start a
  20-minute image build — confirm that for the repo in hand rather than assuming it.
- **Apply it by copying files verbatim, not through a hand-rolled patch.**
  `git -C <fork-clone> show <branch>:<path> > <image-repo>/<path>` is the authoritative move, and
  it is self-verifying: compare the copy against `git show <branch>:<path>` and expect IDENTICAL.
  A `diff -u` between an absolute scratch path and the repo produces headers `git apply` rejects
  (`error: … : No such file or directory`) — if a patch file is wanted for review, **generate it
  from the branch** (`git diff main..HEAD > <name>.patch`), which carries proper `a/`-`b/`
  prefixes, and prove it applies with `git apply --check` inside a throwaway clone of `main`
  before handing it over. Also `git show` the file list after committing: the branch should
  change exactly the files intended, and nothing else (no `__pycache__`).

## What upstream's 4.5 brings (so the plan names it)

4.5 base apps (Omasnap, OWE, Hype, Monologue, Signed, Disktree) packaged in the COPR; Gliff and
the Hyprland titlebars NOT on Fedora yet; **Voxtype the default dictation backend** (Alt+Space,
Right Alt push-to-talk) with the install shims retired; Ctrl+brightness drives the keyboard
backlight; Alt+Shift+Tab cycles backwards; installs no longer join the docker group; F44+F45
supported incl. in-place 44→45; kitty 0.50.0; Nov HypXR snapshots (which the fork's COPR
prunes).
