# Porting icloud-for-omarchy to Fedora (COPR + image)

Upstream: **github.com/ferdousbhai/icloud-for-omarchy** (MIT, Rust 84% + GTK4 +
Qt6/QML, very active). Seven Arch packages shipped as a signed pacman repo and
an `install.sh`: icloud-session, icloud-photos, icloud-findmy, icloud-notes,
icloud-reminders, icloud-contacts, icloud-drive. It is a *suite*, not a viewer —
it overlaps the rclone cloud mounts and beats them where it matters (see below).

Our side: **github.com/wegweg7979/icloud-for-omarchy-rpm** (packaging only) and
COPR **wegweg7979/icloud-for-omarchy**.

## Why this beats the rclone mounts it sits next to

| Capability | rclone FUSE mount | icloud-for-omarchy |
|---|---|---|
| Drive | live mount, rw | `~/iCloud Drive` **bidirectional sync**, conflicted copies, deletions to trash / Recently Deleted, rename propagation, >20-removal quorum, missing folder = sync nothing |
| Photos | read-only mount | GTK4 app: browse + **upload** + delete-with-undo; thumbnails are iCloud's own previews, nothing decoded locally |
| Sign-in | 30-day trust token to renew | Apple's own page + 2FA once, cookies in the system keyring |
| Requires | trust token | Apple ID with Advanced Data Protection **off**, "Access iCloud Data on the Web" **on** |

## The port is a PACKAGING problem, not a codebase problem

Measured read-only recon before writing anything:

- `pacman` appears in the source only as three "reinstall with pacman -S"
  *error-message strings* (notes/qml/main.qml, notes/src/cli.cpp,
  sessiond/src/daemon.rs); no `/etc/arch-release` checks, no AUR/paru.
- The 37 `omarchy` mentions are theme/QoL integration + docs. Notes reads
  `~/.local/state/omarchy/current/theme/colors.toml`, **which the hurunagus image
  already ships**.
- **Phase 0 proof** (do this before writing a spec): run upstream's own
  `cargo build --release --locked --bins -p icloud-sessiond -p icloud-drive
  -p icloud-photos` in a `registry.fedoraproject.org/fedora:45` container with
  gtk4-devel/libadwaita-devel/webkitgtk6.0-devel/gcc/pkgconf-pkg-config. It
  finished in **104s, exit 0, no source changes**, producing icloud-sessiond,
  icloud-session-signin, icloud-drive, icloud-photos, icloud-photos-app.
  **The session package's crate is `icloud-sessiond`, not `icloud-session`.**
  Edition 2024 → needs rust ≥1.85 (F45 has 1.99.1).

## Fedora adaptations the spec needed (none is a patch)

- `org.freedesktop.secrets` is a **capability no Fedora package Provides** →
  `Requires: gnome-keyring` (which owns that D-Bus name).
- Everything else maps 1:1: gtk4, libadwaita, webkitgtk6.0, gstreamer1-plugins-good,
  sqlite-libs, hicolor-icon-theme, wl-clipboard, xdg-utils, qt6-qtbase,
  qt6-qtdeclarative. libshumate is Find My only.
- **SQLite is the SYSTEM library, not the crate's bundled amalgamation** — the
  built binaries carry `libsqlite3.so.0` in their auto-generated requires, and
  the amalgamation inside the vendored crate is not compiled. It only built at
  first because `sqlite-devel` arrives transitively
  (webkitgtk6.0-devel → libsoup3-devel → pkgconfig(sqlite3)); declare it
  explicitly, because a transitive build dep is not a contract.
