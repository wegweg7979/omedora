# GTK dark theming on Fedora (GTK3 renders light while everything else is dark)

Load when: the user reports light dialog boxes / light GTK apps on an omedora
(hurunagus) box, or when touching `omarchy-theme-set-gnome`, GNOME
`gtk-theme`/`color-scheme` values, or a `theme-set` hook.

## The bug, in one line

omedora's `omarchy-theme-set-gnome` sets dconf `gtk-theme=Adwaita-dark`, and
**GTK 3.24 cannot resolve `Adwaita-dark` as a theme name** — it appends the dark
variant itself, looks for `Adwaita-dark-dark`, misses, and silently falls back
to *light* Adwaita. GTK4/libadwaita apps stay dark because they follow
`color-scheme` instead, which is why the symptom is "only certain windows".

- `Adwaita-dark` is a GTK4/libadwaita-ism. GTK3 selects its dark theme from the
  `gtk-application-prefer-dark-theme` flag + theme name `Adwaita`.
- **dconf's `gtk-theme` overrides `gtk-theme-name` in
  `~/.config/gtk-3.0/settings.ini`** (GTK3 binds the dconf key), so an ini fix
  alone does nothing while dconf says `Adwaita-dark`. Both halves are needed.
- Reading `gtk-theme-name` off `Gtk.Settings` is NOT evidence: it reports
  `Adwaita-dark` happily while the loaded CSS is light.
- **dconf's `color-scheme` does NOT reach GTK3's flag** (verified: `gtk-theme=Adwaita`
  + `prefer-dark-theme=0` renders light even with `color-scheme=prefer-dark`), and
  no dconf schema carries it at all — `org.gtk.Settings` does not exist and gtk3/gtk4
  ship only ColorChooser/Debug/EmojiChooser/FileChooser schemas. On a bare Hyprland
  session (no XSETTINGS daemon) the settings file is the ONLY route for the flag.
  `gtk-theme=Adwaita:dark` in dconf does not work either — GTK3 does not parse the
  variant out of the dconf string (verified light).
- It leaks beyond native GTK3: `xdg-desktop-portal-gtk` re-exports host
  `gtk-theme` + `color-scheme` to Flatpaks, and Qt apps under
  `QT_QPA_PLATFORMTHEME=gtk3` follow the same flag (Qt's `libqgtk3.so`
  subscribes to `notify::gtk-application-prefer-dark-theme`).

Working combination: dconf `gtk-theme=Adwaita`, `color-scheme=prefer-dark`,
and `gtk-application-prefer-dark-theme=1` in `~/.config/gtk-{3,4}.0/settings.ini`.

## Prove it by rendering pixels, not by reading settings

`Gtk.OffscreenWindow` renders through the real theme pipeline without touching
the user's screen. Dark reads ~`#343434`, light ~`#f3f2f1`:

```bash
SIG=$(ls /run/user/1000/hypr/ | head -1)
WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 \
HYPRLAND_INSTANCE_SIGNATURE="$SIG" /usr/bin/python3 - <<'EOF'
import gi, collections
from gi.repository import Gtk, GLib
w = Gtk.OffscreenWindow(); w.add(Gtk.Button(label='x')); w.show_all()
while GLib.MainContext.default().iteration(False): pass
pb = w.get_pixbuf(); buf = pb.get_pixels(); rs, nch = pb.get_rowstride(), pb.get_n_channels()
c = collections.Counter()
for y in range(2, pb.get_height()-2, 3):
    for x in range(2, pb.get_width()-2, 3):
        o = y*rs + x*nch
        c[(buf[o]<<16)|(buf[o+1]<<8)|buf[o+2]] += 1
print([f'#{v:06x}' for v,_ in c.most_common(3)])
EOF
```

Cross-check with a forced reference: `GTK_THEME=Adwaita:dark <same probe>` renders
dark even when the config is broken, which separates "the theme is wrong" from
"the probe is wrong". Use `XDG_CONFIG_HOME=<scratch>` to bisect a config without
touching the user's files (it also removes the dconf db, so GSettings returns
schema defaults — useful for isolating which of dconf/ini wins).

