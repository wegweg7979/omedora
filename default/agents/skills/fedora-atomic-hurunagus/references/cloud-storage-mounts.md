# Cloud storage drives in the file manager (Google Drive, iCloud Drive, …)

Use when the user asks "how do I get <cloud service> mountable in Nautilus /
make it show up as a folder" on a hurunagus box. Answer from the LIVE box's backend
inventory, never from the generic "Settings → Online Accounts" advice — that advice is
years stale and, on this image family, wrong for the two services people ask about most.

## Verdict table for this image family

| Service | Route |
|---|---|
| Nextcloud / ownCloud / generic WebDAV / OneDrive / SFTP / SMB | **Native, works.** gvfs ships `gvfsd-dav`, `gvfsd-onedrive`, `gvfsd-sftp`, `gvfsd-smb`; add the account with `gnome-online-accounts-gtk` (standalone UI, needs no GNOME session) or gnome-control-center. Nautilus "Connect to Server" covers WebDAV/SFTP/SMB too. |
| Google Drive | **NOT via GNOME Online Accounts.** No `gvfsd-google` and no `libgdata` anywhere in the repos, so a GOA Google account yields Calendar/Contacts only — never a Drive folder. |
| iCloud Drive | **Never had a GOA provider**, and there is no file-level WebDAV in iCloud (its DAV endpoints are CalDAV/CardDAV = calendar/contacts). Nothing to enable. |
| Google Drive + iCloud Drive | **rclone FUSE mount.** A FUSE mount is a normal filesystem to Nautilus: it appears under "Other Locations" and a bookmark pins it in the sidebar. |

## Probe: which cloud backends does THIS build actually have?

Read-only, seconds, and the whole answer to "can I enable it?":

```bash
ls /usr/libexec/gvfsd-*                  # gvfsd-onedrive / gvfsd-dav yes, gvfsd-google NO
ls /usr/share/gvfs/mounts/               # the same list as mount definitions
dnf5 repoquery --available --whatprovides '*gvfsd-google*'   # empty => the backend does not exist anywhere
rpm -q libgdata                          # the backend's dependency; absent, and not in any repo
ls /usr/lib64/goa-1.0/                   # GOA provider modules, when not compiled into libgoa
strings /usr/lib64/libgoa-backend-1.0.so.1 | grep -iE 'Google|Microsoft|ownCloud|WebDAV'
```

Verified on F45 / gvfs 1.62: `gvfsd-onedrive` present, `gvfsd-google` absent,
`libgdata` unavailable. Re-run the probe on a new release instead of assuming it stays
that way — a backend coming back is the one fact that would change this file.

## rclone: the delivery route for both

- **Fedora repo package, no COPR** — `dnf5 repoquery --available --qf '%{name} %{evr} [%{reponame}]' rclone`. Requires glibc + filesystem **only**; no scriptlets, no weak deps. `fuse3` and `/dev/fuse` are already in the image, so nothing else is needed for `rclone mount`.
- **Verify the backends before promising a service.** Extract the RPM and ask the binary — this is the step that proves "Google Drive and iCloud Drive both work here":
  ```bash
  dnf5 --destdir <scratch> download rclone && cd <scratch>
  rpm2cpio rclone-*.rpm | cpio -idm ./usr/bin/rclone
  ./usr/bin/rclone help backends | grep -iE 'icloud|drive'
  ```
  Confirmed names: `drive` = Google Drive, `iclouddrive` = iCloud Drive and Photos, plus `onedrive`, `webdav`.
- **Image side:** one unguarded `dnf5 install -y rclone` block in `build_files/build.sh` (its own `::group::`, echo `rclone version` at build time). Unguarded on purpose — an image that silently ships without the binary is exactly the failure that made an earlier attempt look like rclone's fault. Never put the config in the image (below).

## Per-user mount shape

Systemd **user** units — `~/.config/systemd/user/rclone-<remote>.service`:

