# Porting the Omedora/Omarchy command suite to an immutable bootc image

Omedora is already a *mutable-Fedora* port of Omarchy (dnf on a writable /usr).
Carrying it onto an immutable/bootc image is a SECOND port with its own shape.
This extends `references/omedora-copr.md` (what the COPR owns) and
`update-notification.md` (the update check) — read those first; those cover the
binary/manifest split and the checker; this covers the command suite itself.

## The core design: a third distro token, not a rewrite

Omedora's commands are one-file-per-command in `bin/`, each keeping its Arch
body byte-identical and adding a top-of-file distro dispatch that enoughs off to
a sibling:

```bash
case "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" in
  fedora) exec "$(dirname -- "${BASH_SOURCE[0]}")/fedora/pkg.py" add "$@";;
esac
```

To port to immutable, do NOT rewrite the Arch/Omedora bodies. Extend
`bin/omarchy-distro` from {arch,fedora} to {arch,fedora,fedora-ostree}: emit
`fedora-ostree` when `/run/ostree-booted` exists, else the existing logic. Then
each mutable-state command's `case` gains a third arm that execs a new sibling
under `bin/ostree/`. This keeps the Arch body untouched so upstream rebases stay
clean — the same additive-patch contract `test/byte-identity-test.sh` enforces.

Classify each command before touching it: pure user-space (~/.config, hyprctl,
PipeWire, Flatpak apps) works unchanged; `pkg-*`, `install-*`, `remove-*`,
`reinstall*`, and the `update-*` chain drive dnf and are the ones that need the
ostree branch. `install/hardware/`, Plymouth, Limine, SDDM, snapper, and the
XR specs under `omedora/packaging/copr/` are image-owned or bootc-managed and
are deletion candidates, not adaptation.

## Distro token: empty must mean mutable

`omarchy-distro` must honor a test/override marker variable where "set and
empty" = force the MUTABLE path (a host that wants to opt out), distinct from
"unset" = default to the real marker path. `VAR="${OMARCHY_OSTREE_MARKER:-/run/ostree-booted}"`
is wrong — `:-` coerces an explicitly empty value back to the default, so a test
can never force mutable. Test set-but-empty with `${VAR+x}`:

```bash
if [[ -n ${OMARCHY_OSTREE_MARKER+x} ]]; then
  ostree_marker="$OMARCHY_OSTREE_MARKER"   # even "" => mutable
else
  ostree_marker="/run/ostree-booted"
fi
```

## Test trap: the dev host is often itself booted from ostree

On a developer/repro machine running a bootc image, `/run/ostree-booted` EXISTS,
so every `distro-test.sh` assertion expecting plain `fedora` silently became
`fedora-ostree`. Every test that asserts the mutable token must pass the empty
marker explicitly: `OMARCHY_OSTREE_MARKER="" OMARCHY_OS_RELEASE_PATH="$fix" \
"$ROOT/bin/omarchy-distro"`. Add the ostree-branch assertions to the same test
file using a fixture marker file. This is the lesson behind the marker seam
above.

## Pruning the menu after deleting commands: thematic, not dangling

The menu (`default/omarchy/omarchy-menu.jsonc`, one id per line, JSONC) is
pruned by deleting whole lines. Two mistakes when removing a command family:

1. **Route intent through the dangling-ref grep, not the family.** An entry for
a removed service/gaming item may call a *generic* survivor
(`omarchy-install-and-launch`, `omarchy-games-retro-install`) and reference a
package, not the deleted command — so a "does the menu reference a deleted
command?" grep misses it. Track by family, not by direct reference.
2. **Drop container submenu ids that go empty.** After a `Gaming`/`Service`
submenu loses all children, remove the now-empty parent row too, including
nested empties, recursively until stable.

Validate with the repo's OWN parser rather than a hand-rolled one:
`shell/plugins/menu/MenuModel.js` `stripJsonc`/`parseMenuJsonc` (also used by
`test/shell.d/menu-*.sh`) — run it over the edited file and assert it parses and
has no dangling `omarchy-*` command refs other than known package args
e.g. `omarchy-emacs`). Don't ship a Python jsonc stripper when the repo already
parses the file; the strip logic (string-aware comment + trailing-comma
handling) is easy to get wrong.

