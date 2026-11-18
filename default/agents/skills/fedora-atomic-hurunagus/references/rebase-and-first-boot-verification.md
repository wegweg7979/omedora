# Verifying a rebased atomic host (hurunagus / omedora line)

After a rebase the user reports "it's on the new version" and, later, "no migrations have run".
Neither is proven by the tag string. Everything below is READ-ONLY — run it over ssh, never
against the user's live desktop session, and ask before running anything that writes.

## 1. Did the host actually land on the target build?

- Read the **booted** deployment in `rpm-ostree status` — the `●` entry. Any NON-`●` entry is the
  **staged** one: update downloaded, reboot pending. A host can run the older build while its
  staged entry already advertises the newest `latest.<date>-<sha>`.
- Compare per host: booted digest, `latest.<date>-<sha>` version, and `rpm -q omedora` (its
  `…git<sha>` suffix is the baked-content marker). **Same tag + different omedora NEVRA = one host is
  one build behind** — either it has not rebooted into the staged deployment, or the image was
  rebuilt from the same commit.
- Fedora major: `/etc/os-release` reads `NAME=hurunagus-hyprland` / `VERSION_ID=45` after a rebase.
  The omedora package is built `fc45` for both F44 and F45 hosts, so an `fc44`-era rpm means the host
  is still booted on the older deployment — the rpm release alone does not tell you the host's Fedora.
- `bootc status` on these hosts is the rpm-ostree wrapper; parse `rpm-ostree status` (its `--json`
  form when you need fields such as `.staged`) rather than assuming a bootc-native schema.

Cross-host sweep (read-only, one call):

```sh
for h in workstation desktop laptop mini; do
  printf '%-12s ' "$h"
  timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" \
    'hostname; rpm -q omedora; rpm-ostree status | grep -E "^●|Digest|Version"'
done
```

Distinguishing booted from staged is the whole point of the grep: `grep -E "Version|Digest"` alone
hands you two digests per host with no label and invites reporting the staged one as booted.

## 2. Did the desktop actually arrive? (the skel-adoption signature)

An atomic rebase never seeds `/etc/skel` into an existing `$HOME`. "Rebase landed, omarchy desktop did
not" looks exactly like this:

- `~/.config/hypr/` holds ONLY the old `hyprland.lua` — no `autostart.lua`, `bindings.lua`,
  `looknfeel.lua`, `monitors.lua`, `input.lua`, `xdph.conf`
- no `~/.config/omarchy` at all, and no `~/.local/state/omarchy`
- Hyprland IS running — `start-hyprland` (spawned by `uwsm start -g -1 -e -N Hyprland -D Hyprland --
  start-hyprland` from the image's single session file
  `/usr/share/wayland-sessions/hurunagus.desktop`) — but `pgrep -a quickshell` is EMPTY, so there is
  no omarchy shell

Fix is the hurubase post-reboot checklist (`sudo ./hurubase <address>`), which offers the adoption
file-by-file with `<file>.pre-rebase-<ts>` backups of anything it replaces (`btop.conf`, `foot.ini`,
`kitty.conf` and the stale `hypr/hyprland.lua` are the usual replacements).

## 3. Did first-run and migrations actually run?

Markers (user side) — any of these missing means the machinery never completed:

| Path | Written by |
|---|---|
| `~/.local/state/omarchy/done/first-run-user` | `omarchy-provision-first-run` guard (checked via `omarchy-done check`) |
| `~/.local/state/omarchy/first-run.log` | same command, one line per first-run step |
| `~/.local/state/omarchy/migrations/` | `omarchy-migrate`, one marker per applied migration |
| `~/.local/state/omarchy/agents/usage/` | the shell's agent-usage widget (first session write) |
| `/var/lib/omarchy/migrations/` | machine-side migration markers (only migrations needing root state) |

