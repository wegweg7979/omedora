# Reporting Issues and Submitting PRs

Read this when the user wants to report an Omarchy bug, suggest a feature, or
contribute a fix upstream.

## Fedora hosts (omedora / hurunagus): route by what is broken

This checkout IS the Fedora port, so the target is not always upstream:

| Broken | Where it belongs |
|--------|------------------|
| Omarchy itself on Arch — shell, menu, Hyprland defaults, upstream behavior | `omacom/omarchy`, as below |
| The port: a `bin/fedora/` or `bin/omarchy-ostree/` path, an `install/packages/fedora.toml` mapping, a migration's Fedora arm, the distro dispatch | **this repository**, `wegweg7979/omedora` |
| The image: what is baked (packages, COPR payload, first-boot provisioning, drivers, kernel) | the image repo, e.g. `wegweg7979/hurunagus-hyprland` |

On a bootc image `/usr/share/omarchy` is read-only and holds the *installed* copy, so a
fix is real only once it is in this repository, built into a new `omedora-settings` RPM,
baked into an image and rebased. Report the version you saw (`omarchy version` on the host
runs the shipped copy, not your checkout) together with the deployment (`rpm-ostree
status`) — a stale deployment explains most "but I already fixed that" reports.

Development conventions for the port are this repository's own: `AGENTS.md` plus the
`omedora/` docs (`README.md`, `architecture.md`, `packages.md`).

Omarchy lives at https://github.com/omacom/omarchy. Route requests to the
right place:

- **Verified bugs** -> GitHub issues. Issues are for validated bugs only, not
  support requests.
- **Feature ideas and suggestions** ->
  https://github.com/omacom/omarchy/discussions/categories/suggestions
- **Support and "is this a bug?" questions** -> the Discord community at
  https://omarchy.org/discord. Start here when the problem isn't clearly a bug
  in Omarchy itself.

## Filing a Good Bug Report

The bug template asks for system details (CPU, GPU, Omarchy version), a
description with steps to reproduce, and diagnostics. Gather them:

```bash
omarchy version

# Generate the diagnostic log (also written to /tmp/omarchy-debug.log)
omarchy debug --no-sudo --print

# Interactive variant: `omarchy debug` offers to upload the log to
# logs.omarchy.org (expires after 24h) and prints a shareable URL to
# include in the issue.
```

**Capture the problem on screen.** A screenshot or short recording of the bug
is often worth more than the description — see [`capture.md`](capture.md) for
`omarchy capture screenshot` and `omarchy screenrecord`. Keep recordings short
and focused on the misbehavior. GitHub issue attachments are added by
drag-and-drop in the web form, so save the capture and hand the user the file
path to attach (`gh` cannot upload media).

For screen-recording failures specifically, rerun with
`OMARCHY_SCREENRECORD_DEBUG=true` and attach `$XDG_RUNTIME_DIR/omarchy-screenrecord.log` (or `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omarchy-screenrecord.log` without a session runtime directory).

File the issue with `gh` when available:

```bash
gh issue create --repo omacom/omarchy --title "..." --body "..."
```

Include: what happened, what was expected, steps to reproduce, system details,
the debug log URL (or attached log), and the capture.

## Submitting a PR

Never develop against `/usr/share/omarchy`. Clone a working copy instead:

```bash
gh repo fork omacom/omarchy --clone
cd omarchy
```

Fixing the **port** instead? Clone this repository (`wegweg7979/omedora`) — the same rule
applies: never develop against `/usr/share/omarchy`. A distro sibling (`bin/fedora/`,
`bin/omarchy-ostree/`) is a change to the port, and belongs here, not in an upstream PR.

Follow the repository's own `AGENTS.md` for style, testing, and commit
conventions — it is the authority on contributions. Keep commits atomic, run
`./test/all` before pushing, and open the PR with `gh pr create`. A PR that
fixes a visual problem should include before/after captures (again, see
[`capture.md`](capture.md)).
