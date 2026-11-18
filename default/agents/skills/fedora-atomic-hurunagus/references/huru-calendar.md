# Huru Calendar (`huru-calendar`, fork of Dux Calendar)

The user's iCloud calendar stack: `~/huru-calendar` (github `wegweg7979/huru-calendar`,
MIT fork of `duxlabs-dev/dux-calendar`), shipped into the hurunagus-hyprland image.

## The shape that was chosen (2026-11)

**Headless daemon + Omarchy bar widget, NOT a repackaged desktop app.** The decision
rule: reuse the sync ENGINE, replace the UI.

- dcal's Go core already implements iCloud properly — CalDAV discovery, Apple's
  `calendar-color` extension, iCloud's "creator upgraded these reminders"
  placeholder VTODO, iCloud 404 propstats for stale invites, rrule expansion,
  keyring, reminders, ICS/vcs import. Re-implementing that as a plugin is weeks
  of work for a worse result.
- The app's own Quickshell window/tray is what a plugin replaces — on the user's
  own shell it is a foreign second desktop.
- iCloud-only (`i need icloud only`) deletes the whole OAuth question: Apple =
  CalDAV + app-specific password, no client ID. `hcal account add icloud` exists
  as a dedicated subcommand (`runAddCalDAV(cmd, true)`, preset `ICloudCalDAVURL`).

## Facts to reuse (verified, not assumed)

- `hcal daemon` = "Run the dcal daemon (IPC + HTTP, no UI)" → the sync engine runs
  **without Qt**: no `dux-qt-base`, no `libdux-qt-base.so.0`, no C++ build, no
  Qt-ABI rebuild duty, no third-party COPR. `dcal run` is the one that needs the
  Qt runtime (it re-execs as `dcal qs` and `dlopen`s the lib via `dux-go/qtbase`).
- Headless build = `CGO_ENABLED=0 go build -trimpath -o hcal ./cmd/hcal` with **no
  build tags and no submodules** (`-tags withshell` + `sync-shell` are the UI
  build, which needs `dux-qml-common` for `DCommon`). Pure Go, ~39 MB with `-s -w`.
- Version comes from ldflags: `-X main.Version=… -X main.Commit=… -X main.BuildTime=…`.
  A git-less source copy prints `commit unknown`.
- **IPC is the plugin's API and it speaks JSON**: `hcal ipc <method> k=v` prints
  indented JSON over `$XDG_RUNTIME_DIR/dankcal-<pid>.sock` (`DANKCAL_SOCKET`
  overrides; `ipc.FindRunningSocket()` discovers it). `hcal ipc list
  [--json]` is a LOCAL subcommand — it needs no daemon, so it is useless as a
  liveness probe (that false-positive cost a debugging round).
- Useful methods: `events.list from= to= query= limit= offset=`, `events.get`,
  `calendars.list`, `accounts.list`, `accounts.caldav.add`,
  `accounts.local.add`, `accounts.refresh`, `reminders.upcoming`,
  `events.parseIcs` + `events.importIcs` (conflict preview in the widget),
  `tasks.*` (VTODO = iCloud Reminders), `files.*`, and
  **`subscribe`/`unsubscribe topics=accounts,calendars,events,sync`** → push
  updates instead of polling a timer.
- The daemon also opens an HTTP API (HUMA/chi) on a random `127.0.0.1` port —
  decide deliberately whether the shipped unit should keep it.
- Keyring is **file-backed** (`~/.local/share/dankcal/keyring`), so headless works
  with no secret-service daemon.

## Rebrand conventions applied to this fork

- `dcal` → **`hcal`** (binary, CLI, completions, unit `hcal.service`); the shipped
  unit runs `ExecStart=/usr/bin/hcal daemon`, not `run --session --hidden`.
- Product = "Huru Calendar"; package = `huru-calendar`; icon/desktop/metainfo =
  flat `huru-calendar` (same flat convention as airgraph, no reverse-DNS id).
- **KEPT on purpose**: the `dankcal` config/data/state/socket namespace and
  `DANKCAL_*` env vars (the user's real accounts, `dankcal.db` and keyring live
  there), the Go module path `github.com/duxlabs-dev/dux-calendar/core`, the
  `dux-go` import, both submodule URLs, `quickshell/` and `distro/`.
- **The upstream OAuth credentials had to be blanked** (`core/internal/oauth/
  googledefaults.go` encoded vars, `microsoftdefaults.go` client ID): their README
  says forks/rebranded builds may not use them, and the code paths already treat
  empty as "none", so it is a 3-line change. `googledefaults_test.go` was inverted
  to assert the default build ships NO credentials.
- Rebranding must be a **word-boundary** pass. A naive `dcal` → `hcal` substring
  rewrite corrupts generated Ent code (`removedcalendars` → `removehcalendars`)
  and must never touch `dankcal`, `DANKCAL_*`, or module import paths; assert the
  module path survives after every rewrite.
- An `os.walk` skip list must match on `rel == d or rel.startswith(d + os.sep)`:
  a bare `startswith(".git")` silently skips the whole `.github/` tree (cost one
  run to notice).
- Prune the fork's CI to `go-ci.yml` (gofmt/vet/golangci-lint/test/headless build)
  + `prek.yml`. Upstream's release/flatpak/port/i18n/notify workflows publish to
  Dux's channels or call their secrets; `notify-packaging.yml` in particular would
  fire on the user's fork.

## Verify a change (proven recipe)