- `omarchy-provision-first-run` is idempotent and fired ONCE PER SESSION by the compositor start, so
  the chown alone does not repair a host that is already logged in — the session that came up while
  the state dir was root-owned already failed silently. A fresh login/reboot (or a manual run) is
  required; the trigger chain is:

  ```
  ~/.config/hypr/hyprland.lua
    └─ require("default.hypr.omarchy")      -- image: /usr/share/omarchy/default/hypr/omarchy.lua:7
         └─ require("default.hypr.autostart")  -- .../default/hypr/autostart.lua:15
              └─ hl.exec_cmd("omarchy-provision-first-run")
  ```

  Note `~/.config/hypr/autostart.lua` is a comment-only STUB on this line (byte-identical on every
  host) — grep the IMAGE's `default/hypr/autostart.lua` for the call sites, never the user file.
- `omarchy-migrate --pending` lists, `omarchy-migrate` runs, and the blessed `omarchy update` runs it
  for you. Both write as the USER; a root-owned state dir blocks every one of them. NEVER
  `sudo omarchy-migrate` — the markers are `$HOME`-side, so a root run just re-creates the ownership
  bug you are repairing.
- On this image `omarchy update` dispatches to `bin/omarchy-ostree/update`: `ujust update` (else
  `bootc upgrade`) → `omarchy-migrate` → `omarchy-hook post-update` → mise → flatpak. The migration
  step is gated only on the image-apply step not ERRORING, so it still runs the pending migrations
  when the host is already on the newest image — no need to wait for a new build to migrate.
- Two non-signals: `~/.local/state/omarchy/migrations/user/` being EMPTY is normal (a healthy
  installed host reads 0 there too — markers land as files directly in `migrations/`), and
  `/var/lib/omarchy/migrations/` only exists once a migration needs machine-side state. Neither
  absence indicates a problem by itself.

Success signature after the reboot — a never-migrated box reads: 11 first-run steps and ZERO
`Failed` lines in `first-run.log`; `done/first-run-user` + `done/finalize-user`; `agents/usage/`
populated with one JSON per provider; `journalctl -b -t omarchy-shell | grep -c mktemp` = 0; user
units `omarchy-crash-watch` / `omarchy-fcitx5` / `omarchy-migrate-notify` / `omarchy-sleep-lock`
enabled; and `omarchy-migrate --pending` still listing the bulk of 219 migrations (first-run resolves
only a handful — 219 → 215 here — so a large pending count afterwards is expected, not a failure).

### 3a. "The other hosts ran the migrations fine" — almost always false

`omarchy-provision-user --force --first-install` (the ISO / finalize path) marks EVERY shipped
migration complete for that user, so an installed host carries a full marker set and never executes
the chain. Compare marker counts before believing any fleet comparison:

```sh
for h in workstation desktop laptop mini; do
  printf '%-12s %s\n' "$h" "$(timeout 10 ssh -o BatchMode=yes "$h" 'ls ~/.local/state/omarchy/migrations 2>/dev/null | wc -l')"
done
```

A host installed the normal way reads ~220 (every shipped migration); a rebased or foreign-line host
reads a handful. So "it ran fine there" usually means "it ran NOTHING there" — the host that breaks is
the only one running the real 219-migration chain for the first time, and a fresh install is not a
control for it. Say that out loud instead of hunting for a difference in the migrating host.

### 3b. "The update ran" proves nothing about migrations

`bin/omarchy-ostree/update` calls `omarchy-migrate || true`, so an aborting migration does NOT stop
it: the update finishes its hooks/mise/flatpak/distrobox steps and then blocks on
`gum confirm "Reboot now to apply the Omedora image update?"` — visible as a long-lived `gum confirm`
process in `ps -eo pid,etimes,args`. Judge by the marker set, never by "the command finished" or by
the terminal's last line.

### 3c. Triage a migration's write by its TARGET, and by whether that target exists

- `/` is **composefs, mounted `ro`** (`findmnt -no TARGET,FSTYPE,OPTIONS /`) — `/usr` is unwritable at
  runtime even as root, so a migration that writes there (`sudo mkdir -p /usr/lib/chromium`,
  `tee /usr/lib/chromium/initial_preferences`) fails with EROFS and aborts the queue. `/etc` and `/var`
  are writable; the failure is specific to `/usr`.
- Before calling such a step a defect, check its target is even installed (`rpm -q <pkg>`, `ls -d`). A
  seed write for a browser the image never shipped is impossible AND irrelevant — that is the case for
  guarding the migration, not for finding another writable path.
