# GitHub Actions CI/CD Reference

## build.yml (container image build + push)

- **Trigger:** `push` (main), `pull_request` (main), `schedule` (cron: `00 06 * * 2` = Tuesday 06:00 UTC), `workflow_dispatch`
- **Job:** `build_push` — builds and pushes to ghcr.io
- **Permissions:** `contents: read`, `packages: write`, `id-token: write` (OIDC)
- **Key steps:** checkout → remove-unwanted-software → setup-just → check just syntax → image name → default tag → prepare env → build image → rechunk → generate build tags

## build-disk.yml (disk image build)

- **Trigger:** `pull_request` on `disk_config/` files, or `workflow_dispatch` with inputs (`platform`, `upload-to-s3`)
- **Job:** `build` — builds qcow2 and anaconda-iso via `osbuild/bootc-image-builder-action`
- **Matrix:** `disk-type: ["qcow2", "anaconda-iso"]`
- **Key inputs:** `builder-image`, `config-file`, `image`, `chown`, `types`, `additional-args`
- **Permissions:** `contents: read`, `packages: read`, `id-token: write`

## Concurrency

- Group: `${{ github.workflow }}-${{ github.ref || github.run_id }}` with `cancel-in-progress: true`
- **A push that QUEUES a run cancels the in-flight one for the same ref; a push that queues
  nothing cannot.** `paths-ignore: '**/README.md'` means a doc-only push starts no run, so it is
  the safe way to land README fixes while a 20-30 minute build is running (verified 2026-11-16:
  the build for `fe90aae` kept going untouched through a README-only push to the same branch).
  Any push with a non-doc change does cancel it — the superseded run then reads `cancelled`,
  which is supersession, not failure.
- **Fetch before pushing: these repos also receive doc-only commits made off this machine.**
  Measured the same day in `hurunagus-hyprland`: origin/main carried 7 README-only web-editor
  commits ("streamline content", "Refine README description for clarity") plus a
  `build_files/fedora.toml` prose line the local checkout lacked, so `git push` was a
  non-fast-forward. `git fetch` and read `git status -sb`'s `[ahead N, behind M]` before
  pushing, rebase, and **re-read any file the remote also touched instead of letting the replay
  pick a side** — there the remote's newer prose was the factually WRONG version and the
  replayed local commit was right (see `gtk-dark-theming-fedora.md`).

## Image naming

- Registry: `ghcr.io/<owner>/<repo>`
- Tags: `latest`, `<tag>-<git-sha>`, `<tag>-<date>-<git-sha>`, `<date>`, `<tag>-<date>`, `<tag>`

## The two-workflow split, and the exact invocations

The repos split CI into two files, and **the split is the point** — never merge them:

- **`build.yml` = container image ONLY, no bootc-image-builder in it.** Runner
  **`ubuntu-24.04`**. After `setup-just` it runs `just check`, then the build itself as
  **`sudo -E $(command -v just) build`** — `sudo` because the recipe needs privileges,
  **`-E`** so the env `setup-just` exported survives, and `command -v just` to resolve
  the installed binary rather than trusting PATH under sudo — then `just tag-images` and
  the GHCR push. **cosign signing is optional** (not on by default).
- **`build-disk.yml` = ISO + QCow2 via `osbuild/bootc-image-builder-action`**, pinned to
  `@028e4d28330efe546229eb9cb52aee78174d2347`, as a **matrix of `qcow2` +
  `anaconda-iso`**. Keeping disk-image work out of `build.yml` means a disk-config change
  never re-pushes the container image, and vice versa.
- **The Justfile pulls its env from `image-template.env` via `dotenv`** — that file, not
  the workflow, is where `IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC`,
  `IMAGE_KEYWORDS`, `IMAGE_LOGO_URL`, `DEFAULT_TAG` and `BIB_IMAGE` live. Renaming the
  image or changing the BIB image is an env edit, not a workflow edit.

## CI for a repo that is NOT an image build

For plain script/tool repos (a helper CLI, a rebase tool): two jobs on `ubuntu-24.04`,
no `just`, no ghcr push, no BIB.

- **lint**: `bash -n` every shell file → `shellcheck -S warning <files>` → the executable
  bit and shebang survive a clone → a consistency check that the README lists everything
  the tool prints → the CLI answers `--version`/`--help`/`--list` with no system to
  inspect.
- **test**: run the repo's own sandboxed suite verbatim. That is only safe if the suite
  needs neither root nor network; a suite that reaches the live desktop stays manual.
- Pin severity at `-S warning` and say why in a comment: style-level rules fight
  deliberate `${VAR:-}` defaults and quoted globs, so `style` turns every future edit into
  a lint argument.

### Keep the README from drifting away from the tool's own table

A tool with an embedded target/option table drifts from its README silently. Lint the
pair instead of trusting review:

