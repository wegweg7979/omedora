# Porting a ZIG app to hurunagus (measured on hyprglaze, F45, 2026-11)

Verified by a real container build, not by reading docs. Reuse the recipe for any
Zig desktop app; the numbers below are what a Fedora 45 podman build actually
returned.

## Packing a Zig app as an RPM (measured on hyprglaze, F45)

- **A green COPR build is NOT a runnable artifact: Zig defaults to `-Dcpu=native`.**
  The build therefore compiles for the BUILDER's microarchitecture. Measured: the
  first published hyprglaze build carried AVX-512 (385 `zmm` references, 151
  AVX-512-only mnemonics) because the COPR builder has it, and on target machines
  — a 12th-gen i9 with AVX-512 fused off — the RPM's binary died with `Illegal
  instruction (core dumped)` (exit 132) while the same source built locally ran
  fine. Pin it in the spec: `%global zigcpu x86_64_v2` + `zig build -Dcpu=%{zigcpu}`.
  **Zig spells the levels with UNDERSCORES** — `-Dcpu=x86_64_v2` compiles,
  `-Dcpu=x86-64-v2` (the GCC `-march` spelling) is rejected as an unknown CPU model
  and fails the build before it compiles anything. Accept the artifact only after:
  `objdump -d <bin> | grep -cE 'zmm[0-9]'` is 0, `--list-themes`/`--list-effects`
  run from the RPM-extracted tree on a target machine, and `rpm -qip` shows the
  expected Release. Triggering that check is why the first two attempts were
  caught — running the packaged binary is a different claim from building it.
- **Build logs are not in `api_3`** (`/api_3/build-log/<id>?chroot=…` → 404) and the
  results dir carries no `build.log` for a failed build; read the log from the web
  UI (`/coprs/build/<id>/`) instead, or reproduce the failure locally.

- **The trap a bare container hides: a Zig binary has no GNU build-id.**
  `zig build --release=safe` emits DWARF but `--build-id` defaults to `none`, and
  Fedora's `find-debuginfo` is invoked with `--strict-build-id` — so the COPR build
  dies with `*** ERROR: No build ID note found in .../usr/bin/<app>` / `Bad exit
  status from ... (%install)`. A first container check PASSES and lies if
  `redhat-rpm-config` is not installed (it is what ships the brp scripts): always
  install `rpm-build rpmdevtools redhat-rpm-config` to reproduce COPR, and never
  conclude "the spec is fine" from a buildroot without them. The spec-level knobs do
  NOT fix it — `%define _missing_build_ids_terminate_build 0` (the macro is defined in
  `/usr/lib/rpm/redhat/macros` but the strict flag is on the command line) and
  `debug_package %{nil}` both leave the error. The zero-patch fix: pass
  **`zig build --build-id=sha1`** in `%build` and `%install` — Zig 0.17's build
  system accepts it (`-Dbuild_id=…` does not: "invalid option", exit 1), the binary
  then carries `.note.gnu.build-id`, and debuginfo + debugsource packages are real.
- `Requires: hyprland-bin >= 0.55` is how a Fedora spec says "needs the Lua-config
  Hyprland"; upstream's Arch `depends=('hyprland>=0.55')` is not a Fedora package name.
- `%{_userunitdir}` (from `BuildRequires: systemd-rpm-macros`) is the correct path for
  the units a Zig `--prefix` install drops in `lib/systemd/user/`; `%{_libdir}` would
  be `/usr/lib64` and wrong. `%doc README.md docs` carries the upstream docs.
- Verify with `dnf5 builddep -y --spec <spec>` (installs ONLY declared BRs — the check
  that the BR list is complete) then `rpmbuild -ba`. Measured on hyprglaze: 151 s,
  0 warnings, 17/17 build steps, 128/128 unit tests, main + debuginfo + debugsource +
  SRPM, 1.9 MB stripped binary with a build-id, 24 effects / 367 themes from the
  packaged tree. SOURCES must hold BOTH sources for a local `rpmbuild` — it does not
  fetch them.
- **Macros in spec COMMENTS are expanded and warn** (`warning: Macro expanded in
  comment on line N`) — write "the debug_package nil line", not `%{nil}`, and
  `rpmbuild`'s log stays clean.

## Recipe (read-only w.r.t. the host — no `rpm-ostree install`, ever)

```bash
mkdir -p <scratch>/hg-build
podman run --rm -v <scratch>/hg-build:/work:z -w /work docker.io/library/fedora:45 bash -c '
  dnf5 install -y --setopt=install_weak_deps=False wayland-devel libglvnd-devel \
    mesa-libEGL-devel pulseaudio-libs-devel stb-devel git gcc glibc-devel binutils tar xz
  curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz
  tar -C /opt -xf /tmp/zig.tar.xz; export PATH=/opt/zig-x86_64-linux-0.17.1:$PATH
  git clone --depth=1 https://github.com/<owner>/<app> /work/app && cd /work/app
  zig build --release=safe && zig build test
  zig build --release=safe --prefix /work/stage   # the whole install tree
