# Rebranding a forked app and baking it into the image

The user forks a third-party desktop app (`wegweg7979/<app>`), wants it renamed
to their own brand, packaged, and installed in `hurunagus-hyprland`. This file is
the procedure: read-only recon FIRST, the rebrand tier rules, the two traps that
kill options, and where each piece lives. Sizing beats editing — do not clone and
grep hundreds of files before you know the token surface.

## 1. Recon read-only, before any clone

Nothing here writes to disk or touches the user's repos:

```bash
gh repo view <owner>/<fork> --json name,description,parent,defaultBranchRef,licenseInfo,homepageUrl
gh api repos/<owner>/<fork>/compare/master...<upstream-owner>:master --jq '{ahead:.ahead_by,behind:.behind_by}'
gh api repos/<upstream-owner>/<app>/git/trees/HEAD?recursive=1 --jq '.tree[].path' | head -80
curl -fsSL https://raw.githubusercontent.com/<owner>/<fork>/master/README.md
```

Read `README.md`, `Makefile`, `.gitmodules` and `distro/` from the **fork** (it is
byte-identical to upstream on a fresh fork) — those three files answer nearly
everything: build system, install layout, embedded assets, and which sibling
repos are hard dependencies.

Two lookups that save the most time:

- **Does the upstream org ship distro packaging?** `gh api
  repos/<org>/<org>-repo/git/trees/HEAD?recursive=1 --jq '.tree[].path' | grep -i
  'fedora\|copr'`. A maintained `distro/fedora/<app>/<app>.spec` is a WORKING
  Fedora spec — derive ours from it instead of inventing BuildRequires and
  install paths. Look for `distro/{arch,debian,fedora,opensuse,void}/` too.
- **Does the upstream org already publish a COPR?** `curl -s
  "https://copr.fedorainfracloud.org/api_3/project/search?query=<org>"` and
  `api_3/build/list?ownername=<org>&projectname=<repo>&limit=8` — `succeeded`
  builds of the app + its runtime prove the packaging path works on this Fedora
  release, and give a baseline for "the app is installable without us".

Then probe the running host (it is the same image family): `rpm -q` loop over the
runtime deps, `rpm -E %fedora`, `dnf5 repoquery --available` for the toolchain the
spec needs. On this host the Fedora 45 line carried `golang 1.27.3` and
`quickshell 0.3.2` + `qt6-qtdeclarative 6.11.2`; a Go app whose `go.mod` says
`go 1.27.3` is therefore buildable in a `fedora-45-x86_64` chroot.

## 2. The two traps that decide the plan

Surface both in the FINDINGS of the plan, before the options table — each one can
eliminate a delivery option, and the user prunes options, not caveats.

