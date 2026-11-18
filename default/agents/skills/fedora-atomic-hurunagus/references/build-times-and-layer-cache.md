# Build times and the layer cache

The ublue/image-template bootc build is 20-30 minutes by default and most of it
is avoidable work. This file is the measured anatomy, the staged-cache pattern
that replaces the `--no-cache` hammer, and the checks that prove a restructure
without a full build.

## 1. Measure per step before saying anything about speed

```bash
gh run view <run-id> -R <owner>/<repo> --json jobs
# then compute (completedAt - startedAt) per jobs[].steps[]
```

A 27-minute hurunagus-hyprland image build broke down as:

| Step | Time |
|---|---|
| Maximize build space | 65s |
| Build Image (`RUN /ctx/build.sh` layer) | 749s |
| Rechunk with rpm-ostree | 610s |
| Push to GHCR | 157s |
| sign / tag / lint | <15s |

The bluebuild comparison run was a single 393s step doing build+push+sign. Do
not compare totals across templates until you know they do the same steps on
comparable content — usually they do not.

## 2. Why bluebuild looks 4x faster

- **It does not rechunk.** The action's inputs in its own log read
  `rechunk: false`, `chunkah: false`, `build_chunked_oci: false`. Check the log
  before theorising about caching.
- **One layer per recipe module.** Its generated Containerfile is multi-stage
  with many small RUNs (`#47 [stage-5 1/16] RUN …`), so unchanged modules are
  reusable and BuildKit streams layers to the registry during the build — there
  is no separate serial push step.
- **Often less content.** Read the recipe for commented-out heavy modules
  (`#- type: custom-kernel`) and count packages before crediting the builder.
- **Its actions/cache hit is usually just the binfmt helper image** (seconds),
  not a layer cache. Do not repeat "bluebuild caches the build" without
  evidence from the log.

## 3. The ublue template's two time sinks

1. `just ostree-rechunk` (rpm-ostree rechunker) — the template's own comment
   calls it optional and it only shrinks client-side deltas. ~10 minutes.
   Gate it instead of paying it on every push:

   ```yaml
   - name: Rechunk with rpm-ostree
     if: github.event_name == 'schedule' || inputs.rechunk
   ```

   Keep the rechunked build as the one users update from (weekly schedule) and
   say explicitly that a push-built `:latest` is no longer rechunked.
2. One giant `RUN /ctx/build.sh` layer. Its cache key is the instruction text +
   base image, so any edit invalidates all of it, and `NO_CACHE=1` (used to keep
   a mutating COPR fresh) throws the cache away every run.

## 4. Pattern: stages ordered by volatility, busted by ARGs

Containerfile — one phase per RUN, each referencing the arg that may bust it:

```dockerfile
ARG OMEDORA_BUST=0
ARG KERNEL_BUST=0
ARG ALL_BUST=0

RUN --mount=from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    ALL_BUST="${ALL_BUST}" /ctx/build.sh base

RUN --mount=from=ctx,source=/,target=/ctx \
    ALL_BUST="${ALL_BUST}" KERNEL_BUST="${KERNEL_BUST}" /ctx/build.sh kernel

RUN --mount=from=ctx,source=/,target=/ctx \
    ALL_BUST="${ALL_BUST}" OMEDORA_BUST="${OMEDORA_BUST}" /ctx/build.sh fresh
```

build.sh — phases as functions; **bash does not require indentation inside a
function body**, so existing sections move verbatim and the diff stays readable:

```bash
PHASE="${1:-all}"
phase_base()   { … }   # repos, the whole package install, system files, services
phase_kernel() { … }   # kernel swap + initramfs
phase_fresh()  { … }   # dnf5 --refresh upgrade of the volatile package, re-mirror, clean
case "$PHASE" in base|kernel|fresh) phase_$PHASE ;; all) phase_base; phase_kernel; phase_fresh ;; esac
```

CI pass-through (Justfile recipe gains an `EXTRA_BUILD_ARGS` lever):

```yaml
EXTRA_BUILD_ARGS: >-
  --build-arg OMEDORA_BUST=${{ github.run_id }}
  ${{ (github.event_name == 'schedule' || inputs.fresh)
      && format('--build-arg ALL_BUST={0} --build-arg KERNEL_BUST={0}', github.run_id) || '' }}
```

Rules that make this safe:

- **Keep the volatile package installable in the cached phase too**, so files
  the cached phase copies out of it exist (e.g. a theme mirrored from
  `/usr/share/<pkg>/…`). The volatile phase then *upgrades* it and redoes the
  mirror — otherwise a package upgrade leaves a stale copy behind.