## After deletion, expect the CLI metadata gate to churn

`test/cli` — the CLI routing/metadata gate — has assertions that reference
*specific* command binaries (xbox-cloud, gpu-lib32, dev benchmark), so deleting
a family that those assertions name FAILS that test by design. That is expected
deletion churn, not a regression in the dispatcher (`commands --check` still
passes). When pruning a family, grep `test/cli` for the deleted binary names and
remove or update those assertions in the same change.

The byte-identity audit (`test/byte-identity-test.sh`) self-skips when the
upstream pin tag (from `omedora/architecture.md`) is absent — a shallow/fork
clone with no tags makes it a no-op. It enforces "every deleted line of an
upstream file must be allowlisted," so wholesale command deletion on a repo
WITH the pin tag needs allowlist updates; on a bare fork it silently gates nothing.

## Verification: separate your failures from pre-existing ones FIRST

After deleting command families, run the test gate on a clean HEAD worktree and
DIFF the failing-file set against your working tree before touching any test:

```bash
git worktree add /tmp/clean-head HEAD
cd /tmp/clean-head && bash test/shell > /tmp/shell-baseline.out 2>&1; echo $?
awk '/^==>/{f=$0} /^not ok/{print f}' /tmp/shell-baseline.out | sort -u
# compare to the same awk over your working tree's test/shell run
```

