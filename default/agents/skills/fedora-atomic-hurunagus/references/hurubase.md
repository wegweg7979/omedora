


<!-- absorbed from SKILL.md 2026-11-12 -->

## Cross-DE/DM rebase helper (`hurubase`, 2026-11)

Its own repo: `~/Documents/GitHub/hurunagus-rebase` — standalone, NOT in omedora,
because not every hurunagus variant ships omarchy/omedora, so nothing in it may
call `omarchy-*`. One self-contained bash script (`hurubase`), run from a
checkout; deliberately not baked into any image yet.

**Running the checklist is a SUDO verb that writes into `$HOME` — check ownership before blaming the desktop.**
`cp -a /etc/skel/...` preserves ownership, so a checklist run under sudo leaves
root-owned dotfiles behind (`sudo find "$HOME" -xdev -user root -not -path '*/.cache/*'`
inventories them: `~/.config/**`, `~/.local/state/omarchy/**`,
`~/.local/share/applications/**`, `~/.local/share/nautilus-python/**`). The fatal one is the
**state dir**: `~/.local/state/omarchy` at root 755 means the user cannot write migration
markers, `done/first-run-user` or `first-run.log` — so *nothing migrates and first-run never
completes*, and the shell logs `mktemp: failed to create file via template
'…/.local/state/omarchy/agents/usage/.<p>.XXXXXX': No such file or directory` every session.
Proof in one line: `touch ~/.local/state/omarchy/.w` → Permission denied. Repair:
`sudo chown -R <user>:<user> ~/.config ~/.local/state ~/.local/share/applications ~/.local/share/nautilus-python`,
`chmod 600 ~/.config/omarchy/shell.json` (the skel copy lands 644; an installed box has 600),
then as the USER (never root — the migration markers and first-run guards live in the USER's
`~/.local/state/omarchy/`, so `sudo omarchy-migrate` just re-creates the ownership bug being repaired):
`omarchy-provision-first-run` and `omarchy-migrate`. The chown alone does NOT repair a logged-in host:
first-run fires once per SESSION from the compositor autostart, so the already-running session has
already failed silently — reboot, re-login, or run it by hand. hurubase
already resolves `$HOME` from `SUDO_USER` but never chowns what it writes — a known gap in the tool,
not user error; after any root-run `$HOME` seeding, verify ownership first.
- **hurubase needs a CONTROLLING TERMINAL** — its prompts read `/dev/tty`, so a plain
  `ssh host './hurubase …'` (no `-t`) dies with `./hurubase: line 172: /dev/tty: No such device or
  address`. Use `ssh -tt`, a real terminal on the box, or `HURUBASE_ANSWERS`; `--dry-run --yes`
  prints the entire checklist (what would be written/replaced/backed up) without changing anything,
  and bare `--check` only answers "you are already running <address>".
- **Which Omarchy line a box is on = `omedora/base-version` (`4.5.0`), NOT `/usr/share/omarchy/version`.**
  That file mirrors upstream verbatim (`4.0.0.alpha`) and reads identically on every host of the line,
  so it proves nothing; the baked content marker is `rpm -q omedora`'s `…git<sha>` suffix.
- **A failed unit that appears on EVERY host of the line is noise, not a regression.**
  `systemd-remount-fs.service` fails on every boot here: fstab pins the btrfs root subvol `ro`, so the
  remount-reconfigure hits `mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure.`
  Compare a suspicious unit across the other hosts before reporting it to the user.
- **Reboots of other hosts are the user's to run — ask, do not attempt.** Over ssh polkit answers
  `Access denied as the requested operation requires interactive authentication`, and sudo is
  password-gated (the only NOPASSWD entries are a few omarchy helpers), so a remote reboot cannot be
  driven from an agent session.
- Depth for the whole read-only rebase audit — the cross-host booted-vs-staged sweep, the
  "desktop never arrived" skel signature, the first-run/migration marker table and the ownership
  repair: `references/rebase-and-first-boot-verification.md`.