```ini
[Unit]
Description=rclone mount <remote>
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/usr/bin/mkdir -p %h/<MountDir>
ExecStart=/usr/bin/rclone mount <remote>: %h/<MountDir> \
  --vfs-cache-mode writes --dir-cache-time 12h --vfs-cache-max-age 24h --umask 022
ExecStop=/usr/bin/fusermount3 -u %h/<MountDir>
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

- `Type=notify` is right: rclone speaks sd_notify. Add `--poll-interval 15s` **only** for remotes that support change polling (Google Drive does; `iclouddrive` does not).
- Enable with `systemctl --user enable --now rclone-<remote>.service`; a Hyprland session has a running user manager, so no lingering is needed.
- **Sidebar pin:** Nautilus 51 goes through GTK's bookmarks manager, and GTK4 kept the gtk-3.0 path — append `file:///var/home/user/<MountDir> <Label>` to `~/.config/gtk-3.0/bookmarks` (the file already holds the XDG dirs). Starring in Nautilus writes the same file.
- Status: the unit text above is the planned shape, not yet exercised end-to-end on this host. The proof to demand after the first real mount is `systemctl --user status rclone-<remote>` _and_ `ls ~/<MountDir>` (or `rclone lsd <remote>:`) — a green unit with an empty mount dir means the remote, not the unit, is the problem.

## Secrets rule (hard)

`~/.config/rclone/rclone.conf` holds OAuth refresh tokens and the user's Apple ID.
**Never commit it, never bake it into `system_files/`, never print a token value in a
plan or a chat message** — inventory it by remote NAME and key name only:

```bash
awk -F'[][]' '/^\[/{n=$2} /^[a-z_]+ *=/{split($0,a,"="); print n": "a[1]}' ~/.config/rclone/rclone.conf
```

The image ships the binary (and optionally the units); the credentials stay in `$HOME`.
Per-user config belongs to the payload/reapply mechanism only if it is secret-free — see
`references/user-config-delta-capture.md` for that delivery shape.

## Recognising why a previous attempt failed

A `rclone.conf` with a remote configured is NOT a working remote. Before proposing a
mount, run `rclone lsd <remote>:` per remote, and read the user's shell history for how
they last tried (`grep -h rclone ~/.bash_history ~/.zsh_history`) — the failure mode is
usually visible in those lines:

- `rclone mount remote-name: …` — the literal docs placeholder. The real names come from `rclone listremotes`; a name that does not exist fails immediately.
- Mounting in the foreground of a terminal: it dies with the terminal (and gets `killall`ed). Always a `systemd --user` unit.
- An `iclouddrive` remote carrying `apple_id` but no session/password keys was configured but **never logged in** — `rclone config reconnect <remote>:` is interactive (Apple ID password + 2FA). The USER types credentials; the agent never does.
- A mount directory that does not exist yet: create it (`ExecStartPre` above does).

State the iCloud caveats up front rather than letting them discover it: the
`iclouddrive` backend is experimental, drives Apple's private CloudKit API, stores a
session token, and can be broken or invalidated by Apple without notice. It is a
convenience mount, never a backup target.

## The "we had this package in the image and removed it" trap

Do not conclude from a grep of the flagship repo. `git log --all -S rclone` in
`hurunagus-hyprland` matches only `.github/workflows/build-disk.yml` — that is CI
installing rclone **on the runner** to upload disk images to S3, a false positive that
reads like the package was once part of the image. Walk every checkout instead, and
confirm the hit sits in the image-build region:

```bash
for d in ~/hurunagus ~/Documents/GitHub/hurunagus-* ~/omedora-inspect; do
  printf '== %s\n' "$d"
  git -C "$d" log --all --oneline -S <pkg> --format='  %h %ad %s' --date=short | head -5
done
```

- Where a hit legitimately lives: bluebuild lines in `recipes/recipe.yml` (`dnf: packages:`), ublue/bootc lines in `build_files/build.sh`. A package can be in one line's repo and absent from the flagship — a commented-out entry means "removed" without any commit message saying why.
- The removal commit rarely carries the reason; the user's shell history does. Lead with the real diagnosis (placeholder remote, foreground mount, never-logged-in remote) instead of re-adding the package and hoping.