```bash
B=~/.hermes/cache/scratch/hcal-build && mkdir -p "$B"
podman run --rm -v ~/huru-calendar:/src:z,ro -v "$B":/work:z -w /work \
  registry.fedoraproject.org/fedora:45 bash -c '
    dnf -y install golang git >/dev/null 2>&1
    cp -a /src /work/src && cd /work/src/core
    gofmt -s -l . ; GOTOOLCHAIN=local go vet ./... ; GOTOOLCHAIN=local go test ./...
    GOTOOLCHAIN=local CGO_ENABLED=0 go build -trimpath -o /work/hcal ./cmd/hcal'
```

Two traps: `podman run --userns=keep-id` maps the container to the host uid, so
`dnf` inside says "requires superuser privileges" — don't use it for a build that
installs packages; and `--workdir` is only honoured on or after the image tag.
Then run the daemon against a **scratch XDG home** (`XDG_CONFIG_HOME`/
`XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME`/`XDG_RUNTIME_DIR` all under
scratch) and hash the real `~/.config/dankcal` + `~/.local/share/dankcal` before
and after to prove they were untouched.

**Known pre-existing test failure**: `core/internal/paths` `TestSocketDir` fails
identically on pristine upstream master in a root container (writable `/run` makes
the runtime-dir fallback resolve there instead of `os.TempDir()`). Not caused by
this fork — do not "fix" it as part of a rebrand.

## Packaging: done (2026-11-14)

- Repo `wegweg7979/huru-calendar`: rebrand committed (`9b8dd77`), spec at
  `rpm/huru-calendar.spec` (+ `.spec.sources`), tag **v2.1.2** matching upstream's
  version, pushed.
- COPR project **`wegweg7979/huru-calendar` id 271791**, package id 3282940
  (SCM: clone github, committish `master`, spec `rpm/huru-calendar.spec`,
  `source_build_method: rpkg`), chroot fedora-45-x86_64, `enable_net: true`
  (the Go build fetches modules — without it the build dies on module download).
  Build 11323034 `succeeded`; the RPM is published and verified by pulling the
  href out of `repodata` and running the binary inside it.
- GitHub webhook on the fork (events `create` + `push`, delivery 200) so a push
  or a new tag rebuilds the RPM by itself.
- The spec ships the binary, icon, user unit and completions — **not** the
  desktop entry or AppStream metadata (a GUI this fork does not build). No
  submodules, no `-tags withshell`, no Qt/build deps beyond `golang`.

## Image wiring: done (2026-11-14)

- `build_files/build.sh`: its own `::group::/::endgroup::` block right after
  airgraph — `dnf5 -y copr enable wegweg7979/huru-calendar`, install, disable,
  unguarded on purpose.
- Payload: `.config/omarchy/plugins/huru.calendar/{manifest.json,Calendar.qml}`
  plus a `huru.calendar` row at the FRONT of `shell.json`'s `centerEnd`
  (`defaultSection: centerEnd`, beside the clock), and the
  `omarchy-hurunagus-configs` inventory comment kept in step.
- Replaying the payload on a box that already has the config reports
  **`back up 1`** for `shell.json` — expected: adding a bar row makes the
  payload disagree with every live arrangement once. Say so when shipping it,
  and change an existing box with `omarchy hurunagus configs` (which backs the
  file up first) rather than by hand.

## Verifying a bar widget WITHOUT touching the live session (proven recipe)

A nested headless compositor plus a Quickshell instance pointed at a scratch
config exercises the real widget against the real daemon:

1. Scratch config dir: `shell.qml` wrapper + symlinks `Commons` and `Ui` →
   `/usr/share/omarchy/shell/*` (that is how `qs.Commons` resolves) + a copy of
   the plugin dir. The wrapper instantiates the plugin with a **stub bar** — a
   `QtObject` carrying `barForeground`, `urgent`, `fontFamily`, `vertical`,
   `barSize`, `barSizeFor()`, `position`, `foregroundAnimationEnabled`,
   `showTooltip()`, `switchPanelFrom()`; miss one and the Ui components log
   `Unable to assign [undefined]`, which looks like your bug and is not.
2. `weston --backend=headless-backend.so --socket=wayland-<name>` and run
   `WAYLAND_DISPLAY=<name> PATH=<dir-with-hcal> quickshell -p <dir> -n`.
   Nothing appears on the user's screen.
3. **QML `console.log`/`print` output is NOT surfaced by this Quickshell build**
   (nothing on stdout, nothing in `log.qslog`, and no JS errors either). Write
   the report from QML instead: a `Process` running
   `sh -c "echo '<escaped>' >> <file>"`, called from a `Timer`. Emit **one**
   line per tick — a second `reporter.running = true` while the first is still
   running is silently dropped.
4. Two runs are worth doing: with the daemon (real events, grouping, tooltip,
   selected-event formatting) and with `NO_DAEMON=1` (the daemon-down state must
   show the hint and log no QML errors).

Load errors DO surface (`ERROR: Failed to load configuration  caused by
@shell.qml[n]: X is not a type`), so this catches syntax, missing imports and
broken ids; it just cannot show pixels or hover.

## Remaining (optional)

- A month grid in the popup (the stock clock panel's grid is the style
  reference) and event dots in that stock panel — the latter is an
  omedora/upstream change with a conflict surface, so it is deliberately not
  done.
- The daemon's 127.0.0.1 HTTP API is still enabled in the shipped unit; decide
  whether that should be off.
- `assets/danklogo.svg`, `assets/screenshots/*` and `distro/{flatpak,nix}` still
  carry upstream branding but are not shipped.
