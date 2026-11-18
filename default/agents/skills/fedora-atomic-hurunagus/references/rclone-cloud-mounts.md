# Cloud drives (Google Drive, iCloud Drive) mounted into Nautilus

Goal shape: "get Google Drive and/or iCloud Drive mountable in Nautilus" on the
bootc Hyprland box. On Fedora 45 / GNOME 51 this **cannot** be done through
GNOME Online Accounts — it is rclone + systemd user units, or nothing.

## Why GOA is not an option any more (verified 2026-11, F45 image)

- `gvfs-1.62` ships `gvfsd-onedrive`, `gvfsd-dav`, `gvfsd-sftp`, `gvfsd-smb`,
  `gvfsd-mtp` … and **no `gvfsd-google`**. `dnf5 repoquery --available
  --whatprovides '*gvfsd-google*'` → nothing; `libgdata` (its only possible
  dependency) is **not in the Fedora repos at all**. So "Settings → Online
  Accounts → Google" yields Calendar/Contacts, never a Drive folder in Files.
- iCloud never had a GOA provider, and iCloud exposes no file-level WebDAV
  (its DAV endpoints are CalDAV/CardDAV — calendar and contacts only).
- Nautilus "Connect to Server" (WebDAV/SFTP/SMB) therefore reaches neither
  service. Say this plainly instead of handing over GOA steps that cannot work.
- GOA-backed mounts that DO still work here: OneDrive, WebDAV/Nextcloud, SFTP, SMB.

## The package (no COPR, no risk)

`rclone 1.75.2-2.fc45` from *Fedora 45 Updates*; `--requires` is glibc +
filesystem only, no scriptlets, no Recommends/Suggests; `fuse3` and `/dev/fuse`
already present in the image. Its `drive` and `iclouddrive` backends are both
compiled in — prove with `rclone help backends` on the extracted binary.

Image side: one unguarded block in `build_files/build.sh`, after the
`huru-calendar` block and before `install_packages()` (commit `2e1e50f`):

```bash
echo "::group:: Installing rclone (cloud storage mounts)"
dnf5 install -y rclone
echo "rclone installed: $(rclone version | head -n1)"
echo "::endgroup::"
```

Unguarded on purpose — an image that silently lacks rclone was the failure mode
that made the earlier attempt undiagnosable. Do NOT put it in `EXTRA_PACKAGES`:
that path's failures are warnings unless the name is added to the required-case
list.

## Prove it BEFORE the image build (the step that matters)

Nothing needs installing to test the whole stack — run Fedora's own binary out of
the RPM:

```bash
cd <scratch> && dnf5 -q download --destdir . rclone
rpm2cpio rclone-*.rpm | cpio -idm --quiet ./usr/bin/rclone
cp -p ~/.config/rclone/rclone.conf <scratch>/rclone.conf.bak   # token refresh REWRITES it
./usr/bin/rclone version
./usr/bin/rclone about google-drive:      # proves the remote + token refresh
./usr/bin/rclone lsd google-drive:
./usr/bin/rclone lsd icloud:              # expect the trust-token error, see below
```

Then prove the systemd shape without writing a unit:

```bash
systemd-run --user --unit=rclone-test --service-type=notify --collect \
  -p Restart=no -p TimeoutStartSec=40 -- ./usr/bin/rclone mount google-drive: <mnt> \
     --config=~/.config/rclone/rclone.conf --vfs-cache-mode writes
systemctl --user show rclone-test -p Type -p ActiveState -p SubState --value
findmnt -no FSTYPE,SOURCE <mnt>      # expect: fuse.rclone google-drive:
ls <mnt> | head                       # real remote files through the mount
systemctl --user stop rclone-test     # then confirm the mountpoint is empty
```

`Type=notify` is CORRECT for this package (rclone sends sd_notify; the unit goes
`active`/`running`, verified on host). A plain FUSE mount does **not** appear in
`gio mount -l` — Nautilus shows it as a mounted filesystem, so test with
`findmnt`/`ls`, never `gio mount -l`.

