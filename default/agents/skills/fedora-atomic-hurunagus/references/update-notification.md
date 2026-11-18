# Omarchy update-notification rework for immutable bootc

The bar's update badge is **thin** — all real logic lives in CLI scripts. When
reworking it for a Fedora **bootc** image, keep the widget untouched by
preserving its contract.

## The chain (read these to diagnose)

1. `~/.config/omarchy/shell.json` bar layout -> widget `SystemUpdate.qml` (in
   `/usr/share/omarchy/shell/plugins/bar/widgets/`). Polls every 6h; shows the
   refresh icon iff `omarchy-update-available` exits 0; clicking runs
   `omarchy-update` in a terminal.
2. `omarchy-update-available` dispatches on distro (`omarchy-distro`): for
   `fedora` it execs `/usr/sbin/fedora/update-available`, else the Arch
   `checkupdates` branch.
3. Mutable checker: `dnf check-upgrade --refresh --repo <omedora-copr-id>`.
4. Runner `omarchy-update` (Fedora-aware copy in `~/.local/bin/`) delegates to
   `ujust update` (rpm-ostree + flatpak + distrobox).

**Contract the widget depends on — must not change:**
- exit 0 = updates available (list on stdout); exit !=0 = up to date
- state files under `~/.local/state/omarchy/updates/{packages,aur,available,error,checked-at}`

## The key pitfall: dnf is the wrong signal on immutable

On bootc, `dnf check-upgrade` is meaningless for updates. The omedora/omarchy
RPMs are baked into the container image at build time (`RUN build.sh` inside
the image, not layered on the host), so there are no separately-updatable RPMs
on the live system. A COPR dnf check misses image rebuilds and diffs an RPM DB
that isn't the update mechanism. "Is there an update?" on bootc means **is
there a newer container image than the deployed one?**

## Detect immutable vs mutable before branching

Do NOT assume the running system fits your expectation — verify:
- immutable: `test -e /run/ostree-booted` (present on all bootc/ostree hosts),
  or `rpm-ostree status` shows `ostree-image-signed:docker://<registry>:latest`
  origins with a multi-entry `Deployments` list.
- mutable omedora: no `/run/ostree-booted`; omarchy/omedora COPR configured in
  `/etc/yum.repos.d/`.

## Correct immutable update checks

Read the deployment JSON ONCE and derive every value from it
(`rpm-ostree status --json` — no text parsing):

```bash
json=$(rpm-ostree status --json 2>/dev/null || true)
# real image digest of the booted deployment (see digests pitfall below)
booted_digest=$(printf '%s' "$json" | jq -r \
  '.deployments[] | select(.booted==true) | ."container-image-reference-digest" // empty' | head -1)
# registry ref for skopeo: strip the ostree-image-signed: prefix (see pitfall)
raw_ref=$(printf '%s' "$json" | jq -r \
  '.deployments[] | select(.booted==true) | ."container-image-reference" // empty' | head -1)
image_ref="docker://${raw_ref#*docker://}"
```

Primary (no network, mirrors how the OS itself stages):
`rpm-ostreed-automatic.timer` runs with `AutomaticUpdates: stage`, so a newer
image lands as a staged (non-booted) deployment. **Key off the `.staged` FIELD,
never off timestamps and never off a count of non-booted deployments:**

```bash
# Present somewhere -> AUTHORITATIVE. Only .staged==true means a reboot is pending.
if printf '%s' "$json" | jq -e 'any(.deployments[]; has("staged"))' >/dev/null 2>&1; then
  n=$(printf '%s' "$json" | jq '[.deployments[] | select(.staged==true)] | length' || echo 0)
  (( n >= 1 )) && staged_available=1
else
  # ONLY for rpm-ostree too old to emit .staged: numeric max_by timestamp compare.
  newest_ts=$(printf '%s' "$json" | jq -r '.deployments | max_by(.timestamp) | .timestamp')
  booted_ts=$(printf '%s' "$json" | jq -r '.deployments[] | select(.booted==true) | .timestamp' | head -1)
  [[ -n $newest_ts && -n $booted_ts && $newest_ts -gt $booted_ts ]] && staged_available=1
fi
```

The gate must be `has("staged")`, **not** "is the count of `select(.staged==true)`
non-empty": that selector yields a non-empty `"0"` for an explicit
`staged:false`, so a count-based gate silently routes every modern host into the
timestamp fallback — which is the phantom-badge bug in the pitfall list below.

Fallback (network poll, when auto-stage is off) — compare remote vs deployed
digest with `skopeo` (ships in the ublue base image):

```bash
remote=$(timeout 60 skopeo inspect --format '{{.Digest}}' "$image_ref" 2>/dev/null)
if [[ -n $remote && $booted_digest != "$remote" ]]; then → "new image", exit 0
elif [[ $remote == "$booted_digest" ]]; then → current, exit 1
fi
```

### Digests pitfall (roots of the two classic false "update available" bugs)