## Persistence

`/usr` is read-only, so do NOT patch `omarchy-theme-set-gnome` on the box. Two
options, both `$HOME`-safe:

1. **Hook (preferred, shipped to the user's box):**
   `~/.config/omarchy/hooks/theme-set.d/20-gtk-dark` — theme hooks run *after*
   `omarchy-theme-set-gnome` inside `omarchy-theme-set`, so it re-asserts the
   working values on every theme switch (`omarchy hook theme-set <slug>` runs
   every non-`.sample` file in the dir; no install step, just place the file).
   Read the mode from the current theme's `colors.toml`
   (`omarchy-theme-color --file … mode`) instead of hardcoding dark, or a later
   light theme is broken by the hook.
2. **Repo fix (the real omedora fix) — SHIPPED** (commit `bd8c8fe2c` on
   `omedora-4`, 2026-11-16; COPR builds 11336216/11336215 succeeded, both tagged
   `gitbd8c8fe`). Patch
   `bin/omarchy-theme-set-gnome` in `/var/home/user/omedora-inspect`: the upstream
   dark line is relocated verbatim into an `if [[ $(omarchy-distro) == arch ]]` arm
   (Arch keeps byte-identical behaviour) and Fedora sets `gtk-theme=Adwaita`, plus a
   `set_gtk_prefer_dark()` helper that rewrites ONLY the
   `gtk-application-prefer-dark-theme` key in `~/.config/gtk-{3,4}.0/settings.ini`
   (mode-driven: 0 on a light theme, 1 on dark) so a user's font/theme keys survive.
   Same trap as `install/user/first-run/gnome-theme.sh`, which is already neutralized
   on Fedora with a comment saying the theme system drives these values — it does, but
   with a GTK3-unresolvable name. GNOME-alongside-omedora users are unaffected by
   `Adwaita`: libadwaita keys off `color-scheme`.

   Three things that make this patch land in the repo's own conventions:
   - **Relocate, don't delete**: keeping the upstream line verbatim inside the Arch
     arm means the diff is additive except that one deleted line, which needs the
     standard `ALLOW["bin/omarchy-theme-set-gnome"]='  gsettings set
     org.gnome.desktop.interface gtk-theme "Adwaita-dark"'` entry in
     `test/byte-identity-test.sh` (exact text, leading 2 spaces, single quotes escaped
     `'"'"'`). A NEW deletion without an ALLOW entry trips the gate.
   - **Verify the gate locally even when the pin tag is absent**: the audit takes
     `OMEDORA_BASE_TAG=HEAD` as an override, so
     `OMEDORA_BASE_TAG=HEAD bash test/byte-identity-test.sh` really evaluates your
     diff against HEAD (the pin tag is usually missing in a local clone, and the
     audit then skips silently — a pass that proves nothing).
   - **Behaviour-test the script in a scratch HOME with stubbed
     `gsettings`/`omarchy-distro`/`omarchy-theme-color` on PATH** (`gs` writes args to
     `$GSETTINGS_LOG`, `omarchy-distro` echoes `$STUB_DISTRO`, `omarchy-theme-color`
     echoes `$STUB_MODE`) and a bogus `DBUS_SESSION_BUS_ADDRESS` so a stub that
     didn't take effect fails loudly instead of writing the live dconf. Cover: fedora
     dark, fedora light, an existing settings.ini with user keys (must be preserved,
     flag flipped, no duplicate key), a file with no `[Settings]` group, and
     `arch` (upstream value, no settings.ini written). Harness:
     `~/.hermes/cache/scratch/gtkprobe/theme-set-gnome-sim.sh` (re-create from this
     note if pruned). Never run the real `omarchy-theme-set` on the live desktop
     (pitfall 9).
   - **A payload change rebuilds the self-source packages on push alone**: `bin/**`
     is in `copr-build.yml`'s push paths, so pushing to `omedora-4` submits
     `omedora-settings` + `omedora` (no `workflow_dispatch` needed), and `test.yml`
     runs the L1 job. Prove the fix reached the artifact — not just that the build
     went green — with `scripts/copr-verify-payload.sh` against
     `/usr/bin/omarchy-theme-set-gnome` (the `/usr/share/omarchy/bin/*` path is a
     symlink in the RPM; see `copr-app-publishing.md`). The host keeps running the
     PREVIOUS commit's payload until a new image is built and rebased, so the user's
     `theme-set.d/20-gtk-dark` hook stays the stopgap meanwhile.

## The adw-gtk3 follow-up (GTK3 apps should look like the libadwaita ones)

**Shipped 2026-11-16** on the user's go: omedora `842205680` (payload + map) →
COPR builds 11336422/11336423 succeeded f44+f45, NEVRA
`…-1.202611161751git8422056` → image repo `cb5151b` → image build run
43923873783 green in 21m, registry digest `sha256:6e101552…`, label
`latest.20261116-cb5151b`. Verified INSIDE the pulled image (not from the badge):
`rpm -q omedora` = `…git8422056`, `adw-gtk3-theme-6.5-1.fc45` baked,
`/usr/share/themes/adw-gtk3-dark/gtk-3.0/gtk-dark.css` present (so the
`theme_installed` guard takes the adw branch), and both published RPMs' payloads
diffed identical to the committed files. It closes
the skip the map itself defers to: `[gnome-themes-extra]` said "adw-gtk3-theme is
the modern equivalent … Skip until omedora has a GTK theming story on Fedora".

- **Two files change per checkout**: `install/packages/fedora.toml` (omedora) →
  `source = "dnf"`, `names = ["adw-gtk3-theme"]`; and the image repo's
  `build_files/fedora.toml`, which is kept byte-identical to it (`cmp` them).
- **`adw-gtk3-theme` ships BOTH toolkits** — `/usr/share/themes/adw-gtk3{,-dark}/gtk-3.0/`
  and `gtk-4.0/`, the latter a real sheet (`gtk.css` importing `libadwaita.css`
  + `libadwaita-tweaks.css`, ~431 KB). This was got WRONG once by reading a
  truncated `repoquery -l | head -25` listing, which showed only gtk-3.0 assets:
  **a `head`-truncated file list says nothing about what a package ships** — grep
  the list for the directory you care about
  (`repoquery -l adw-gtk3-theme | grep -c gtk-4.0` → 20), or look inside the
  built image. The shipped script therefore leaves GTK4 on `Adwaita` with a
  justification ("adw-gtk3 has no gtk-4.0 sheet") that is false, and the map's
  `reason` string repeats it — both are user-visible once installed, so fold the
  correction into the NEXT payload change rather than spending a COPR rebuild +
  25-minute image build on prose.
- **The false claim keeps RE-ENTERING from the script's own comment, not from the
  map.** Source: `bin/omarchy-theme-set-gnome` (~line 65, "adw-gtk3 ships gtk-3.0
  files only, so GTK4 keeps Adwaita") — the `reason` string is copied out of it,
  so correcting only the map leaves the comment to leak it back on the next prose
  pass. It recurred 2026-11-16: a web-UI commit on `hurunagus-hyprland` rewrote the
  reason to "It ships gtk-3.0 files only, so GTK4 is unaffected", and the fix had
  to be re-applied through the omedora-synced copy (`616db68`, which also keeps the
  image repo's `build_files/fedora.toml` byte-identical to omedora's — `cmp` them).
  Re-measured on BOTH available versions: `adw-gtk3-theme-6.4-4.fc45` and
  `6.5-1.fc45` each ship **110 `gtk-3.0` + 20 `gtk-4.0` files**, the GTK4 sheets
  being real for both theme names
  (`adw-gtk3{,-dark}/gtk-4.0/{gtk.css,gtk-dark.css,libadwaita.css,libadwaita-tweaks.css}`).
  When touching this prose, check all three places at once: the script comment,
  omedora's `install/packages/fedora.toml`, and the image repo's
  `build_files/fedora.toml`.
- Naming adw-gtk3 for GTK4 is a separate, optional decision: it would change
  non-libadwaita GTK4 apps and, since the GTK4 sheet IS libadwaita's own
  stylesheet, roughly nothing for libadwaita ones. Today GTK4 rides
  `color-scheme` (verified dark), so there is no defect to fix. The measurement
  behind that: a presented GTK4 window renders dark (`#353535`) even with an
  unresolvable `gtk-theme-name` AND `prefer-dark-theme=0` (captured with `grim`),
  while GTK3 in the same state renders light — GTK4 ignores the setting GTK3
  obeys, so re-check if a future GTK4 starts resolving `gtk-theme-name`.
- **Guard on GTK's own search order, not a hardcoded `/usr` path**:
  `for dir in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do [[ -d $dir/themes/<name> ]] …` — it honours a
  user-installed theme in `~/.local/share/themes`, and it is the only way to test
  the branch on a box where `/usr` is read-only (point `XDG_DATA_HOME` at a scratch
  dir in the sim harness). Flatpak's `org.gtk.Gtk3theme.*` extensions do NOT
  export themes to `/var/lib/flatpak/exports/share/themes`, so the guard cannot be
  fooled by them — sandboxed GTK3 apps get the theme through the portal instead,
  and those two extensions are already present on workstation.
- **Verify the bake without a build**: run the image's resolver directly —
  `python3 build_files/fedora-resolve.py --map build_files/fedora.toml --fedora-version 45 --copr-out /tmp/c.txt build_files/omarchy-base.packages build_files/fedora-baseline.packages | grep adw`
  → `adw-gtk3-theme` (143-line list). `test/pkg-map-test.sh` and
  `test/pkg-helper-test.sh` are pure parsers, safe to run on the host, and
  `pkg-map-test.sh` asserts exactly the invariant the edit has to keep
  ("every name it can reach must resolve as an explicit dnf mapping or skip",
  dnf entries need `names`).
- **Shipping order**: omedora push (payload + map) → COPR rebuild `omedora` +
  `omedora-settings` → image repo commit (its own `fedora.toml` copy) → image
  build/rebase. The user's own `theme-set.d` hook is now **self-retiring**: it
  exits when the INSTALLED script contains `set_gtk_setting`, so once the image
  carries the fix the hook goes quiet on its own.
- Light mode is deliberately left on upstream's `Adwaita` (the two relocated
  upstream lines stay one, not two): parity for light themes needs a second
  allowlisted relocation, so it waits for the user to ask for it.

## The colon-split bug (shipped in `8422056`, found on the rebased host)

The `theme_installed` guard asked `for dir in "$XDG_DATA_HOME…" ${XDG_DATA_DIRS:-…}`
and **word splitting does not split on `:`** — the unquoted list stayed ONE word,
so the loop tested `/usr/local/share:/usr/share/themes/adw-gtk3-dark`, which is not
a directory, and every entry after the first was invisible. On a real Fedora box
the theme lives in `/usr/share` (an XDG_DATA_DIRS entry) with nothing in
`XDG_DATA_HOME`, so the guard answered "not installed" and the script fell back to
plain Adwaita — dark, but not the libadwaita look. The sim harness passed because
it only ever put the theme in `XDG_DATA_HOME`: **the one half that worked.**

Fix: `IFS=: read -ra dirs <<<"$XDG_DATA_HOME:$XDG_DATA_DIRS"`, then loop
`"${dirs[@]}"`. Fixed in `0e4f45888` (payload verified identical in the published
RPM; COPR 11336737/11336736 green).

How it was caught, and how to check it again next time:

- Run the **installed** script on the rebased host and read the resulting dconf
  value — it stayed `Adwaita` while the script exited 0. A silent fallback is the
  symptom; the exit code says nothing.
- The harness now has a case that puts the theme ONLY behind a colon-separated
  `XDG_DATA_DIRS` (what a Fedora host actually looks like). Run it against both
  builds: shipped → 3 assertions FAIL, fixed → ALL PASS. A sim that sets only
  `XDG_DATA_HOME` cannot see this class of bug.
- The same bug existed in the local `theme-set.d` hook (same loop). Lesson: when a
  hook mirrors repo logic, fix both, and make the hook's retirement marker match a
  *working* implementation (`read -ra dirs`), not a function name — it retired on
  the broken payload and stopped re-asserting.
- Measured end state on the host: GTK3's resolved `theme_bg_color`
  `rgb(53,53,53)` (Adwaita dark) → `rgb(34,34,38)`, exactly the `#222226`
  `adw-gtk3-dark` declares; a GTK3 window's own background (sample the outer few
  pixels — a Button fills the middle and its face is `#38383b`) renders `#222226`
  vs `#353535` with `GTK_THEME=Adwaita:dark` forced.