- **Decide the apply path from `/etc/containers/policy.json`, never from a table guess.** Match the docker repo key by longest prefix: `insecureAcceptAnything` (including the EMPTY-key fallback the ublue template ships) = the signed path works in one step; `sigstoreSigned`/`signedBy` with a missing keyPath = two-step; `reject`/no entry = two-step. On the user's hosts the empty-repo fallback means the documented two-step is usually unnecessary — print that, and name the skipped verification out loud.
- **`/etc/skel` is the cross-DE failure mode and it has two halves.** (1) Adoption: an atomic rebase never seeds `/etc/skel` into an existing `$HOME`, so the new desktop's configs never arrive. Write only MISSING files, report differences (opt-in `--adopt-differs` with `<file>.pre-rebase-<ts>` backups), and honour a per-target never-clobber list (Zirconium: `~/.config/niri/local.kdl`). (2) Session: `~/.config/sddm/state.conf` `LastSession=` and `/var/lib/AccountsService/users/<user>` `XSession=` keep naming the OLD session after the rebase → black screen or a bounce back to the greeter. Report by default; `--finish --fix-session` (root) resets them after backing up.
- **Per-target facts worth encoding.** Zirconium: Fedora bootc, mkosi-built (no Containerfile/build.sh to copy from), niri + DankMaterialShell, `enable greetd.service` plus `greetd.service.d/20-kmscon.conf`, installs via plain `bootc switch`, ships user-level `chezmoi-init.service`/`chezmoi-update.timer` that manage `$HOME` on first login, and its preset disables sshd/systemd-timesyncd while enabling auditd/firewalld/ntpd-rs/systemd-resolved/cardwired. ublue family (bluefin/silverblue/aurora/kinoite/bazzite): ublue-os key + `ghcr.io/ublue-os` policy entry, GNOME→GDM, KDE→SDDM.
- **Live vs dead variants: ASK, never infer from registry activity.** `hurunagus-hyprland` is the FLAGSHIP variant and the default target of anything variant-aware. `hurunagus`, `hurunagus-umbriel` and `hurunagus-hyprland-dms` are dead or never worked, yet all three still publish fresh-looking ghcr tags (`latest-<date>-<sha>`) — a recent tag proves a build ran, not that the image boots or that the user wants it. Propose a variant set and let the user prune it; keep the dead names out of tables, READMEs and ghcr probes.
- **Refuse `*-nvidia*` refs** (exit 1, not a warning): the project does not stand behind vendor-flavoured images, so they are neither listed nor accepted by name.
- **Bash traps that cost real time here.** (a) `df -Pk --output=avail` is REJECTED by coreutils ("options -P and --output are mutually exclusive"), so a space guard silently no-ops — use `df -Pk <path> | awk 'NR==2{print $4}'` and emit a WARNING when the number cannot be read instead of skipping the guard. (b) A helper ending in `[[ ... ]] && printf` returns 1 on a non-match, so `x=$(helper "$v")` under `set -e` kills the script SILENTLY (symptom: output stops mid-section, exit 1, no error) — end such helpers with `return 0`. (c) `printf '%-8s ...' fmt extra-args` repeats the format and prints phantom rows. (d) Sourcing os-release inside `( )` and reading the vars outside yields empty strings — do source+print inside the subshell.
- **The interface is the ADDRESS, not a name (user's decision, 2026-11).** `hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest`. A bare name exits 2 with a pointer to `--list`; the address is what gets resolved, digest-pinned and rebased onto. The name→desktop table stays as *knowledge* (DE, DM, session name, never-clobber list, notes) looked up from the address, with a generic path + warning for unknown addresses.
- **`--list-refs` exists because the human `--list` table is unparseable by whitespace.** The desktop column contains spaces ("Hyprland + Omarchy"), so `read -r _ _ _ _ address _` silently reads the DM as the address and the CI/README consistency check reports nonsense. Any script or CI step that wants the addresses must use `--list-refs` (one address per line).
- **One command, repeated — not `--continue`/`--finish` ceremony.** State lives in `/var/lib/hurubase/state` (`/var` is untouched by a rebase, so it survives), and re-running the same address walks the machine: no state → preflight/plan/apply; staged at step 1 → the signed half; booted on the target → the fix checklist. A rebase in progress to a *different* address is refused, and rebasing onto the image you already run says so instead of re-rebasing.
- **The post-reboot fixes are PROMPTED, not reported** — the user asked for fixes with prompts. Each finding is checked against the running target and offered separately: `/etc/skel` adoption (a plan/apply classifier: missing → write, identical → nothing, differs → ask, never-clobber → always leave), the stale recorded session in `/var/lib/AccountsService/users/<user>` + `~/.config/sddm/state.conf`, a display manager still enabled that the target does not ship, a dangling `display-manager.service` alias (fix = `systemctl enable <target dm>`, never an rm), and the target's own user-level dotfile services (Zirconium's chezmoi → offer `systemctl --user mask`, or print it when there is no session bus). Root-only fixes defer to "re-run this same command with sudo" rather than failing.
- **`HURUBASE_ANSWERS` is both a feature and the test seam**: a file of `y`/`n` lines consumed one per prompt, which is the only sane way to test an interactive checklist (a FIFO for the prompt TTY deadlocks, and a plain file re-reads line 1 every time).
- **bash 5.3 + `set -u` trap: `${#arr[@]}` on a declared-but-empty array is an "unbound variable" error and kills the function.** `local -a list` followed by `((${#list[@]} < 3)) && list+=(x)` aborts with `list: unbound variable` (reproduced: `local -a a; ((${#a[@]} < 3))`). Accumulate `first-N examples` in a plain string with a counter (`((n <= 3)) && eg+="$rel "`) instead of an array.
- **Verify with mocks PLUS one real read-only run.** 139 checks in `test/hurubase-test.sh` (fake rpm-ostree/bootc/skopeo/systemctl/df/mokutil + fixture `/etc`, `$HOME`, `/etc/skel`) were green while two real bugs (the `df` guard, a crash on targets with no OCI version label) only appeared from `./hurubase --check <target>` against the live host. Always finish with a read-only preflight on the real machine; `./hurubase <address> --yes --dry-run --no-adopt` is a safe way to see the whole post-reboot checklist on a live box without changing anything.
- **The hurunagus-hyprland clone goes stale, and `git push` will then be REJECTED.** `~/hurunagus-hyprland` (the working clone) can sit behind `origin/main` while `git status` reports "in sync" from a stale remote-tracking ref. Always `git fetch` before reporting a branch state, and on rejection `git rebase origin/main` — never force-push. Real instance 2026-11: a README commit was rejected by 4 unseen remote commits; reading `git diff HEAD...origin/main -- README.md` first showed the remote's edits were in `## Desktop` while the local ones sat at lines 24/71/119/134, so the rebase was clean.
- **`build.yml`'s push trigger carries `paths-ignore: '**/README.md'`,** so a docs-only push to `main` publishes no image and starts no run — no need to warn about a rebuild. Its `workflow_dispatch` inputs are `fresh` (ignore the layer cache, re-resolve the CachyOS kernel) and `rechunk` (~10 min).
- **The hurunagus-hyprland README now leads `## Install` with `hurubase`** as the safe path (manual 4-step kept below as "If you prefer to do it yourself"), points at it from the loose rebase block near the top, and notes in the cross-distro section that re-running the same command covers the `omarchy-reinstall-configs` step plus the stale-session fix.