```bash
rc=0
while read -r name _; do
  [[ -n $name ]] || continue
  pat=$(printf '`%s`' "$name")
  grep -qF "$pat" README.md || { echo "::error file=README.md::README does not list '$name'"; rc=1; }
  done < <(./tool --list | sed -n '1,/^$/p' | tail -n +2)
exit "$rc"
```

Take the table REGION only (`sed -n '1,/^$/p'`) and skip the header row — a footer line
that names refused or dead entries otherwise trips the check. Run the snippet locally
before shipping it: a lint step that fails on its own first CI run is worse than none.

### Pin every action to a commit SHA, and re-pin when the runner complains

```bash
# tag -> commit, dereferencing annotated tags (a lightweight tag's sha IS the commit)
sha=$(gh api repos/actions/checkout/git/refs/tags/v5 --jq '.object.sha')
if [ "$(gh api repos/actions/checkout/git/refs/tags/v5 --jq '.object.type')" = tag ]; then
  gh api "repos/actions/checkout/git/tags/$sha" --jq '.object.sha'
else
  echo "$sha"
fi
```

Write it as `uses: owner/action@<sha> # vN` so the pin stays readable. **A green run can
still carry `##[warning] ... is deprecated. The following actions target Node.js 20 ...:
<action>@<sha>` in its log** — the badge hides it, a log grep does not. Resolve the newer
major, re-pin, and prove the fix by grepping the NEW run's log for that warning (expect 0
hits). checkout v4 targets the deprecated Node 20 runtime; v5 does not.

### Run shellcheck locally before CI ever sees it

Lint you have never run locally is a red pipeline waiting to happen, and no sudo is
needed — the static release binary is enough:

```bash
cd "$TMPDIR" && curl -fsSL -o sc.tar.xz \
  https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz \
  && tar -xf sc.tar.xz && ./shellcheck-v0.10.0/shellcheck -S warning <files>
```

First-run findings on this class of tool are all real and cheap: unused variables
(SC2034), a non-constant `source` of an os-release seam (SC1090 → add
`# shellcheck source=/dev/null`), `VAR=word` assignments shellcheck reads as command
substitution (SC2209 → quote them), unquoted `find $(...)` arguments (SC2046).


<!-- absorbed from SKILL.md 2026-11-12 -->

## GitHub Actions patterns

### Reading the logs of an IN-PROGRESS run (2026-11)