**Baked third-party credentials are usually NOT licensed for forks.** Check the
LICENSE / README tail for OAuth client IDs. Upstream's wording is the rule: the
shipped Google/Microsoft client IDs identify the upstream application and
"forks, rebranded builds" must register their own, supplied at build time
(`-ldflags -X`) or runtime (env var). A rebrand either strips them (features
needing no client ID keep working — CalDAV/iCloud via app-specific password, local
calendars, `.ics` import) or the user registers their own app with each provider
(an external credential action — theirs to do, never the agent's). Never bake
upstream's credentials into a renamed build.

**Never rename the app's config/data/state namespace when the user already has
data there.** Check first: `ls ~/.config/<name> ~/.local/share/<name>`. The
namespace is typically one string in a paths helper (e.g. `paths.go` calls
`dankpaths.New("dankcal")`) that fans out to config, data, cache, state and the
IPC socket. Renaming it orphans the user's database, keyring entries, accounts
and settings on their live box, in exchange for a cosmetic win. Keep it, and say
explicitly in the plan that this is why (the user's first choice may be the other
way until they hear it costs them their accounts).

## 3. Rebrand tiers — size with a token census

```bash
git grep -I -c -i -- <token> | awk -F: '{s+=$NF} END{print s+0}'
git grep -I -l -i -- <token> | wc -l
```

Expect a handful of tokens in the hundreds of hits (product name, binary, config
dir, upstream org) spread over 80-200 files. Split them into tiers; the
user-visible tier is small (~20 files) and is what actually gets rebranded.

| Tier | Surfaces | Default |
|---|---|---|
| User-visible, rename | product name in README/docs/metainfo/About, RPM name, `Name=`/`Comment=`/`Icon=`, desktop-entry filename, icon SVG, systemd unit filename, window/notification/tray strings, completions script names | rename |
| Internal contract, keep | config/data/state/socket namespace (rule above), env-var prefix the Go code and QML share, Go module path, sibling submodule URLs | keep unless asked |
| Upstream infrastructure, prune | CI workflows pointing at upstream's release/flatpak/nix/i18n+translation-service secrets | prune or disable in the same pass |

A rename touches the packaging too: the desktop entry's `Exec`, the unit's
`ExecStart`, and any install script that hardcodes the old binary name. The
daemon's self-reexec uses the running executable path, so it follows the rename
for free.

**App naming convention for this user's own apps (from airgraph):** a flat name,
no reverse-DNS id — `Name=<App>`, `Exec=<app>`, `Icon=<app>`,
`%{_datadir}/applications/<app>.desktop`. A four-letter CLI name parallel to the
upstream one (`dcal` → `hcal`) is the natural pick for a daemon+CLI app; the RPM
carries the long human name (`huru-calendar`).

## 4. Delivery options (pick one, state the cost)

The app must arrive in the image as an RPM. Shape the choice around what the app
runtime needs:

| Option | Shape | Cost |
|---|---|---|
| Own COPR, one RPM, runtime embedded | build the app against the vendored runtime source so the shared object is baked inside the binary (upstream's Flatpak manifest shows the flags: `-DCMAKE_INSTALL_LIBDIR=<subdir next to the binary>`); image installs one package | heavy build deps live in the COPR chroot, not the image; we rebuild when Fedora bumps Qt |
| Own COPR, two RPMs | app RPM + the runtime library as its own package (copy upstream's spec) | same Qt-rebuild duty, a second package to babysit |
| Build inside `build.sh` | clone + compile in the Containerfile, no COPR | adds the C++/Go build and a Qt-private-devel layer to EVERY image build; see `references/build-times-and-layer-cache.md` |

Any option that compiles against the distro's Qt has the same ABI exposure: the
runtime library (embedded or not) links the SYSTEM Qt at runtime, so Fedora Qt
bumps require a rebuild either way. Never present embedding as solving ABI drift.

The runtime-library dependency is resolved at runtime by a dlopen search — next to
the binary, then a sibling `lib/<app-name>/` dir, then the bare soname in the
system library dirs — so a system-package route and an embedded route are
interchangeable from the app's side. Read the dependency's own loading code
before assuming which packages must ship.

## 5. Image-side seams

Same as any baked app (`references/copr-app-publishing.md` §"Image integration"):
own group block in `build_files/build.sh` at the app-install seam, unguarded
install, COPR disabled afterwards, never in the resolved package lists.
Additionally, when the app is a daemon + GUI shell:

- A shipped `%{_userunitdir}/<app>.service` starts nothing by itself. Wire login
  start declaratively from `system_files/` (`/etc/systemd/user/default.target.wants/`
  symlink) or `/etc/xdg/autostart/<app>.desktop` — `systemctl --global enable`
  does not work inside a container build.
- Menu/keybind row goes in the user's look-and-feel payload,
  `system_files/usr/share/hurunagus/config/.config/omarchy/extensions/omarchy-menu.jsonc`
  (dotted id, `icon`/`label`/`action`), not in the fork.
- A tray-icon feature is dead weight unless the bar hosts a StatusNotifier item
  host; check before promising tray integration — the daemon + IPC surface works
  regardless.

## 6. Domain note: the Dux Labs stack (several of their apps share one anatomy)

Any `duxlabs-dev` app the user adopts has this shape — worth knowing before the
next one:

- `core/` = Go daemon + CLI, pure Go (`CGO_ENABLED=0`), no vendor dir in the repo;
  upstream release tarballs ship vendored modules + the QML submodule, so a COPR
  spec either fetches an extra Source for the submodule or vendors in-fork.
- `quickshell/` = QML UI embedded into the binary via `go:embed`; `quickshell/DCommon`
  is a symlink into the `dux-qml-common` submodule, and `go:embed` rejects
  symlinks — the build dereferences it (`cp -aL`, `tar -h`).
- `libdux-qt-base.so.0` = `dux-qt-base`, their **fork of Quickshell built as a
  shared library** (LGPL-3.0) exposing `dqb_main()`; the host binary re-execs
  itself with a `qs` subcommand and dlopens it. It is not upstream `quickshell`.
- Packaging reference: `duxlabs-dev/dux-repo` → `distro/fedora/<app>/<app>.spec`
  (+ `-git` twins), published to COPR `duxlabs/dux-repo`; their scripts bump
  `Version:`/tags, so the twin specs stay in lockstep.
- Their OAuth client IDs and translation-service workflows are the parts that
  must not travel into a fork (see §2).
