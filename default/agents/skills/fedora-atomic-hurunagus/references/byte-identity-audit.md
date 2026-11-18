# The byte-identity audit (additive-only discipline) — and the pin it silently skips without

Load when: touching an upstream-owned file in an omedora checkout, adding a
`CARRIED`/`ALLOW` entry, or answering "is the port still additive?".

`test/byte-identity-test.sh` is the fork's central discipline gate: every file
that exists in BOTH the upstream pin and the tree must differ only additively, or
its deleted lines must be allowlisted. It is pure git + bash — safe to run on the
live box, unlike the rest of the suite (pitfall 9a).

## The trap: it SKIPS when the pin tag is absent, and says "ok"

```
ok - # SKIP byte-identity audit: pin 'omedora-base-…' not present in this checkout (shallow clone?)
```

The pin comes from `omedora/architecture.md` (pattern
`omedora-base-<date>-omarchy4-<sha>`), and the tag lives in the PARENT repo
(`AndrewGaspar/omedora`), not in the fork — so a normal clone AND the L1 CI job
both skip it. A green run therefore proves nothing: read the step's own output for
`auditing against pin:` before believing an audit result, in CI or locally.

Make it real locally (read-only; no remote has to be added):

```bash
git fetch --depth=1 --no-tags https://github.com/AndrewGaspar/omedora.git \
    refs/tags/<PIN>:refs/tags/<PIN>
bash test/byte-identity-test.sh                          # now really audits
OMEDORA_BASE_TAG=HEAD bash test/byte-identity-test.sh   # bisect your own change only
```

`OMEDORA_BASE_TAG=HEAD` diffs against the last commit instead of upstream, which
is the fast loop — but it compares YOUR change against your own previous commit,
so rewriting lines you committed earlier shows up as "deletions" that are not
upstream deletions at all. Use it to answer "did my edit add a NEW upstream
deletion?", not "is the table correct?", and validate the final table against the
real pin.

## Measured state (2026-11-16, pin 20261104)

With the pin present the gate is **red on the repo as it stands**: 128 files with
undocumented upstream deletions — 118 pruned command families (`bin/omarchy-dev-*`,
XR, openclaw, gaming, hw installers/tests) and 10 files edited in place
(`bin/omarchy-reinstall-configs`, `default/hypr/envs.lua`,
`default/omarchy/omarchy-menu.jsonc`, `etc/fastfetch/config.jsonc`, `icon.txt`,
`install/hardware/all.sh`, `install/provisioning/omarchy-provision-owner.service`,
`install/user/all.sh`, `install/user/first-run/enable-user-units.sh`,
`shell/plugins/panels/weather/Panel.qml`). The tables document ~10 relocations, so
the gate as configured would fail the moment the pin is fetchable. Nothing is
broken by that — the port prunes on purpose — but "the port is additive-only" is
currently a claim, not a check.

## Authoring an entry

- A deleted line must be allowlisted EXACTLY (leading whitespace included), as a
  multi-line single-quoted blob: `ALLOW["path"]='  line one` newline `  line two'`.
  The audit's check is per line text.
- A deliberate divergence that is not a relocation goes in `CARRIED["path"]='rationale'`
  instead: it is exempt from additive-only, must state why, and the audit reports
  how many upstream lines it drops (443 for a whole deleted workflow). CARRIED also
  self-cleans — when the file stops differing (upstream landed it, or absorbed the
  change) the stale-entry guard prints a WARNING to stderr, so drop the entry then.
  Note the stale guard prints warnings for EVERY entry whenever you use
  `OMEDORA_BASE_TAG=HEAD`; that is the baseline, not rot.
- Single quotes inside a blob are written with the shell escape `'\''`.
- Prefer relocation (the upstream line re-added verbatim inside the Arch/else arm)
  over deletion: it keeps the diff additive and documents itself.
- Deleting an upstream FILE (e.g. a workflow the fork cannot run) is a divergence:
  record it as CARRIED with the reason, or the next pin rotation re-imports it and
  the audit flags the deletion.