- **Freshness policy must be stated per stage**: every build (`OMEDORA_BUST`),
  weekly/manual (`KERNEL_BUST`, `ALL_BUST`), or never. An always-cached kernel
  layer silently freezes the kernel until someone changes build.sh.
- **`ALL_BUST` reproduces the old `--no-cache` exactly**, so keep one lever that
  still means "rebuild everything" for release runs.
- No-arg invocation must keep the all-phases behaviour, so a workstation
  `just build` is unchanged.

## 5. CI cache reality — check before promising a speedup

- GitHub-hosted runners start with an **empty podman store**. Without a
  persisted cache, splitting into stages does the same work with more layers:
  no CI gain.
- The runner's podman is 4.9-era buildah: **no `--cache-to`**, so registry
  layer caching is unavailable. Gate the flags on capability so local builds
  use them and CI silently does not:

  ```bash
  if [[ -n "${BUILD_CACHE_REF:-}" ]] && podman build --help 2>/dev/null | grep -q -- '--cache-to'; then
      PODMAN_BUILD_ARGS+=(--cache-from "${BUILD_CACHE_REF}" --cache-to "${BUILD_CACHE_REF}")
  fi
  ```

- Persisting CI state means caching `/var/lib/containers/storage` (root-owned:
  chown to the runner user before the post-run save, back to root before
  building) — multi-GB, so weigh the save time against the win.
- **Forecast the CI delta as "rechunk removal" only.** Staged layers pay off
  immediately for local `just build` reruns and for CI only once a cache
exists.

## 6. Verifying a restructure without a 20-minute build

- **Assert the moved bodies are byte-identical** to the original line ranges
  programmatically (slice both files, compare lists). Reading a 500-line diff by
  eye is not verification.
- `bash -n build_files/build.sh`
- `just --unstable --fmt --check -f Justfile` (this is what `just check` runs in
  CI, so a formatting slip fails the build before it starts)
- `just --list` — proves every recipe still parses
- Parse the workflow YAML: PyYAML is often absent, `ruby -ryaml -e
  'YAML.load_file("…")'` works.
- **Prove ARG cache-keying with a throwaway busybox Containerfile** before
  trusting it in the real build:

  ```dockerfile
  FROM busybox
  ARG A=0
  ARG B=0
  RUN echo "a=${A}" > /a.txt
  RUN echo "b=${B}" > /b.txt
  ```

  Same args → every step reports `Using cache`; change `B` → only the B step and
  later ones rebuild; change `A` → A and later rebuild. **Verify contents with
  `podman run --rm <img> cat /b.txt`** rather than trusting the log: buildah
  prints `--> Using cache` lines in ways that read misleadingly, and only the
  file contents settle it.
- A restructure that cannot be exercised locally needs the CI path that builds
  without publishing: `pull_request` triggers build but skip the push/sign steps
  (they are guarded on the default branch), so a PR is the timing comparison.


<!-- absorbed from SKILL.md 2026-11-12 -->

## Build time: measure, then stage the layers

- **Never quote a build-time difference without the per-step breakdown.**
  `gh run view <id> -R <o>/<r> --json jobs` carries `startedAt`/`completedAt`
  for every step; the ublue job splits into Maximize space / Build Image (the
  `RUN build.sh` layer) / Rechunk / Push, and the answer is always in one of
  those. A 27-minute hyprland build was 749s building plus 610s rechunking.
- **`just ostree-rechunk` is ~10 minutes of pure delta-sizing and the template
  says it is optional.** Bluebuild does not rechunk at all, which is most of why
  a "same settings" bluebuild image finishes in a quarter of the time — before
  theorising about caching, check the other side's action inputs (`rechunk:`,
  `chunkah:`) and its recipe for commented-out heavy modules. Gate rechunk on
  schedule/dispatch; keep the rechunked build as the one users update from.
- **A single `RUN /ctx/build.sh` layer is the other half.** Its cache key is the
  instruction text + base image, so any edit re-runs the whole package
  transaction and `NO_CACHE=1` (the COPR-freshness hammer) re-runs it every
  time. Split the script into phases ordered by volatility and bust each with
  its own build arg — `references/build-times-and-layer-cache.md` has the
  Containerfile, the phased `build.sh` shape, the freshness policy and the
  ARG-bust verification.
- **A staged build alone does NOT speed CI up.** GitHub runners start with an
  empty podman store and the runner's podman has no `--cache-to`, so stages only
  pay off for local `just build` reruns until a cache is persisted. Forecast the
  CI delta as the rechunk removal and say so out loud.
- Keep the no-arg invocation equivalent to "all phases" so a workstation
  `just build` behaves exactly as before, and assert the moved phase bodies are
  byte-identical to the original line ranges rather than eyeballing the diff.