Only the failures NEW to your tree are your regression — fix or delete THOSE
tests. Failures present on clean HEAD are pre-existing/environmental (fixtures
expected missing tools, this ostree host's state) and are out of scope; do not
churn the suite for them. Deleting only the 6-7 newly-failing files and pruning
the CLI assertions is the correct, minimal completion of a command-family
removal. Clean up with `git worktree remove --force /tmp/clean-head`.

Deleting a family also orphans TOP-LEVEL `test/*.sh` spec tests beyond
`test/shell.d/`: XR specs (`hypxr-*`, `xreal-ctl`, `basalt-xreal`,
`monado-xreal`), `openclaw-spec`, and the plymouth/pacman cases inside
`archism-gating-test.sh`. Grep the whole `test/` tree for deleted command names,
not just `shell.d`. Some need deletion (pure spec orphans), some only a trim
(`archism-gating` keeps its fingerprint/channel cases), some ride on a later
phase (`update-flow-test.sh` waits for the bootc update rework, not deletion).

## Repointing assertion targets: a partial-prefix test must NOT resolve

`test/cli` has "partial prefix renders matching commands" assertions that run
the dispatcher with a partial route (`omarchy hw asus` originally). When those
command families are deleted you cannot just repoint at a survivor's name:
`omarchy hw laptop` FULLY RESOLVES to a real binary and executes hardware
detection (jq parse error / non-zero exit on a host without the tooling), which
kills the test under `set -e`. A partial-prefix assertion needs a route that
matches several commands but does NOT resolve to one; once the family is pruned
so no such ambiguity remains, DROP the partial-prefix assertion rather than
repoint it — the bare `--help` group assertions already cover the group.

## Never run test suites on a live dev host — static-only may be the required mode

The shell suite's broader/acceptance-style tests execute commands that reach
the system manager (systemctl, firewall, root) AND run against the LIVE
INSTALLED tree (`/usr/share/omarchy`), not the checkout — a test on a booted
host fires polkit/root/firewall prompts the user must deny. The user has flagged
this twice ("my testing is triggering" the firewall/root-password prompts) and
likes a static-only verification boundary thereafter. So: prefer `bash -n`
syntax checks, `git diff`/`git status`, and reading files over executing the
suite. If the user reports prompts firing, kill every test process now and stop
running the repo's tests. When a command-family deletion breaks tests,
baseline-compare a clean HEAD worktree first so you fix only YOUR regressions,
not pre-existing/environmental failures; a worktree you created to baseline must
be cleaned up with `git worktree remove --force`.

On check-your-own-work runs of the SAFE in-tree gates (e.g. `distro-test.sh`),
be aware the dev host often IS ostree-booted and a controller override may fire
real subprocesses — never background a fan-out subagent that serially runs
the whole suite against the live host.

## Reviewing a batch of migrations/ and install/ scripts for immutable-readiness

When asked to go through "the migrations that run after a rebase" (or any
install/* config suite) on the immutable fork, do not read 100+ files linearly.
Cluster programmatically, decide per cluster, then verify with grep sweeps.

1. **Cluster by action token, not by title.** For migrations, group by what they
touch: `omarchy-pkg-add/drop/present` (PKG), `pacman`/`limine-mkinitcpio`/`dracut`
(boot/pacman), `sudo systemctl`/`as_root` (machine-state), `systemctl --user`
(user units), `$HOME/.config` edits (plain-config), and `omarchy-*` subcommand
calls. A regex over the file body (first non-comment echo gives the title, but
the ACTION is what matters) is the right classifier.

2. **Split install/config vs install/user — that is the load-bearing fact.**
`install/config/*` (e.g. `firewall.sh`, and the shebang-fix that root-edits
`/usr/bin/powerprofilesctl` with `sed`) runs as ROOT under `omarchy-setup-system`,
inside the MUTABLE installer (`omedora/install-4.sh`: packages -> setup-system ->
provision-user) and NEVER runs on the bootc image. `install/user/*` runs as the
USER at bootc first-boot (`omarchy-provision-owner.service` ->
`omarchy-provision-user --force --first-install`) and MUST be `$HOME`-only.
So: any `/usr`/`/opt` write in install/config is a mutable-installer concern, not
a bootc regression — leave it; the bootc image's only first-boot surface is
install/user (theme, chromium, git, xcompose, mise, keyring, an auto-detecting
nouveau-cursor fix). The Fedora siblings (`*-fedora.sh`) already do the
immutable-safe thing (shim into `~/.local/bin`, firewalld rules, `enable_if_present`).

3. **Cross-check package targets against what is ALREADY BAKED, not against the
source.** Read the image bake set (`build_files/omarchy-base.packages` +
`fedora-baseline.packages` + `EXTRA_PACKAGES` in `build.sh`) and ask of each
migration's `omarchy-pkg-add` target: is it in the bake set? A target already
baked makes the migration a silent no-op on bootc (`pkg-add` is satisfied). A
`omarchy-pkg-add` target falls into exactly one of three classes, and only the
third is a decision:

   - **baked** — the migration is a no-op, correct as written;
   - **skip-mapped in `fedora.toml`** — nothing is installed and nothing should
     fail; this is NOT a bake-vs-leave decision, and a migration that errors on
     one of these is a bug in the immutable `pkg` sibling (see the section on
     skip entries and the migration queue below);
   - **unmapped and not baked** — this WILL exit 1 at runtime and abort the
     migration queue, so either bake it or guard the migration.

"A COPR builds it" and "the image installs it" are different facts (kitty/satty
build on the COPR but are not installed) — a COPR spec is not a bake.

   A grep-derived failure list OVER-REPORTS, and acting on one means telling the user their
   migrations are broken when they are not. A `omarchy-pkg-(add|drop)` match also hits comments
   (`# omarchy-pkg-add cannot do that swap…`), array literals (a `"${hardware_packages[@]}"` passed
   as a literal argument), and calls inside an enclosing `if` that cannot fire on this host (empty
   hardware array, a `/etc/pacman.d/mirrorlist` that does not exist, an `lspci` match with no such
   GPU). Read the guard AND the enclosing condition before naming a migration a failure, or probe
   the helper directly — `OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <name>` (and `…-drop <name>`) is
   read-only and exits 1 exactly when the real run would abort the queue. A large candidate list is
   not a large defect list; verify reachability before reporting it.

4. **Apply the guard rule per migration, never blanket** (SKILL.md gotcha 8):
extend `== "fedora"` to `== "fedora" || == "fedora-ostree"` for
Arch/boot/pacman/machine-image work; LEAVE the `== "fedora"` guard on
`$HOME`//etc hardening so bootc runs it, and add an explicit "runs on immutable
too" comment so an upstream merge cannot silently revert it; ADD `fedora-ostree`
to INVERTED (`== "fedora" ]] || exit 0`, i.e. run-ON-Fedora) guards so they
still run. All migrations must end `bash -n` clean. A migration that writes under `/usr` can never
run on bootc at all (`/` is composefs `ro`, not merely "root-owned") — guard it, or bake the file
into the image so the migration's own comparison (`cat <path> != <seed>`) goes false and it never
fires.

5. **Drop pruned hardware/family by DELETING the migration file**, then grep the
whole tree for the deleted filename so no runtime chain (`omarchy-update`,
`omarchy-migrate`) still names it. A fresh image never runs a deleted migration;
the `--first-install` path in `omarchy-provision-user` marks whatever is present
at image-build time as done, so deletions are clean.

6. **Read what a COPR actually serves with the package manager, not the web UI,
and refetch.** A build page saying "succeeded" does NOT mean the repo metadata
carries the new NEVRA yet — COPR publish lags minutes, so a `dnf repoquery`
run too soon shows the OLD nevre and looks like a regression. The authoritative
read is a refetch against the chroot repodata:

   ```bash
   dnf5 -y repoquery --noplugins --refresh \
     --repofrompath=omz,<results>/<owner>/<proj>/fedora-<rel>-x86_64/ \
     --repoid=omz '<pkg>'
   ```

   Re-run the same query when the first one disagrees with a build page before
   concluding it is broken — one stale read is not the state of the repo. (The
   COPR v3 JSON API paths for listing builds/project contents are unstable;
   prefer the HTML Builds tab and this repoquery over guessing API shapes.)

## The pkg sibling's skip entry, and why one bad migration kills the run

`omarchy-migrate` runs each migration as `bash -euo pipefail "$file"` inside a
loop that is itself `set -euo pipefail`, so a migration exiting non-zero ABORTS
the entire run: earlier migrations keep their markers, the failing one does not,
and every later migration never runs. The user sees "N pending, about ten went
through, then it failed". Two rules follow:

- **`add` on the immutable sibling must treat a `skip` entry as a clean no-op.**
  The mutable helper's `is_entry_installed` returns False for `skip` on purpose
  ("nothing is installed for a skip entry, so it is never present"), and its own
  `add` collects skip entries and warns. Carrying only the sibling's
  `not active` check is wrong: that flag is the `since`/`until` release filter,
  which a skip entry PASSES — so the skip falls through to "not in the image;
  bake it into the image build" and exits 1. Print the entry's reason and
  `continue` instead.
- **Do not fix it by making `present` report a skip as present.** Guards depend on
  the truth — a menu row must not offer to remove or launch what Fedora never got.
  Keep `present`/`missing` exact complements and put the tolerance in `add`.

The same blast radius applies to any command a migration calls that no longer
exists: guard it inside the migration (`command -v X >/dev/null || exit 0`) rather
than letting a missing command block the queue. Marking a migration's marker by
hand unblocks the later ones, but only after doing that migration's post-failure
steps yourself — its work after the failing line never ran.

### Reproducing add/drop locally on an ostree-booted dev host

The sibling is self-contained, so its behaviour is testable without a VM — but it
resolves its `fedora/` sibling from its OWN directory, so a copy under /tmp fails
to import. Run it in-tree:

```bash
OMARCHY_PATH=$PWD python3 bin/omarchy-ostree/pkg.py add <name>
```

Probe all three branches before rebuilding: a skip-mapped name (expect
"skipping …", exit 0), a name the target image bakes (expect "already baked",
exit 0), and a name it does not bake (expect the bake-it message, exit 1). On a
dev host that predates the bump, a package the NEXT image bakes legitimately hits
that third branch — that is not a failure of your change.

### Pinpointing which migration failed when you cannot see the host

- The pending set is computable: migrations present in the new base and absent
  from the old line (`git ls-tree -r --name-only <new> -- migrations/` vs `<old>`),
  ordered by the numeric filename prefix. Reconcile that count with what the user
  reports pending — a match confirms both the set and the ordering; a mismatch
  means the failure is somewhere else.
- The runner touches a migration's marker only AFTER it succeeds, so the FIRST
  entry of `omarchy-migrate --pending` IS the failing migration, and re-running
  resumes there with no cleanup.
- Markers live at `$HOME/.local/state/omarchy/migrations/<name>` (override
  `OMARCHY_MIGRATION_STATE`); the markers already written show the naming shape.
- Ask for the failing command's stderr early. Reading a migration and reasoning
  about which step looks fragile is a cheap way to be confidently wrong about
  which line died; one line of output names it.


<!-- absorbed from SKILL.md 2026-11-12 -->

## omedora fork == immutable (2026-11)

The user's fork `wegweg7979/omedora` branch `omedora-4` was adapted for immutable bootc in one commit. This is the canonical Omedora-to-immutable reference:

- `omarchy-distro` emits a THIRD token `fedora-ostree` when `/run/ostree-booted` exists (`OMARCHY_OSTREE_MARKER` seam; empty marker forces mutable `fedora`). Pitfall: use `${VAR+x}` not `${VAR:-}` so an explicitly EMPTY marker means "force mutable" and an UNSET one means "use the real path".
- Immutable siblings in `bin/omarchy-ostree/` (renamed from `bin/ostree/` — see gotcha 3 below for why the name matters): `pkg.py` (present/missing/installed relay the mutable pkg.py read-only rpm+flatpak query; add/drop install/remove Flatpak only, RPMs need bake-at-build; use `resolve_mapping` for source). `update-available` (detect staged by rpm-ostree's OWN `.staged` flag — `[.deployments[] | select(.staged==true)]`, NOT by timestamp; fall back to a NUMERIC `-gt` compare only when the field is absent. Pitfall: `[[ a > b ]]` in bash is LEXICOGRAPHIC, not numeric — comparing epoch timestamps that way mis-fires AFTER the newest image is applied and re-reports a false staged + "reboot to apply" when ujust update has already nothing left to fetch. `.staged` is the authoritative signal: non-booted + staged=true = reboot pending, so the fix stopped honoring the stale timestamp path. rollback-sibling-safe — NEVER count non-booted deployments except the genuinely-staged one). `update` (apply ujust/bootc/rpm-ostree image + migrate + hooks + mise/flatpak + "reboot to apply").
- Arch bodies stay byte-identical; the fedora-ostree arm is a prepend `case` that `exec`s the sibling — upstream rebases stay clean (the user's chosen Option 2).
- Removed: gaming, commercial services, non-Hermes agent installers, brand-specific hw (asus/xps/framework/surface/nvidia/Panther-Lake), boot stack (plymouth/hibernation/limine/sddm/direct-boot/snapshot/factory-reset/windows-vm), dev tooling, XR/vision COPR specs. Keep the 8 load-bearing generic `hw-*` (laptop, laptop-closed, external-monitors, display, intel, vulkan, webcam, touchpad).
- COPR ownership: the fork's `bin/omedora-copr` default `OMEDORA_COPR_OWNER` is now `wegweg7979` (was the upstream `agaspar`), and `omedora/packaging/copr/build-repo.sh`'s SPECS list was pruned of the deleted XR/vision + openclaw + hyprpad specs so a full COPR build succeeds. **The project exists and the images consume it**: `wegweg7979/omedora-4` (chroots fedora-44 + fedora-45), and a host running the fork has `_copr:copr.fedorainfracloud.org:wegweg7979:omedora-4.repo` enabled with a baked NEVRA carrying the fork's own commit (`…git2c68f33`) — so the `copr enable` flip and the vendored-checker removal are DONE, not pending. Verify before claiming otherwise: `ls /etc/yum.repos.d/ | grep wegweg7979` plus `rpm -q omedora omedora-settings`. COPR web UI + API-token page are the only tools needed (no copr-cli); the `COPR_API_TOKEN` secret is what `.github/workflows/copr-build.yml` uses.
