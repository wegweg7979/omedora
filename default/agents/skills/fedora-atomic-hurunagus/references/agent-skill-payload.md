# The agent-skill (and shipped-doc) payload the image delivers to coding agents

Load this when the user says that a skill, doc, or agent instruction that SHIPS ON THE
IMAGE should be modified for hurunagus / the immutable Fedora base ("the omarchy skill
that ships on our image should maybe be shipped modified for hurunagus-hyprland and its
fedora immutable base").

## Where it lives, and how it reaches every agent

- **Single source of truth:** omedora's `default/agents/skills/<name>/` (its `SKILL.md`
  plus the topic `.md` files next to it). Edit it in `~/omedora-inspect` — never in
  `/usr/share/omarchy/…`, which is the read-only installed copy.
- The directory is PACKAGED: `rpm -qf /usr/share/omarchy/default/agents/skills/omarchy/SKILL.md`
  resolves to `omedora-settings-<nevra>`. So `default/agents/skills/` is a shipped
  artifact of the fork, not scratch space, and it reaches `/usr` only through the RPM.
- `bin/omarchy-provision-user` loops over `"$OMARCHY_PATH"/default/agents/skills/*/` and
  `ln -sfn`s each directory into `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`,
  `~/.pi/agent/skills`, `~/.gemini/config/skills` and `~/.hermes/skills`. Two
  consequences: **this Hermes agent's own `~/.hermes/skills/omarchy` is that symlink**
  (writing through it writes into read-only `/usr`), and every agent on the host starts
  reading the new text at the same moment.
- Nothing in the image repo (`system_files/`, `build_files/`) copies these files. Do not
  go looking there for the payload; it belongs to omedora.

## Read-only recon before proposing anything

```bash
diff -rq ~/omedora-inspect/default/agents/skills/<name> \
         /usr/share/omarchy/default/agents/skills/<name>      # checkout vs installed
rpm -qf /usr/share/omarchy/default/agents/skills/<name>/SKILL.md
ls -la ~/.hermes/skills/ | grep <name>                        # confirm the symlink, not a copy
git -C ~/omedora-inspect status --porcelain default/agents/skills/
grep -rniE 'arch|pacman|AUR|sudo|/usr/share' \
     /usr/share/omarchy/default/agents/skills/<name>/*.md     # where the distro claims actually are
```

## Two constraints that decide the SHAPE of the edit

1. **The same `omedora-settings` RPM also serves mutable Fedora hosts.** Never
   blanket-replace Arch facts with bootc facts — write a *distro delta* keyed to the same
   token the commands use: `omarchy-distro` → `arch` | `fedora` | `fedora-ostree`. A doc
   that tells only the bootc truth misleads the mutable host, and vice versa.
2. **`test/byte-identity-test.sh` covers these files too.** Upstream files are
   additive-only; every upstream line you delete or rewrite needs a per-file
   `ALLOW["<path>"]='<the exact deleted line>'` entry in the SAME commit. The pin tag is
   resolved from `omedora/architecture.md`; when that tag is absent from the local
   checkout the audit self-skips locally while still running in CI, so add the allowlist
   entries from the start instead of discovering the churn in CI.

## Verify the shipped text against the LIVE host, not the fork's intent

- `omarchy-distro` — which token this host actually is.
- `omarchy commands --json` (jq over `route|binary|group|summary|requires_sudo`) and
  `omarchy <group> --help` — what exists and how it describes itself.
- **The CLI metadata is NOT proof a route works on this base.** It still advertises
  AUR/pacman commands and summaries on a bootc host. Probe the route itself:

  ```bash
  OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <already-baked-pkg>
  #   exit 0  "'<pkg>' is already baked into the image (or a satisfying flatpak)."
  OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add <unbaked-pkg>
  #   exit 1  "'<pkg>' is not in the image. On an immutable host bake it into the image build
  #            (fedora.toml / Containerfile) and rebase — dnf install cannot …"
  OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-aur-add <pkg>
  #   routes to the SAME bake path: there is no AUR tier to reach
  ```

  The dry run is read-only and exits 1 exactly when the real run would abort the
  migration/install queue.
- Presence probes for every package or tool the text tells an agent to configure:
  `rpm -q <pkg>`. The shipped terminal is `foot`; alacritty/kitty/ghostty are NOT
  installed, so a guide listing all four config paths sends an agent to a file that does
  not exist.
- `sudo -n true` / `sudo -n -l` — no passwordless sudo rules exist on these hosts.

## Claim classes the fork's shipped skill gets wrong on the immutable base

One inventory row each, with the measured evidence attached:

- the distro line ("agentic Arch Linux distribution") and the architecture table's
  **Arch Linux / Base OS** row;
- "Omarchy may grant passwordless `sudo`" — false here, and `sudo` cannot change `/usr`
  anyway;
- `omarchy pkg add` / `omarchy pkg aur add` as the way to install software — the real
  answer is bake it into the image (`build_files/build.sh` / `fedora.toml`) and rebase;
  Flatpak is the only runtime-installable tier;
- `omarchy update` sold as a package upgrade — it applies the image, runs migrations and
  post-update hooks, updates mise/flatpak, then needs a reboot;
- bare `omarchy reinstall` — only `omarchy reinstall configs` ships;
- bug-report / PR routing to upstream `omacom/omarchy` — fork and immutable bugs go to the
  fork's repo, image bugs to the image repo, and the fork's dev conventions are its own,
  not upstream's `AGENTS.md`;
- package and setup-wizard claims (`omarchy install <target>`, `omarchy setup …`) — read
  the verdict out of the image's own map (`build_files/fedora.toml`, ~94 skip entries
  with reasons) instead of asserting one.

The topic guides (`hyprland.md`, `plugins.md`, `theming.md`, `hooks.md`, `capture.md`)
carry no distro claims — leave them untouched, and say so in the plan.

## Deliverable shape, and the cost to state in the plan

Inventory first, then the decision table; no edits until the user says go (the
plan-then-prompt contract elsewhere in this skill):

| file:line | now | becomes | why |
|---|---|---|---|

Decision rows to offer, with a marked default: edit the shipped skill in place as an
`omarchy-distro` delta vs. add a sibling skill directory plus a pointer; correct the wrong
upstream lines with allowlisted deletions vs. append-only (a contradiction left mid-file
is worse than allowlist churn); add a repo test asserting the Fedora claims so an upstream
rebase cannot silently revert them, vs. skip.

State the delivery delay plainly: a text change is a new `omedora-settings` NEVRA → COPR
build (gate the image build on `succeeded`) → image build → rebase/reboot before ANY agent
on the host reads the new text. Editing the checkout alone changes nothing on the running
box. Mechanics: `references/omedora-copr.md`.