- The job-log blob only exists once the job COMPLETES: `gh api repos/<o>/<r>/actions/jobs/<job_id>/logs` returns `BlobNotFound` (HTTP 404) mid-run, and the anonymous raw-logs URL (`/actions/runs/<id>/job/<job_id>/logs`) returns `Not Found` even for a PUBLIC repo. GitHub's live log view needs a signed-in browser — an anonymous tab of the job page just says `Sign in to view logs`, so do not plan on scraping it.
- Mid-run signal that needs no auth: `gh api repos/<o>/<r>/actions/jobs/<job_id> --jq '.status, (.steps[] | "\(.number). [\(.status)/\(.conclusion // "-")] \(.name)")'`. A single step can contain the whole `build.sh` port (plus the Containerfile's `bootc container lint`), so "step N succeeded" is often the real yes/no — a far cheaper signal than waiting for the log.
- Best split for answering "will it work?" mid-run: read the step-level status yourself and ask the user (who has the signed-in browser) to paste the log tail. Their paste of the green `::group:: Swapping in the CachyOS kernel` block arrived long before the run finished.
- Authenticated `gh` polling is cheap (5000 req/h); the 60/h wall only bites unauthenticated watchers (see COPR gotcha 10).
- **Waiting for a run you own: `gh run watch <id> --exit-status --interval 10`**, then read the verdict per STEP rather than per job: `gh run view <id> --json headSha,conclusion,jobs --jq '"sha \(.headSha[0:7]) \(.conclusion)", (.jobs[] | "  \(.name): \(.conclusion)")'`. gh is authenticated, so no rate-budget gymnastics are needed here.
- **`gh --template` renders a big integer run id in SCIENTIFIC NOTATION**, so `{{.databaseId}}` printed `4.3923873783e+10` — unusable as the `<id>` argument for `gh run watch`/`gh run view`. Take ids with `--jq` (`gh run list -R <o>/<r> --limit 1 --json databaseId --jq '.[0].databaseId'`), and echo the id into a scratch file when a background watcher will need it later. Use the `--template` form for sha/status fields, not for ids.
- **Assert a specific line out of the finished log instead of trusting the green badge**: `gh run view <id> --log | grep -E 'checks passed|deprecated'` — that grep, not the badge, is what caught a pinned action sitting on a deprecated Node runtime while every job read `success`. The log is ANSI-coloured and the ECHOED SCRIPT BODY carries `\x1b[36;1m`-style prefixes, so use `grep -a` and strip SGR first (`sed 's/\x1b\[[0-9;]*m//g'`) when what you are matching is a line of the script rather than the step's own output — otherwise the line you know is there greps clean and you conclude the step never ran.

- **build.yml**:
  - Trigger: push/PR/schedule (cron: 00 06 * * 2)
  - Jobs: `build_push` - builds and pushes to ghcr.io
  - Steps: checkout, remove-unwanted-software, setup-just, check, build image, rechunk, generate tags
  - Permissions: `packages: write`, `id-token: write` (for OIDC)
- **build-disk.yml**:
  - Trigger: PR with disk_config changes, or workflow_dispatch
  - Jobs: `build` - builds qcow2 and anaconda-iso via bootc-image-builder-action
  - Uses: `osbuild/bootc-image-builder-action@028e4d28330efe546229eb9cb52aee78174d2347` (main)
  - Input: `platform` (amd64 or arm64), `upload-to-s3`
- Key labels added to images:
  - `io.artifacthub.package.*` - for ArtifactHub
  - `org.opencontainers.image.*` - for OCI compliance

## Inheriting an upstream workflow: check its branch + secret assumptions FIRST

A workflow that arrives with the upstream tree can be permanently red in the fork
without anything being wrong with the fork's code, and a daily red job is worse
than no job — it teaches everyone to ignore red. Two probes settle it before you
debug anything:

```bash
gh api repos/<parent>/branches --jq '.[].name'      # does the branch it pins even exist?
gh secret list                                       # does it have the secrets it needs?
gh workflow list                                     # is it still registered after a deletion?
```

Worked example (2026-11-16): `.github/workflows/i18n-sync.yml` is upstream's
daily translation sync, hardcoded to `quattro` — the checkout `ref:`, the PR
`base=`, and its `push: branches:` — and NEITHER the fork nor the parent has that
branch (upstream renamed to `omedora-4` and left the file stale), so every
scheduled run died at its first `actions/checkout` (Nov 13-16 red) and its push
trigger could never fire. It also wanted `MUSE_API_KEY` + `I18N_SYNC_TOKEN`, while
the repo carries only `COPR_API_TOKEN` — so no configuration could make it succeed
in the fork. Retirement, not repair: `git rm` the workflow, record it as a CARRIED
entry in the byte-identity audit (a whole deleted file = a divergence the next pin
rotation would otherwise re-import and flag), and add one additive paragraph to
the doc that describes it (`docs/i18n.md`) so the manual does not document a
workflow the fork does not have. Keep the neighbouring `i18n-check.yml`-style
PR check — that one needs no secrets and guards a real invariant.

Two process notes from doing it: `git add -A <path>` ABORTS the whole add when one
pathspec no longer exists (a staged deletion is not a pathspec), which silently
commits only the already-staged part — check `git show --stat` after committing a
deletion rather than trusting the commit's exit code; and a push that lands two
commits makes the first run show `cancelled`, which is the concurrency group, not
a failure.


## Reporting a long build's outcome when the user is AFK

This user goes AFK during a 20-30 minute image build and expects to be reached on
**Slack**. Send through `connectors__slack__SEND_MESSAGE` to the gateway bot's DM
with them, **`<slack-id>`** (verified working 2026-11-16) — the connector's own
DM with them (`<slack-id>`) and the bot's configured `home_channel`
(`<slack-id>`) both fail (`channel_not_found` / `not_in_channel`, because DM
channel ids are per-app and the bot was never invited to the channel). Any target
is DISCOVERED, never guessed: `platforms.slack.home_channel.user_id` in
`~/.hermes/config.yaml` names the user, and `LIST_CONVERSATIONS` with
`types=im,mpim,...` returns the `D...` channel whose `user` field matches it. Do not
DM a `D...` id you cannot map that way — the Slack API returns DM partners as bare
user IDs with no names, and four DMs look equally plausible; an unmapped DM could
be a stranger. Read the message back (`FETCH_CONVERSATION_HISTORY`) after sending,
then send ONE result message rather than a running commentary.

Waiting for the run: `gh run watch <id> -R <owner>/<repo> --exit-status --interval 60`
with a generous timeout — a foreground request over 600s is promoted to a tracked
background process that notifies on completion, which is the right shape for a build.
Do not hand-roll a backgrounded `sleep` polling loop instead.

Then verify what actually SHIPPED rather than merely that CI was green:
`skopeo inspect docker://<image>:latest` for the digest plus the `...image.version`
label (must read `latest.<date>-<sha>` of the pushed commit); for a package you
added, either read the build log for the block's own echo (`rclone installed:
rclone v1.75.2`) or pull the image and probe it (`podman run --rm <img> rpm -q
rclone`, and for an enabled unit check the
`/etc/systemd/system/multi-user.target.wants/<unit>.service` symlink). Report per
claim: what is verified by output, and what is only "CI went green".
