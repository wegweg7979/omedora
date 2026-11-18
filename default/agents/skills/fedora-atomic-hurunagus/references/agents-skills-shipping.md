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
- **The COPR dispatch needs an explicit package list** (a blank list builds nothing): for a
  skill-only change that is `omedora-settings`.
- Current names shipped: `omarchy` (the end-user customization skill, with its six topic
  guides), `omarchy-app`, `diagnose-crash`.

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