**A cold mount makes Nautilus sit on `Loading…` for a long time — that is not a
broken mount.** Verified on the first open after boot: both Nautilus windows
showed an empty pane and a `Loading…` spinner for well over 12 seconds while
rclone warmed its directory cache against a large Drive, then the entries
appeared on their own (54 top-level entries; the user's own words were "no files
seen yet" → "ok they appeared now"). Do not "fix" it, do not kill the service:
check the mount instead with `ls ~/GoogleDrive | wc -l` and
`journalctl --user -u rclone-gdrive.service`, and expect later opens to be fast
because `--dir-cache-time 12h` keeps the listing warm.

### Restarting a live rclone mount can WEDGE it — always use LAZY unmount

Restarting the unit while the mount is IN USE (Nautilus browsing it, a download in
flight) makes rclone's shutdown unmount fail — ``fusermount3: failed to unmount
…: Device or resource busy`` — and rclone then exits leaving a **stale FUSE mount**
behind. The next start dies before rclone even runs:

```
mkdir[53282]: mkdir: cannot stat '/var/home/user/GoogleDrive': Transport endpoint is not connected
rclone-gdrive.service: Control process exited, code=exited, status=1/FAILURE
```

leaving the unit in an `activating`/`auto-restart` loop with an unreachable
mountpoint (`ls` → `Transport endpoint is not connected`).

- `-u` is NOT enough on a hung mount: it fails with the same `Device or resource
  busy`, so an `ExecStartPre=-/usr/bin/fusermount3 -u` guard STILL lets the
  following `mkdir -p` fail and the unit keeps looping. Use **lazy**:
  `fusermount3 -uz <dir>`. Both units therefore carry
  `ExecStartPre=-/usr/bin/fusermount3 -uz %h/<dir>` AND
  `ExecStop=/usr/bin/fusermount3 -uz %h/<dir>`.
- Manual recovery of a wedged mount: `fusermount3 -uz <dir>` →
  `systemctl --user reset-failed <unit>` → `systemctl --user start <unit>`.
- **Always verify after a restart** — `findmnt` plus an entry count. `systemctl`
  reporting `active` is not proof the mount came back (this happened while the
  mountpoint was dead). Validate a unit change by doing the risky thing on purpose
  once (restart while Nautilus holds the mount) rather than trusting the guard.
- Expect this class of failure again at the 30-day iCloud re-auth and on every
  reboot churn.

### Why the first browse feels slow (and what actually helps)

Measured on this box: warm directory listings are 0.00s, and 80 attribute stats
went from **0.26s to 0.00s** after setting `--attr-timeout 1m` — rclone's default
is **1s**, so every Nautilus pane refresh re-stat'ed the whole directory over the
network. `--dir-cache-time 12h` is the other half of the fix. What CANNOT be tuned
away is the first-ever listing of a directory rclone has not seen: that is a Drive
API round-trip. Nautilus-side, check `show-image-thumbnails`
(`'local-only'` here — a memory of network thumbnailing is the first suspect and
was NOT the cause) before blaming the mount. If repeat *file opens* (PDFs, media,
previews) are the slow part rather than listings, the lever is
`--vfs-cache-mode full` with a `--vfs-cache-max-size` cap so reads come from local
disk — `writes` (the initial setting) caches writes only.

**On the booted host after the rebase:** the package lands at `/usr/bin/rclone`
(also present as `/usr/sbin/rclone` — this image uses unmerged-sbin symlinks, so
`command -v rclone` can report the `/usr/sbin` path; both exist, the unit's
`/usr/bin/rclone` is correct). Deploying means `rpm-ostree status` shows the
booted digest equal to the image manifest digest you probed, then
`systemctl --user enable --now rclone-gdrive.service`, then `findmnt -no
FSTYPE,SOURCE,TARGET ~/GoogleDrive` → `fuse.rclone google-drive: …`.

## Per-user payload (stays in `$HOME`, never in the image)

`~/.config/systemd/user/rclone-gdrive.service` and `rclone-icloud.service`: the
shape that was verified is

```ini
[Service]
Type=notify
# lazy unmount FIRST — a hung mount cannot be cleared with -u, and the bare
# `mkdir -p` that follows then fails with "Transport endpoint is not connected"
ExecStartPre=-/usr/bin/fusermount3 -uz %h/GoogleDrive
ExecStartPre=/usr/bin/mkdir -p %h/GoogleDrive
ExecStart=/usr/bin/rclone mount google-drive: %h/GoogleDrive \
  --config=%h/.config/rclone/rclone.conf --vfs-cache-mode writes \
  --dir-cache-time 12h --attr-timeout 1m --poll-interval 15s \
  --vfs-cache-max-age 24h --umask 022
ExecStop=/usr/bin/fusermount3 -uz %h/GoogleDrive
Restart=on-failure
RestartSec=10
```

- Google Drive supports change polling (`--poll-interval`); **iclouddrive does
  not** — omit the flag there.
- `WantedBy=default.target` + `After/Wants=network-online.target` (a user-manager
  target that exists here).
- Sidebar icons are just two lines appended to **`~/.config/gtk-3.0/bookmarks`**
  (Nautilus 51 still uses that path — its binary links GTK's
  `_gtk_bookmarks_manager`): `file:///var/home/<user>/GoogleDrive GoogleDrive`.
- `rclone.conf` holds OAuth refresh tokens and the Apple ID. It is a `$HOME` file
  (0600) — never baked into the image, never committed, never echoed in full.
  Print remote *names/types* (`configparser`), never values.

## iCloud PHOTOS on the same remote (added 2026-11-15)

The `iclouddrive` backend serves Photos too (`service = photos`), and the choice of
shape matters for maintenance:

- **Do NOT create a second remote for Photos.** Copying `[icloud]` to
  `[icloudphotos]` and flipping `service` works (the obscured password, cookies and
trust_token carry over, so no second 2FA at setup) — but the copy holds its OWN
trust token, so the 30-day renewal needs TWO 2FA logins, one per remote.
- **Use the per-mount override instead:** keep one `icloud:` remote and add
  `--iclouddrive-service photos` to that unit's `ExecStart`. The flag overrides the
  remote default for that process only, so one `rclone reconnect icloud:` renews
  everything. Flags that work (rclone's own docs recommend the shape for Photos):

  ```
  /usr/bin/rclone mount icloud:PrimarySync %h/iCloudPhotos \
    --iclouddrive-service photos --read-only \
    --vfs-cache-mode full --vfs-cache-max-size 20G --vfs-cache-max-age 72h \
    --vfs-refresh --dir-cache-time 1h --attr-timeout 1m --umask 022 --log-level INFO
  ```

  (`--vfs-refresh` pre-warms dir caches in the background; `--dir-cache-time 1h`
  is what the docs suggest here because change detection is a ~200ms check.)
- **Hierarchy:** level 1 = libraries (`PrimarySync`, plus `SharedSync-XXXX` when a
  shared library exists — only `PrimarySync` existed on this account), level 2+ =
  albums (`All Photos`, `Favorites`, `Hidden`, `Screenshots`, `Videos`, `Live`,
  `Slo-mo`, `Portrait`, `Time-lapse`, `Panoramas`, `Bursts`, `Animated`,
  `Recently Deleted`, `iPhoto Events`…), leaves = photos/videos including the
  `.MOV` companions of Live Photos (which is why `ls Favorites | wc -l` (84) exceeds
  the count column `rclone lsd` prints (75) — the delta is the .MOVs).
- **Photos is READ-ONLY** — upload, delete, rename and move are unsupported, and
  `--read-only` makes that explicit (a `touch` in the mountpoint returns
  `Read-only file system` instead of a confusing write error). Getting photos out
  is a copy: `rclone copy icloud:PrimarySync/Favorites ~/Pictures/… \
  --iclouddrive-service photos`.
- **Album listings are cached on disk** at
  `~/.cache/rclone/iclouddrive-photos/<remote>/<zone>/` (`libraries.json`,
  `albums.json`); a first listing of a huge album such as `All Photos` can take
  MINUTES, and subsequent ones are fast. `rclone config reconnect <remote>:` also
  clears that cache.
- Timings measured here: `PrimarySync` libraries 2.45s, album list 4.19s, the
  mounted album list 1.76s, `Favorites` 84 files.

## Browsing the mounts: which viewer, and what a remote album costs

The number that decides app choice — reading through FUSE: the FIRST fetch of a file
costs **~1.5s** (8 cold photos / 8.8 MB in 11.8s), every later read **~0.01s** once the
read cache holds it. So a thumbnail grid over a COLD album is slow once (`Favorites`
≈ 1–2 min) and instant afterwards; point grid apps at a locally copied album for
anything large. Warming by browsing beats warming by waiting: `--vfs-refresh`
pre-warms in the background.

Viewers on this box (checked, not assumed):

- **Loupe** — the current double-click default: `~/.config/mimeapps.list` maps
  jpeg/png/gif/webp/avif/svg to `org.gnome.Loupe.desktop`, and it is installed as a
  FLATPAK, so `/usr/share/applications` has no loupe entry at all. Check
  `flatpak list --app` before calling a default broken.
- **imv** — native, baked by Omarchy's own list (`build_files/omarchy-base.packages`);
  ships `imv.desktop` + `imv-dir.desktop`, both `NoDisplay=true` (absent from menus
  but still valid `Open With`/CLI handlers). Omarchy's
  `default/applications/mimeapps.list` intends imv as the image default; a user
  `~/.config/mimeapps.list` overrides it, and that is what wins.
- **mpv** — for the `.MOV` files (the iCloud `Videos` album and Live Photo companions).
- **swayimg** — the only Wayland-native option with a GALLERY grid, and it decodes
  video via FFmpeg, so one app covers a whole photo library. NOT in the image: test it
  uninstalled first (SKILL.md §"Adding a package…" step 2 — it needed `minizip-ng`
  extracted alongside on `LD_LIBRARY_PATH`). Modes: `-g` gallery, `-v` viewer,
  `-s` slideshow, `-P X,Y` / `-S W,H` position/size (Hyprland-aware), `-a` app id for
  window rules.

## Two things that will break it later — say them out loud

1. **Google `client_id` — DONE on this box (2026-11-14): the `google-drive` remote
   now uses the user's own OAuth client.** rclone's shared client_id is being
   retired during 2026 and prints a ``NOTICE: … shared Google Drive client_id …
   will stop working during 2026`` on every Drive call. The worked procedure, with
   the traps that cost real time:

   - **Project + API.** New Cloud project, then **enable the Drive API**
     (`console.cloud.google.com/apis/library/drive.googleapis.com?project=<num>`).
     Skipping this is the likeliest failure: the new client authenticates
     perfectly and then EVERY call returns `403 … Google Drive API has not been
     used in project <num> before or it is disabled`. That 403 naming the project
     number is also how you confirm the new client is the one in use.
   - **Consent screen (Google Auth Platform).** App name, audience **External**,
     add yourself as a test user, then **Publish app**. TRAP: left in *Testing*,
     grants expire **every 7 days** (per rclone's own docs) and the mount dies
     weekly, looking like a broken remote. Publishing only means clicking through
     "Google hasn't verified this app → Advanced → Go to <app>" once; personal use
     under 100 users needs no verification. If **Publish app** is greyed out, fill
     Branding (app home page + privacy policy URL) and Authorized domains first.
   - **Client type must be `Desktop app`** — a *Web* client will not work with
     rclone's loopback redirect flow.
   - **Switchover.** `rclone config` → `e` → `google-drive` → "Continue using the
     shared client_id anyway?" → **n** → paste client_id + secret → keep scope
     `drive` → "Token already configured - replace it?" → **y** → approve in the
     browser. The old token is bound to the retired client, so the remote is dead
     between the edit and the approval — expected, not a bug. The USER runs this,
     so the secret never passes through chat or shell history (`config update
     client_secret=…` would leave it in history).
   - **Afterwards.** `rclone lsd google-drive:` must list with NO NOTICE — that is
     the proof the new client is live — then `systemctl --user restart
     rclone-gdrive.service`. A running mount does re-read the config on token
     refresh (the live one started hitting the new project's 403s on its own), but
     restart anyway so the switch is clean. `rclone about google-drive:` is a good
     second proof: it answers only when the API is enabled for that client.
   - **Check for a reusable client before sending the user to the console:** none
     existed here — huru-calendar is iCloud-only (`DANKCAL_GOOGLE_CLIENT_ID`
     unset, upstream creds blanked) and the keyring held no Google OAuth
     credentials.
2. **The `icloud` remote starts as a stub — `apple_id` only, no `password`,
   no `cookies`, no `trust_token`.** Every call then dies with
   `missing icloud trust token` (or, from `config reconnect`, an attempted SRP
   login that Apple answers `503`/`401`). **`reconnect` cannot fix this**: it
   only REFRESHES an existing token and needs `password` in the config already.
   The first token comes from the interactive walkthrough, which the user runs
   themselves (never type their credentials):

   ```
   rclone config            # e) Edit existing remote -> icloud
                            #   service: keep (drive)
                            #   apple_id: keep
                            #   password: the REAL Apple ID password
                            #   config_2fa: trusted-device code, or type 'sms'
   rclone lsd icloud:       # must list before any mount is enabled
   ```

   Editing beats delete+recreate (nothing of theirs is removed); the completed
   remote then carries `password` + `cookies` + `trust_token` and `reconnect`
   works for later refreshes. App-specific passwords are REJECTED — the regular
   Apple ID password plus 2FA is the only accepted path, and the trust token is
   valid **30 days**, so expect a monthly re-auth that looks exactly like a
   broken mount. The `iclouddrive` backend is Apple-private-API/experimental and
   `about` is unsupported (`doesn't support about` is normal): treat the mount as
   convenience, not backup.
3. **THE COLON TRAP, which this user hit three times in a row: a bare remote name
   is a LOCAL FOLDER to rclone.** `rclone lsd icloud` → `"icloud" refers to a
   local folder, use "icloud:"` / `directory not found`; `rclone config reconnect
   icloud` → the actively misleading `backend doesn't support reconnect or
   authorize`, because the resolved backend was `local`. Distinguish it from a
   genuinely unknown remote by the error text — `rclone config reconnect
   nosuchremote:` (WITH the colon) says `didn't find section in config file`.
   Before diagnosing anything, check `rclone listremotes` and quote the trailing
   colon in every command handed over.
4. **Probe an unfamiliar backend's capabilities on a THROWAWAY remote in a
   scratch config** (`rclone --config <scratch>/probe.conf config reconnect
   dummy:` with a `<email>` id) — never against the user's real
   account. That test proved `iclouddrive` does implement `reconnect` (clean
   `401`) without spending a login attempt on their Apple ID; probing the real
   remote first got Apple to answer `503` and cost one useless authentication
   attempt that had to be disclosed.

## Diagnosing "I tried rclone before and it didn't work"

Check the shell history for the literal failure rather than guessing. On this box
the history showed `rclone mount remote-name: ~/Cloud/GoogleDrive
--vfs-cache-mode writes` — a literal placeholder remote name, a mount run in the
foreground (dies with the terminal), a `killall rclone`, and an `icloud` remote
configured with `apple_id` but **no session/trust token**. Paired with the fact
that rclone was never in the *hyprland* image at all (the earlier entry lived in
`hurunagus-silverblue/recipes/recipe.yml`, added `5d0d0b8`, commented out at
`a2f0fbb`), that is four independent reasons nothing could have worked — none of
them rclone's fault. Establish which image ever had the package
(`git log -S rclone` per repo) before believing the user's "I removed it".