- Migrations that call `sudo` need a real terminal: a non-interactive run dies at the first one with
  `sudo: a terminal is required to read the password` and aborts there, leaving everything after it
  pending. That is what running `omarchy update` in a terminal (or `ssh -t`) is for — sudo/root steps
  are the user's to run, so hand them over rather than marking your way past the wall.

## 4. Ownership: the failure that masquerades as "migrations never ran"

`cp -a /etc/skel/...` preserves ownership, so running the checklist under sudo leaves root-owned
dotfiles. Inventory read-only:

```sh
find "$HOME" -xdev -user root -not -path '*/.cache/*' -not -path '*/containers/*' | head
```

Expected scope of a sudo-run adoption: `~/.config/**`, `~/.local/state/omarchy/**`,
`~/.local/share/applications/**`, `~/.local/share/nautilus-python/**` — nothing at `$HOME` top level
and nothing else in `.local/share`. Compare against a host installed the normal way: there the same
files are `<user>:<user>`.

Why the state dir is the fatal one: `omarchy-migrate` writes its markers under
`~/.local/state/omarchy/migrations/` and `omarchy-provision-first-run` writes `done/first-run-user` +
`first-run.log` — with that dir at root 755, every one of those writes fails, migrations stay
pending, and the shell repeats `mktemp: failed to create file via template
'/var/home/<u>/.local/state/omarchy/agents/usage/.<provider>.XXXXXX': No such file or directory`
every session. One-line proof: `touch ~/.local/state/omarchy/.w` → Permission denied.

Repair sequence (root for the chown, then back to the user):

```sh
sudo chown -R <user>:<user> ~/.config ~/.local/state ~/.local/share/applications ~/.local/share/nautilus-python
chmod 600 ~/.config/omarchy/shell.json     # skel copy lands 644; an installed box has 600
omarchy-provision-first-run                # as the USER, never root
omarchy-migrate --pending && omarchy-migrate
```

Rule: after ANY root-run `$HOME` seeding (rebase checklist, installer, factory reset), verify
ownership before blaming the desktop, the image or a migration.

## 5. Running the checklist itself

- Prompts read `/dev/tty`, so it needs a CONTROLLING TERMINAL: a plain `ssh host '…'` (no `-t`) dies
  with `./hurubase: line 172: /dev/tty: No such device or address`. `ssh -tt` works, as does a real
  terminal on the box.
- Read-only preview of the whole checklist: `./hurubase --dry-run --yes <address>` (or
  `HURUBASE_ANSWERS=<file of y/n lines>`). Bare `--check` only reports whether the host is already on
  the target.
- Use the preview to show the user SCOPE before they approve: it prints `created` / `replaced
  (backed up)` / `created symlink` per path plus an `Adoption` summary line
  (`wrote N, already identical N, left alone (differ) N, never-clobber N, skipped N`).
- Target notes worth relaying verbatim from that output: the skel payload ships in the image, and the
  CachyOS kernel is UNSIGNED — with Secure Boot on, a MOK must be enrolled by hand.

## 6. Reading a rebased host's health without raising false clangers

- `systemd-remount-fs.service` FAILS on every boot of this line: fstab pins the btrfs root subvol
  `ro` (`subvol=root,compress=zstd:1,ro`), so systemd's remount-reconfigure hits
  `mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure.` The root is already
  read-only as intended. It fails identically on every host → noise, not a regression.
- `systemctl --failed` works from a non-interactive ssh; `systemctl --user` needs
  `XDG_RUNTIME_DIR=/run/user/$(id -u)`.
- `/var/lib/AccountsService/users/<user>` is root-readable only, so the recorded-session (`XSession=`)
  check requires sudo; say so rather than reporting "unknown".
- `pgrep -a quickshell` on a healthy box shows `quickshell -n -p /usr/share/omarchy/shell`; the shell
  writes its log to the journal under `-t omarchy-shell` (`journalctl -b -t omarchy-shell`).
- Reboots of other hosts are the user's to run: polkit refuses a reboot from a non-interactive ssh
  session (`Access denied as the requested operation requires interactive authentication`) and sudo
  is password-gated, so ask, then verify the booted deployment afterwards.
