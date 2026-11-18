# The agent skills omedora ships (and how to change them)

Load this before editing, adding or shipping anything under an omedora checkout's
`default/agents/skills/`. Those files are not documentation on the side — on a
hurunagus host they ARE what every coding agent reads before touching the desktop.

## The delivery chain

```
repo default/agents/skills/<name>/          omedora checkout (branch omedora-4)
  → RPM omedora-settings                    owns /usr/share/omarchy/…
  → /usr/share/omarchy/default/agents/skills/<name>/
  → omarchy-provision-user symlinks it into EVERY agent dir:
      ~/.agents/skills, ~/.claude/skills, ~/.codex/skills,
      ~/.pi/agent/skills, ~/.gemini/config/skills, ~/.hermes/skills
      (+ ~/.hermes/profiles/<name>/skills)
```

Consequences that bite:

- **A skill edit reaches nobody until the RPM is rebuilt, the image is rebuilt and the
  host rebases.** The host's `/usr/share/omarchy/...` copy is the *installed* one, and
  `~/.hermes/skills/<name>` is a symlink into it — so the copy this agent loads is the
  baked one, not the checkout. Rebase is the user's step.
- **A payload push rebuilds the RPM by itself — never hand over a dispatch step.**
  `copr-build.yml` fires on push to `omedora-4` with a `paths:` filter that includes
  `default/**`, the self-sourced packages' payload, and submits **both** `omedora` and
  `omedora-settings` — provided the `COPR_API_TOKEN` secret exists (it does; without it the
  job no-ops so forks don't fail). A manual `workflow_dispatch` *does* need an explicit
  package list (a blank one builds nothing) and is only for rebuilding something the push
  did not touch. Check `gh run list --workflow=copr-build.yml` before telling the user which
  of the two applies.
- Current names shipped: `omarchy` (the end-user customization skill, with its six topic
  guides), `omarchy-app`, `diagnose-crash` — plus the local set kept in step by the weekly
  sync below: `machine-health-check`, `hyprland-config`, `hyprland-plugins`, `quickshell`,
  `fedora-atomic-hurunagus`, `omarchy-bar-modules`, `wifi-survey`.

## Publishing local skills into the payload (the weekly sync)

Skills this agent develops on a host live in `~/.hermes/skills/`; the payload ones show up
in that directory as **symlinks** into `/usr/share/omarchy/…`, so only the *real*
directories are the agent's own work — and only those can be published. That is automated:

- `~/.hermes/scripts/omedora-skill-sync.py` scrubs, writes into
  `~/omedora-inspect/default/agents/skills/<name>/`, and commits locally. It **never
  pushes** — push, COPR rebuild and rebase stay with the user.
- allowlist `~/.hermes/state/omedora-skill-sync/allowlist.txt` (`source -> target-name`;
  a category path like `hyprland/omarchy-bar-modules` maps to a flat payload dir, because
  `omarchy-provision-user` only loops one level). Manifest and per-run reports sit beside it.
- A Hermes cron job (Mondays 20:00 local, the day before the 06:00 UTC Tuesday build) runs
  it, reports what moved, and suggests up to 3 new allowlist candidates.

**Two-phase and fail-closed:** the entire plan is built in memory first, and any problem
aborts *before a byte is written* — never a half-scrubbed file left in the tree. The
blocking gates are: not on the allowlist (never considered at all), an identifier that
survives the scrub, and a payload file hand-edited in the repo since the last sync
(compared against `manifest.json`, so a human's edit is never clobbered).

Scrubbed to placeholders: LAN IPs, `/var/home/<user>`, bare usernames in prose and
commands, email addresses, Slack IDs, and the hostnames workstation/desktop/laptop →
workstation/desktop/laptop. Kept on purpose: the hostname `mini` (a generic word) and the
repo's own GitHub handle. **Prose is not rewritten, only identifier tokens are** — so read
a big skill by eye before its first push. Pitfall in the scrubber itself: a bare
`[DCGUT][0-9A-Z]{8,11}` Slack-id pattern also matches ordinary uppercase words
(`GENERATED`, `DISCONNECTED`), so the rule must additionally demand ≥2 digits in the token.

## What a push actually triggers (check before you push)

Two of the three workflows in `.github/workflows/` fire on a push to `omedora-4`, so read
what a change will set off *before* pushing it — and know that the payload pushes are
self-driving (see the dispatch bullet above).

- **`test.yml` runs an explicit list of tests by name — there is no glob.** So adding
  `.sh`/`.py`/`.md` files under the payload cannot turn CI red on its own: no shellcheck,
  no markdownlint, no "lint everything under X" step exists to satisfy. Confirm that from
  the workflow file rather than assuming new scripts must pass a linter.
- **The tests that do touch `default/agents/skills/` assert by NAME, not by enumeration:**
  `test/agents-skill-fedora-test.sh` reads `default/agents/skills/omarchy` only, and
  `test/shell.d/provision-user-test.sh` loops a fixed pair (`omarchy diagnose-crash`). So a
  new skill breaks neither — and the converse is the real point: **a new skill is covered by
  no test at all**, so its correctness rests on review before the push, not on a green run.
- **`byte-identity-test.sh` diffs *modified upstream* files only.** Brand-new files under a
  payload directory are ignored: additions are safe, and it is deleting or rewriting an
  upstream line that needs an `ALLOW[…]` entry.
- The COPR rebuild of a noarch package can take minutes and, once, the sibling `omedora`
  package sat in `running` long past its usual few minutes — a slow build there is not a
  failure, and it cannot block the skills, which ride in `omedora-settings`.

## Byte-identity: these files are upstream files

`default/agents/skills/omarchy/*` exist on the upstream pin, so
`test/byte-identity-test.sh` audits them: modified upstream files must be **additive-only**
unless each deleted line is listed in the per-file `ALLOW[...]` blob (newline-separated
EXACT upstream texts, leading whitespace significant).

- **Generate the ALLOW value from git; never hand-type it:**
  `git diff -U0 -- <file> | grep '^-' | sed 's/^-//'` (drop the `---` header line).
- **Appending to an upstream line is a deletion.** Extending a sentence, even in YAML
  frontmatter, rewrites that line — put the new sentence on its own line instead (`>`
  folded scalars join lines with spaces, so the parsed value is unchanged).
- The pin tag usually is NOT in a working clone (`git tag` shows only fork tags, and
  `git ls-remote --tags origin` has no `omedora-base-*`), so the audit **self-skips locally
  and can skip in CI too**. Verify the allowlist yourself by set-comparing the ALLOW blob
  against the git-diff deletion list — that is the only real proof available offline.

## Writing style for a shipped skill

A skill is read in pieces (an agent may load only part of `SKILL.md`), so:

- **Replace a wrong upstream line where it sits; do not append a correcting section.**
  A contradiction left mid-file ("| **Arch Linux** | Base OS |") wins whenever the agent
  reads that part.
- **Put the distro reality first**, above the first Arch-specific instruction, and key it on
  `omarchy-distro` (`arch | fedora | fedora-ostree`) — the same token the CLI dispatches on.
- The three commands that lie in an Arch-only skill are the three that route per distro:
  `pkg add` / `pkg aur add` (exits 1 on `fedora-ostree` with the bake message), `update`
  (image + reboot, not packages) and `reinstall` (only `omarchy reinstall configs` exists).
  Probe them on the host with `OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <name>` (read-only).

## Gate it

An upstream rebase would silently restore the Arch text. Add a **static** L1 test —
`test/agents-skill-fedora-test.sh` is the pattern: grep the skill for the Fedora claims,
assert the distro section precedes `## Command Discovery`, assert the topic guides stay
Arch-free, and cross-check the named tokens/commands against `bin/` (`bin/omarchy-distro`,
`bin/omarchy-reinstall-configs`) rather than reasoning about them. Wire it explicitly into
`.github/workflows/test.yml` (job `shell-unit`) — that job runs each test by name; there is
no glob. Keep such a gate grep-and-existence only: never call the CLI or the live system
from it.