'
```

`zig build --prefix <dir>` is the install; inspect `stage/` to write the `%files`
list. The binary produced in the F45 container runs on the F45 host unchanged —
smoke-test it there (`--help`, `--list-*`) before touching any packaging.

## The toolchain gap — the one thing that actually blocks a Zig app here

- **Fedora 45 packages `zig 0.16.0`; hyprglaze needs 0.17.0+** (`build.zig.zon`
  `minimum_zig_version = "0.17.0"`; its `build.zig` uses 0.17-only API —
  `b.addTranslateC`, `run_cmd.addPassthruArgs()`). Official 0.17.1 exists at
  ziglang.org (`zig-x86_64-linux-0.17.1.tar.xz`, 57 411 036 bytes). So the
  package must ship/fetch its own compiler: extra `Source` tarball in the spec,
  or a small `zig-0.17` companion package in the same COPR. Fedora has no
  `zig0.17` compat package and no `zig` COPR worth depending on.
- Upstream had **0 GitHub releases**, so "curl the release binary in build.sh"
  (pitfall 14) does not apply — a Zig app is compile-or-nothing unless it ships
  assets. Check `api.github.com/repos/<o>/<r>/releases` before planning.
- A Zig project with `build.zig.zon` dependencies fetches them over the network
  at build time (e.g. `git+https://…/zig-toml`), so a COPR project for it needs
  `enable_net: true` — same as the icloud-suite precedent.
- Zig's caches live in `$HOME/.cache/zig`; keep it inside the builddir in a
  spec so nothing leaks between builds.

## Fedora-side dependency answers (measured with `dnf5 repoquery`)

| Arch PKGBUILD dep | Fedora 45 equivalent |
|---|---|
| `wayland` (+ `wayland-scanner`) | `wayland-devel` (ships `/usr/sbin/wayland-scanner`) |
| `libglvnd` | `libglvnd-devel` — **also supplies `libEGL.so` AND `libGLESv2.so`** |
| `mesa` | `mesa-libEGL-devel`; **`mesa-libGLES-devel` does not exist in F45** — no GLES devel package is needed |
| `libpulse` | `pulseaudio-libs-devel` (`libpulse-simple.so`) — works against PipeWire's pulse compat |
| `stb` | `stb-devel` — ships `/usr/include/stb/stb_image.h` (matches `#include <stb/stb_image.h>`) |
| `hyprland>=0.55` | **`hyprland-bin >= 0.55`** — Fedora has no package named `hyprland`; the omedora COPR's `hyprland-no-session` Provides `hyprland-bin` and `hyprland-no-session` |

`%{_libdir}` is `/usr/lib64` — wrong for systemd user units. Zig install trees
that hardcode `lib/systemd/user` need `%files` with `%{_userunitdir}` (or a
literal `/usr/lib/systemd/user/`).

## Runtime/integration facts worth checking before promising "it works"

- A wallpaper/daemon that injects Lua into the compositor (`@embedFile` +
  `hyprctl eval`) needs **Hyprland 0.55+ with a Lua config**; the host must show
  `hyprctl eval 'return 42'` → `ok`. This image family (omedora `hyprland-no-session
  0.56.2`) satisfies it — the classic-conf refusal does not apply here.
- The Omarchy background layer is owned by the Quickshell plugin
  `omarchy.background` (`WlrLayershell.layer: WlrLayer.Background`, namespace
  `omarchy-background`), but a third-party background-layer wallpaper does **not**
  need it disabled: both surfaces coexist at layer level 0 and the **later-mapped
  one is the visible one** — `hyprctl layers` lists `omarchy-background` (pid of
  the shell) first and the new `hyprglaze` surface second, and pixels confirm the
  daemon owns the screen (82-84 % of it changed). Check the layer order before
  reaching for `omarchy plugin disable omarchy.background`, which also takes
  Omarchy's own wallpaper picker out of play.
- `graphical-session.target` **is active on this image** (uwsm 0.27.1), so units
  `WantedBy=graphical-session.target` really do start; the upstream README's
  "Hyprland started directly never reaches it" caveat is about Arch setups, not
  this one. Per-connector instance names remain host-specific.
- Upstream nested-compositor harnesses (`scripts/hypr-harness.sh` here) are a
  safe render proof — they drive a second Hyprland and never the host session —
  but they need `HYPRLAND_NO_SD_VARS=1` or the nested compositor rewrites the
  host's systemd/dbus activation environment and breaks every dbus-activated app
  in the real session.

## Turning such a daemon off cleanly (enable/disable contract)