- **The phantom badge (fixed 2026-11-13, omedora `a3e94dc5c`): trust `staged:false`, never fall back to timestamps on a modern host.** Measured on workstation: booted `latest.20261112-95e6a12` (ts 04:39:20Z) with the **rollback sibling NEWER** — `latest.20261112-6ad8d5a` (ts 15:11:36Z) — and `staged:false` on BOTH. A rebuilt image off the same git commit keeps the older commit time, so "sibling newer than booted" is normal, not an update. The badge then read "update available" permanently while `rpm-ostree`/bootc had nothing to apply (registry `latest` digest `sha256:3f8f72f9…` was byte-identical to the booted digest). Diagnose in three read-only commands, in this order:
  1. `rpm-ostree status --json | jq -r '.deployments[] | "booted=\(.booted) staged=\(.staged) ts=\(.timestamp) ver=\(.version)"'` — any `staged=true`? If not, nothing is pending, whatever the timestamps say.
  2. `timeout 60 skopeo inspect --no-tags docker://<image-ref> | jq -r .Digest` vs the booted `container-image-reference-digest` — equal means no new image exists.
  3. `journalctl -u rpm-ostreed-automatic.service -n 20` — a run that fetched and created no new deployment is another "nothing to do".
  Note `bootc upgrade --check` needs root (`This command must be executed as the root user`); the three commands above do not.
- **Test the SHAPE, not just the timestamps.** The checker's own suite had two fixtures and neither covered `staged:false` on both deployments with a newer sibling — the fixture nearest it had the sibling *older*, so the bug shipped green. When reworking this checker, add the live shape plus the two no-`staged`-field legacy cases (present-field shapes must ignore timestamps; absent-field shapes must still use them).
- **Never compare `.checksum` to a registry digest.** `.checksum` is the ostree
  commit hash; `container-image-reference-digest` is the real OCI image digest.
  A commit hash never equals a registry digest, so the check always fires.
  Always use `.container-image-reference-digest` (and `.origin` is `null` in
  JSON — it only appears in text output, so don't rely on it).
- **Never treat every non-booted deployment as a pending update.** The rollback
  deployment is also `booted==false` and older; a naive count is always ≥1.
  Compare `max_by(.timestamp)` against the booted timestamp.
- **`container-image-reference` is already `ostree-image-signed:docker://<ref>`.**
  Prepending a second `docker://` makes skopeo fail with an invalid ref. Strip
  everything up to and including `docker://`, then add one `docker://` back.

### `write_state` newline pitfall

The checker writes `~/.local/state/omarchy/updates/available` and the widget
keys on it being non-empty. When there is NO update, truncating with
`printf '%s\n' ""` writes a single newline, making the file non-empty → the
widget shows a phantom update. Truncate with `: >` when the list is empty, and
only `printf` when there is actually content (same rules for `packages`).

## Rework shape (keep the widget contract)

- Branch on `/run/ostree-booted` inside the dispatcher (`omarchy-update-available`
  `case`) or within `fedora/update-available`: immutable -> ostree/image check;
  mutable -> existing dnf COPR check. Same exit code + stdout + state files, so
  `SystemUpdate.qml` needs zero QML changes.
- The widget's click already runs `omarchy-update`, which delegates to
  `ujust update` (rpm-ostree aware). The real gap: staging an image takes
  effect only on **reboot** — surface a "reboot to apply" prompt/flag after a
  successful upgrade (optionally a second IpcHandler message), rather than
  pretending the download was the update.

## Checker vs runner

The existing override in `references/omarchy-update.sh` is only the **runner**
(what runs when clicked). The **checker** (`omarchy-update-available` and its
`fedora/update-available` sibling) is what powers the notification and is the
mutable-model code that must be reworked for bootc. Don't stop at the runner.


<!-- absorbed from SKILL.md 2026-11-12 -->

## Omarchy updater override (Fedora atomic)

The default Omarchy updater is Arch/pacman-based and fails on Fedora/rpm-ostree
immutable systems. It is TWO pieces, and only the runner is overridden by the
script below:

- **Runner** (`omarchy-update`, runs on click) — replace with a script that
detects the distribution and delegates to `ujust update` (rpm-ostree + flatpak
+ distrobox).
- **Checker** (`omarchy-update-available` -> `fedora/update-available`, powers
the bar badge) — the stock Fedora checker does `dnf check-upgrade` against the
omedora COPR, which is the wrong signal on a bootc host (RPMs are baked into
the image; there is no live RPM DB to diff). On immutable it branches on
`/run/ostree-booted` and keys off rpm-ostree's OWN `.staged` deployment flag
(see COPR gotchas 5) — NOT a skopeo/registry digest poll, which reports a false
alarm because the `latest` tag moves on every same-commit rebuild. See
`references/update-notification.md` and gotcha 5 in the COPR build gotchas section.

- Full script: `references/omarchy-update.sh`
- Install: copy the script to `system_files/usr/local/bin/omarchy-update` in the
  repo; the build installs it to `/usr/local/bin/omarchy-update` in the image
- PATH: `/usr/local/bin` precedes `/usr/sbin`, so the custom script wins
- `ujust update` runs: `rpm-ostree update` (staged → reboot), `flatpak update -y`,
  `distrobox upgrade -a`
