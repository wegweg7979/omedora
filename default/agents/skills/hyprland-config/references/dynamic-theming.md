# Wallpaper-derived (dynamic) theming

Read this when the palette should follow the wallpaper (pywal / wallust / matugen style), when
someone asks "is there dynamic theming here?", or when a task touches theme colors on an
Omarchy/omedora desktop.

## The shape of a solution

Two pieces, both under `$HOME`, nothing under `/usr/share/omarchy` touched:

1. **A producer** that turns the current wallpaper into `colors.toml`.
2. **A trigger** that reruns the producer on every wallpaper change and re-renders the theme.

## colors.toml is the whole palette input

The generator's `output_path` is the entire integration surface. Keys:

- `mode` (`dark`/`light`), `accent`, `selection`, `muted`
- background ramp: `background`, `dark_background`, `darker_background`, `lighter_background`
- foreground ramp: `foreground`, `dark_foreground`, `light_foreground`, `bright_foreground`
- eight ANSI colors `red yellow orange green cyan blue magenta brown` plus their `bright_*` variants

A `colors.toml` in `~/.config/omarchy/themes/<name>/` is enough to recolor the whole desktop —
Hyprland borders, bar, notifications, OSD, lock screen, terminals, btop, editors.

- Read one with the engine's own parser, not a hand-rolled grep:
  `omarchy-theme-color --file <colors.toml> --all` (also resolves legacy `colorN` names and
  derived shades).
- **`omarchy theme set <name>` stages a fresh theme**: the stock theme is copied into
  `~/.local/state/omarchy/current/next-theme`, `~/.config/omarchy/themes/<name>/` is overlaid on
  it, `omarchy-theme-set-templates` renders `$OMARCHY_PATH/default/themed/*.tpl` plus the user's
  `~/.config/omarchy/themed/*.tpl`, and the result is swapped into `current/theme`. Templating runs
  **only** when the staged theme has a `colors.toml`, and a generated file is **skipped when the
  theme already ships a file of that name**.
- **`omarchy theme refresh` re-renders the active theme in place** from its templates. That is the
  cheap "recolor everything" command: rewrite `colors.toml`, refresh, no theme switch and no session
  restart. Pass `theme.name`/`theme.generation` consumers get the new palette the same way a switch
  gives it to them.

## No hook fires on a background change (the pitfall that costs the most time)

Hook names are fixed labels Omarchy's own code calls: `theme-set`, `post-boot`, `font-set`,
`battery-low`, `post-update`, `pre-refresh-pacman`. `omarchy hook <name>` runs
`~/.config/omarchy/hooks/<name>` and every file in `<name>.d/`.

`omarchy theme bg set|next` only repoints the symlink
`~/.local/state/omarchy/current/background` and tells the running shell over IPC
(`omarchy-shell -q background set …`). There is no hook in that path and no script to wrap, so a
`theme-set` hook alone cannot recolor on a wallpaper change — do not plan on one.

Use a systemd **user** path unit on the state directory instead:

```ini
[Path]
PathModified=%h/.local/state/omarchy/current
Unit=<theme>-matugen.service   # oneshot -> the sync script
```

It catches every route to a new wallpaper (keybind, background switcher,
`omarchy theme bg set/next`) and needs no edit to a packaged file — which on `fedora-ostree` is the
only option anyway. Harden the sync script:

- fingerprint guard (wallpaper path + size + nanosecond mtime, remembered under
  `~/.local/state/omarchy/`) so an unrelated path-unit fire costs nothing;
- exit quietly unless the dynamic theme is the *active* theme;
- **pin `PATH` inside the script** — systemd user units inherit a minimal environment.

## Producing the palette with matugen

- Map Material You roles onto the Omarchy keys: `accent = primary`, `background = surface`,
  `foreground = on_surface`, `selection = surface_container_high`, `muted = outline_variant`,
  `red = error`, `blue = primary`, `magenta = secondary`, `green = tertiary`,
  `cyan = tertiary_fixed`, deriving the ramps through matugen's `set_lightness` filter.
- Offer the scheme choice rather than silently picking: `scheme-tonal-spot` keeps a curated feel,
  `scheme-vibrant` / `scheme-content` are more saturated; `mode` picks the dark or light ramp.
- Getting matugen on the host: upstream ships a **static x86_64 tarball** for `~/.local/bin` (no
  privileges, version pinned by us — the pragmatic pick on `fedora-ostree`). Fedora's own repos also
  carry `matugen` (confirm with `dnf -q repoquery --available matugen`); on a bootc image that route
  is an **image bake, and the build + rebase are the user's step** — offer it, never run it.
- Theme backgrounds live in `~/.config/omarchy/themes/<name>/backgrounds/`, extras in
  `~/.config/omarchy/backgrounds/<theme-slug>/`. Link or hardlink individual FILES: cycling walks
  the directory and gets stuck on the first image behind a directory symlink.
- Keep the dynamic theme its own directory and keep it selected — a curated theme is only recolored
  while it is the active theme, so ask before moving the user off one.

## Prior art — check before writing a new pipeline

| Project | Approach | Take |
|---|---|---|
| AccursedGalaxy/omarchy-auto-theme | path unit on the omarchy state dir → matugen → `colors.toml` in a native theme → refresh; touches nothing packaged | closest to the engine; its colors template is the one to start from |
| m7sh/matugen-theme | full theme + installer: static matugen into `~/.local/bin`, templates, `theme-set.d` hook, watch service, `autostart.lua` entry, live-video wallpapers | richest feature set; most Arch-shaped installer |
| Ryoku (Ryoku-dev/ryoku) | Omarchy-derived distro with matugen in its own shell; `docs/theming.md` analyses this same staging engine | readable engine analysis; the approach at scale |
| jaidev7823/omarchy-matugen | shims the `swaybg` binary so wallpaper changes route through swww + matugen | predates the 4.x background flow (`omarchy theme bg …`); stale |
| amolvyas-6/Matugen-Theme-Omarchy | instructs appending a call to `~/.local/share/omarchy/bin/omarchy-theme-bg-next` | **do not**: editing a packaged script is lost on the next image build and impossible on bootc |
| bjarneo/tema, prettyletto/omagen | pick a wallpaper, choose a palette direction, save a themed snapshot | complementary one-off generators, not background pipelines |

Third-party Omarchy tooling is written for Arch: `omarchy pkg aur add …`, `pacman -S` and
`~/.local/share/omarchy/bin` paths appear throughout. On omedora use `omarchy pkg add` / the Fedora
package map, `$OMARCHY_PATH` (or `/usr/share/omarchy`), and `~/.config` + `~/.local/bin`; audit an
installer's package lines before running it.

A theme cloned by `omarchy theme install <url>` cannot ship `*.lua`, terminal configs or
`vscode.json` (they are filtered — see `theming.md` in the `omarchy` skill) and has no way to
install `~/.local/bin` scripts, so a pipeline needs an install script, not just a theme repo.