A background-layer daemon needs a symmetric on/off story, and only one part of it
is non-obvious: the Lua watcher it injects into the compositor. Everything here was
measured on 0.56.2 with a socket2 event counter.

- **Stopping the process does not remove the watcher.** `main.zig` only deinits its
own Zig state; the Lua timer stays in the compositor (16 ms tick, ~2 s heartbeat
  `hg:hb2`, plus cursor/mgeo pushes on change) and is dropped only when the Lua
  state is recreated = a config reload. Counted: daemon dead → 3 watcher events in
  6 s; after `hyprctl reload` → 0 in 8 s.
- **`on` never needs a reload**: a daemon started after a reload reinstalls its
  watcher by itself (3 events in 6 s again, surface rendering).
- **`off` = stop + reload**, and the reload is worth skipping when nothing was
  running (both a hand-run toggle and a user-facing one should avoid remapping the
  desktop for nothing). A daemon that *crashed* still leaves a failed unit, which
  `systemctl --user list-units --all` lists — so the reload still fires.
- **The wallpaper revert needs no restore step and is pixel-exact**: the Omarchy
  background surface keeps rendering underneath, so stopping the daemon brings it
  back instantly (measured on a window-free strip of the output: 0.1-0.2 % of
  pixels differ from the pre-test frame, vs 97.9 % while it ran).
- **Ship the user-facing toggle as an image-owned `omarchy-*` script**, not inside
  the app's RPM: `system_files/usr/bin/omarchy-<app>` carrying the house metadata
  header is auto-discovered by the Omarchy dispatcher as `omarchy <app> on|off`
  (verified against `omarchy commands --json`, which lists the route for the
  existing `omarchy-hurunagus-configs`). The app package stays upstream-shaped.
- For the units: `hyprglaze@<connector>.service`, one instance per monitor,
  `WantedBy=graphical-session.target` (reached via uwsm here, so they really start
  at login). `on` should enable the connectors present **now** and skip ones the
  compositor reports `disabled`, because a pinned-output daemon exits non-zero
  when its output goes away.

## Settings surface: one optional TOML, hot-reloaded

Read this before building anything that toggles or configures such an app (a bar
widget, a panel, a menu row). Measured on hyprglaze at its pinned commit.

- **Path**: `~/.config/hypr/hyprglaze.toml` (`XDG_CONFIG_HOME` first, `--config`
  overrides). A missing file is NOT an error — startup uses the same defaults an
  empty file gets and creates nothing, which is why the app runs fine on a box that
  never configured it.
- **Shape**: top-level `effect`, `theme`, optional `shader`/`output`/`output_wait`;
  then one section per concern (`[transition]`, `[cursor]`, `[geometry]`,
  `[particles]`, `[buddy]`, …) plus one per effect, with the audio effects sharing
  `[visualizer]` (`music`, `sink`, and their own keys).
- **CLI beats the file only at STARTUP.** A hot reload re-reads the file WITHOUT
  re-applying CLI overrides, so once the file changes, the FILE wins — a launcher
  that passes `--effect`/`--theme` gets silently overridden by the next config edit.
- **Hot reload**: inotify on the *directory* (`CLOSE_WRITE|MOVED_TO|CREATE`), so an
  editor save and an atomic tmp+rename both land. Every reload re-initialises the
  effect (so per-effect section edits apply live — logged `reloaded` vs `switched`),
  reloads the theme if its name changed, recompiles the shader if its path changed,
  applies the smoothing keys, and only *warns* for a changed `output` (the layer
  surface binds at creation). A reload whose effect fails to build keeps the current
  effect and logs a warning — bad settings never kill the daemon.
- **Only `theme` has an upstream writer** (`--set-theme`: rewrites the top-level line
  or prepends one, creates the dir, writes tmp+rename). `effect` and
  `[visualizer] music` need our own editor — preserve the rest of the file byte for
  byte, edit one key in place, write atomically; that single-key technique is the model.
- **Parsing is lenient**: unknown keys are ignored (the strict mode is off), a wrong
  type falls back to that key's default, an unquoted `output` is warned about and
  ignored, and numeric params are clamped at use (coral `scale` 24-400). A typo costs
  a default, not a broken wallpaper — do not build validation UI for it.
- **Edge case**: with NO config file at startup there is no watcher, so the first
  `--set-theme` (which creates the file) does not reach the *running* instance; the
  next start picks it up.
- **Adjacent files**: the theme list is embedded in the binary, with a user override at
  `~/.config/hyprglaze/themes.json`; `ai-buddy` credentials live in
  `~/.config/hypr/hyprglaze-aws.env`. Nothing else is written at runtime.
- **Its `theme` is its own namespace** (Gogh scheme names, 367 of them) and unrelated
  to Omarchy's `colors.toml` — "make the wallpaper follow `omarchy theme set`" is a
  mapping hook we would write, not something upstream offers.