- **Debug info: `%global debug_package %{nil}` is a no-op here, and that is a
  measured fact.** rpmbuild's redhat-rpm-config exports `RUSTFLAGS='-Cdebuginfo=2
  -Cstrip=none'`, but cargo's release profile emits its own `-C debuginfo=0`
  afterwards and the last flag wins: the binary from rpmbuild carries no DWARF
  (6,365,056 bytes, only `.debug_gdb_scripts`) and is the same size as a plain
  `cargo build` (6,394,696). Building WITH the override dropped was tested and
  changes nothing — same four RPMs, no -debuginfo, no -debugsource, no warning.
  Keep the override for explicitness and consistency with airgraph/huru-calendar.
  (An earlier claim that dropping it would hit "Empty %files file
  …/debugfiles.list" was WRONG — modern rpmbuild tolerates it silently.)

## Delivered artifacts (v0.12.1)

One spec (`rpm/icloud-for-omarchy.spec`) with four packages: `icloud-session`
(3 binaries incl. the `icloud-session` symlink → `icloud-sessiond`, a **D-Bus
activation** file, a desktop entry), `icloud-drive` (binary +
`/usr/lib/systemd/user/icloud-drive.service`, deliberately **disabled** — a first
sync downloads the whole Drive, so `icloud-drive start` turns it on),
`icloud-photos` (CLI + window, desktop entry, icon), and an `icloud-for-omarchy`
metapackage requiring the three. `%check` runs `desktop-file-validate` on the
source-tree .desktop files; cargo's own suites are deliberately not run yet
(dev-deps + fake servers, not vetted on Fedora).

- **Verification recipe that actually proves the spec** — install ONLY the
  spec's BuildRequires, exactly as COPR does, and mount the output out:
  `dnf5 builddep -y --spec <spec>` then `rpmbuild -bb`; ~170s. A missing
  BuildRequires fails here instead of in COPR.
- COPR settings: chroot `fedora-45-x86_64` (matches airgraph; omedora-4 also has
  f44), **`enable_net: true`** — the Rust build fetches crates from crates.io,
  same precedent as huru-calendar's golang build. Offline fallback: `cargo
  vendor --locked` = 244 crates / 311 MB in 12s.
- `bin/spec-sources` needed one adaptation: its tree-check marker must be an
  **upstream** path (`Cargo.toml`, `packaging/PKGBUILD`), because unlike
  airgraph/huru-calendar the spec is NOT inside the archive it fetches.
  Pinned hash for v0.12.1: `760abd93c76662bae9bc1040685e23b51d6698c9aeb65ce654b4a2634964d298`.
- Published and verified: four RPMs in the repo metadata, `rpm -qp` shows MIT and
  a real `Header OpenPGP V4 RSA/SHA256` signature (project key
  `53fd445ad86a17aa`), payload exactly as spec'd. `rpm -qip`'s `Signature:` field
  prints BLANK without the key imported — that is not an unsigned package; use
  `rpm -qp --qf '%{rsaheader:pgpsig}'` or `rpm --checksig -v` to see it.

## Field notes after deploying it on the host (2026-11-15)

- **The user runs Photos from this suite and keeps rclone for Drive.** Their
  words: "dont want to change to the other icloud drive as i dont want to sync my
  cloud storage" — the rclone `~/iCloudDrive` mount is a live on-demand view,
  while `icloud-drive` downloads the whole Drive locally on first run. So do NOT
  retire the rclone iCloud Drive mount, and do NOT run `icloud-drive start`.
  The package is harmless left installed: verified inert (no process, unit
  `inactive`/`disabled`, no `~/iCloud Drive` directory ever created, and no
  timer exists upstream for it), which is its documented design — off until
  `icloud-drive start`. The Photos rclone mount WAS retired (unit disabled, mount
  removed, sidebar bookmark dropped) because the app supersedes it.
- **`icloud-photos` albums are USER albums only** — Apple's computed collections
  are not part of its model. Measured on a 8,125-asset library: the app
  catalogued 5 albums (`Pictures` 1401, `DJI Album` 18, `12 Oct 2012` 15,
  `12 Oct 2012 (1)` 2, `Dropbox` 0) while the rclone photos mount exposed 17
  names as folders, adding `Favorites`, `Screenshots`, `Videos`, `Live`,
  `Slo-mo`, `Portrait`, `Time-lapse`, `Panoramas`, `Bursts`, `Animated`,
  `Hidden`, `Recently Deleted`, `iPhoto Events`, `All Photos`. The app browses
  the whole library by MONTH instead. If someone needs a smart collection as a
  browse axis, the retired `rclone-icloudphotos.service` is still on disk and can
  be re-enabled alongside the app.
- **First-run numbers** (what to expect): `icloud-session sign-in` →
  `~/.local/state/icloud-session/account.json` (0600) with dsid/full_name/
  webservices and a 30-day `expires_at`; `icloud-session validate` prints the
  real Apple webservice URLs (the proof the session is live, not just written);
  `icloud-photos sync` on a ~8.1k-asset library took **233s**
  (`8136 updated, 0 removed, 5 albums`) and leaves `incremental_sync_ready: true`.
  `icloud-photos thumb <id>` returning a real JPEG (68 KB in `~/.cache/icloud-photos/thumbs/`)
  is the proof the media path works, not just the catalog.
- **Parsing these CLIs from a shell**: they emit a JSON envelope
  (`{"ok","data","summary"}`) and take `--quiet`/`--ids-only`/`--count`. Do NOT
  inline python with escaped quotes in a `bash -c` one-liner — it breaks on the
  first nested quote (hit twice in one session); write the parser to a file
  (a generic `data <field> <field>` walker is enough) and pipe into it.
- Find My needs its own step (`icloud-session set-password`, keeping the Apple ID
  password in the keyring) — `find_my_authorized: false` is the normal state
  otherwise, and Payments/FindMy are not packaged here anyway.

## Open items

- Notes / Reminders / Contacts / Find My are not packaged (Find My needs
  libshumate; Notes needs Qt6 + qmake and a background sync timer).
- Image integration: the self-contained block in `build_files/build.sh`
  (`dnf5 -y copr enable wegweg7979/icloud-for-omarchy` → install →
  `copr disable`), unguarded.
- The suite's own agent skill (`icloud-session skill install`) is not installed.