- **dconf's `gtk-theme` overrides `gtk-4.0/settings.ini` too**, not just GTK3's
  (GTK4 window captured at `#222226` while the ini said `Adwaita`), so the same
  name is written for both toolkits now. A GTK4 presented window is also confounded
  by Hyprland opacity/blur over the wallpaper — it read `#27282d`/`#1a1b26` before
  the window was opaque; `hyprctl keyword windowrulev2` refuses on this build
  ("non-legacy parsers… use eval"), so sample an offscreen/opaque surface instead.

## Traps

- **A `theme-set` re-run decides the value again.** Any manual `gsettings set`
  survives until the next `omarchy theme set`, so verify the fix by clobbering
  the key, then running `omarchy hook theme-set <slug>` and re-reading it — that
  is the same path `omarchy-theme-set` takes.
- GTK reads settings at **startup**: already-running apps keep the old look
  until restarted (portals included — `systemctl --user restart
  xdg-desktop-portal-gtk` if a file chooser must change now).
- `~/.config/gtk-{3,4}.0/dank-colors.css` is a **DankMaterialShell/matugen
  leftover** — it only applies if a `gtk.css` imports it, and it hardcodes a
  stale palette (accent differs from the active theme). Harmless when orphaned;
  ask before deleting, and if the user wants GTK to match the theme's palette
  (stock Adwaita dark is `#343434`, Tokyo Night's bg is `#1a1b26`), generate the
  `@define-color` block from the active theme's `colors.toml` instead of reusing
  the old file.
- Qt palette dump without PyQt/PySide installed: `qmlscene` hangs in this
  session (no display handshake offscreen either). Cheapest real check is the
  strings evidence (`strings /usr/lib64/qt6/plugins/platformthemes/libqgtk3.so |
  grep prefer-dark`) plus static reasoning; don't burn calls on qmlscene.
- A **presented-window + `grim`** capture is the reliable pixel proof (the
  offscreen route above is GTK3-only, and `Gtk.StyleContext.lookup_color` lies for
  GTK4 — it returned a dark color for every combination, including flag=0). Recipe:
  launch the window with `terminal(background=true)` (a probe that presents and
  waits is fine; it must outlive the call), read geometry from `hyprctl clients -j`
  by title, `grim -g '<x>,<y> <w>x<h>'`, then sample with PIL. Two API traps cost
  real time: GTK4 has **no `Gtk.main`** — use `GLib.MainLoop()` and never
  `Gtk.Application.run()` from a plain script (it hung with no output), and a
  callback that shells out to `grim` inside the app's own timeout left the app
  hung, so capture from a SEPARATE call. Verified this way: a plain GTK4 window
  renders `#353535` (Adwaita dark) under `gtk-theme-name=Adwaita` +
  `prefer-dark-theme=1`.
