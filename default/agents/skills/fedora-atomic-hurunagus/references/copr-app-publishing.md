# Publishing a standalone app to Fedora COPR

The user's own apps go to their own GitHub repo and their own COPR project
(`<owner>/<app>`), not into the omedora fork. Drive COPR's API v3 with `curl` —
no `copr-cli` install is needed on an immutable host.

## Credentials

- The token page is `https://copr.fedorainfracloud.org/api/` (must be logged in;
  an account provisioned minutes ago may lag — confirm the header shows the
  username before assuming a missing button). It shows a whole `[copr-cli]` block.
- Save it to `~/.config/copr`, mode 600. The block's `login` field is the username
  used for basic auth; `username` is the account name.
- **Basic auth is `-u "$login:$token"`.** Using `username:$token` fails with
  `Login invalid/expired. Please visit .../api to get or renew your API token.` —
  a valid token looks dead. Keep the secret out of argv/output: a tiny script
  that `sed`s the fields out of the file is enough.
- A GET for a project that does not exist returns 404 whether or not auth works,
  so auth cannot be proven from a read. Prove it with a write (project create).

## Project settings you CANNOT change, and what they actually mean

`auto_prune` and `persistent` are **COPR-admin-only** fields. The token
authenticates (`copr-cli whoami` → the username) and the edit still fails:

```
$ copr-cli modify <owner>/<project> --auto-prune off
exit=7
Error: Operation requires API authentication. …
Error: Non-admin cannot disable auto-prunning.
```

No user-facing route exists: `PATCH`/`PUT`/`POST /api_3/project`, and the legacy
`api_2/edit/project` + `api/edit/project`, all answer 404. Do not promise the
user this toggle — only a COPR admin can flip it.

**Do not treat `auto_prune: true` as a fragility.** Retention is documented: COPR
keeps ONE build per package per project indefinitely and deletes only the older
ones after 14 days; on the **Pulp** backend (check `"storage": "pulp"` in the
project JSON) retention is count-based — the 5 most recent successful builds per
package. Either way the newest build of a published app does not age out from
project inactivity, so an image that installs it from the COPR stays buildable.
Assess this from COPR's retention rules, not from the flag's name (a warning
built on the name alone sent the user chasing a non-problem).

## Driving COPR on the immutable host

`copr-cli` is not installed and `dnf5 install` cannot write `/usr`, so make a
scratch venv — it reads the token from `~/.config/copr` automatically:

```bash
python3 -m venv "$SCRATCH/coprvenv" && "$SCRATCH/coprvenv/bin/pip" install --quiet copr-cli
"$SCRATCH/coprvenv/bin/copr-cli" whoami          # proves the token works
```

Reads work over plain REST too: `GET /api_3/project?ownername=<o>&projectname=<p>`
with `Authorization: Bearer <token>` (print only selected keys — the JSON is
large and the token must never reach stdout).

## Endpoints (verified against the live API)

| Method + path | Purpose |
|---|---|
| `POST /api_3/project/add/{owner}` | create; JSON `name`, `chroots`, `description`, `instructions`, `homepage`, `contact`, `enable_net` |
| `POST /api_3/project/edit/{owner}/{project}` | edit metadata |
| `POST /api_3/package/add/{owner}/{project}/{pkg}/scm` | SCM package; JSON **`package_name` (required in the BODY too)**, `clone_url`, `committish`, `spec`, `scm_type: "git"`, `source_build_method: "rpkg"`, `webhook_rebuild: true` |
| `POST /api_3/package/edit/{owner}/{project}/{pkg}/scm` | edit; **POST**, not PUT (PUT answers "The method is not allowed") |
| `POST /api_3/package/build` | trigger; JSON `ownername`, `projectname`, `package_name` |
| `GET /api_3/build/{id}` | `state`, `source_package.url`, `repo_url` |
| `GET /api_3/build/built-packages/{id}` | per-chroot package list |
| `POST /api_3/webhook/generate/{owner}/{project}` | no body; returns `{"id": <project id>, "webhook_secret": "<uuid>"}` — build the URL yourself: `/webhooks/github/<id>/<secret>/<pkgname>/` |

- **`contact` must be an email address or a URL** — a bare username is refused
  with `{"error": "contact: Contact must be email address or URL"}`.
- **`package_name` is required in the SCM-add BODY**, not just in the path:
  omit it and the API answers `package_name: Please enter a valid package name
  in ^[-+_.a-zA-Z0-9]+$` about a perfectly valid name. (The path segment alone is
  not enough — read `copr/v3/proxies/package.py` when in doubt: it sends
  `data = {"package_name": packagename}`.)
- `auto_prune` is refused **at creation** for a non-admin too
  (`Non-admin cannot disable auto-prunning.`) — leave it out of the create body
  rather than retrying forever; see the retention rules above for why it does
  not matter.
- **`enable_net: true` is mandatory for a Go package** whose build downloads
  modules; without it the chroot has no network and `go build` fails.
- Installable check without touching `/etc/yum.repos.d` (tags, `dnf5` here is
  option-order sensitive):
  `dnf5 --setopt=cachedir=<scratch>/dnfcache --repofrompath=<name>,<repo_url>/fedora-45-x86_64/ --repo=<name> repoquery --available --latest-limit=1 --qf '%{location}\n' <pkg>`.
  `%{location}` prints the src AND the binary RPM — grep for the arch you want
  before curling it, or the URL comes out doubled and 404s.

- `auto_rebuild` is the READ field; the writable field on a package is
  `webhook_rebuild: true`. Set it, or the webhook fires and rebuilds nothing.
- `/api_3/project?ownername=…` needs `projectname` too, or it answers
  "Missing argument projectname" — the endpoint takes both or neither.

- **Reading `~/.config/copr` by hand is a trap, and a working GET proves nothing.**
  An `awk`-based `login:token` split (the shape this file's own docs suggest)
  produced credentials that failed every write with `Login invalid/expired. …`
  while project **reads kept working** — because COPR project metadata is
  public, so a GET succeeds without any auth at all. Parse the file with a real
  INI parser and strip whitespace, or sidestep it entirely:
  `python3 -m venv <scratch>/coprvenv && <venv>/bin/pip install copr-cli` then
  `copr-cli whoami`, which parses the file itself and prints the account name.
  `copr-cli` also covers the whole flow (`create --chroot … --enable-net on`,
  `add-package-scm … --spec rpm/<app>.spec --commit main --method rpkg
  --webhook-rebuild on`, `build-package <project> --name <pkg> --nowait`,
  `watch-build <id>`), so prefer it and keep raw `curl` for the endpoints it
  lacks (webhook generation).
- **`copr-cli` 2.9 (the new CLI) has NO `--homepage`/`--contact` on `create`** — both
  are `unrecognized arguments` (and a failed create leaves no project, so the
  following `add-package-scm` answers `Project <owner>/<project> does not exist`).
  Create with `--chroot fedora-<N>-x86_64 --enable-net on --description --instructions`
  and set the two metadata fields afterwards:
  `POST /api_3/project/edit/<owner>/<project>` with `{"homepage": …, "contact": …}`
  → HTTP 200 (this endpoint works for metadata; `auto_prune`/`persistent` stay
  admin-only). Project-level `enable_net` shows up as `enable_net: true` in the
  project JSON. Read the project id from the webhook-generate response, not a guess.
- **`add-package-scm <project> --name <pkg>` takes the project as a positional**
  (same as `build-package <project> --name <pkg> --nowait`, which replies with the
  build URL and `Created builds: <id>`). `--webhook-rebuild on` is the writable field.

- **Multi-package specs**: one spec can carry several packages plus a
  metapackage; the main package needs a non-empty `%files` (give it the
  `%doc`/`%license` pair) or the build fails on an empty file list. Verify it the
  way COPR will build it — `dnf5 builddep -y --spec <spec>` installs ONLY the
  declared BuildRequires, so an undeclared-but-transitively-available dependency
  shows up as a failure there instead of silently working in your container.
- **A blank `Signature:` line from `rpm -qip` does not mean unsigned.** With the
  key not imported, that field prints empty while the package really carries
  `Header OpenPGP V4 RSA/SHA256`; read it with
  `rpm -qp --qf '%{rsaheader:pgpsig}'` or `rpm --checksig -v` (`NOKEY` there just
  means this host lacks the public key). Each COPR project gets its own key.
- **The GitHub webhook**: `copr-cli` cannot create it. `POST
  /api_3/webhook/generate/{owner}/{project}` returns `{id, webhook_secret}`;
  build the URL yourself (`/webhooks/github/<id>/<secret>/<pkgname>/`) and
  register it on the PACKAGING repo (`gh api repos/<o>/<r>/hooks --method POST
  -f config[url]=… -f config[content_type]=json -f events[]=create -f
  events[]=push -F active=true`). A `last_response.code == 200` on the first ping
  is the proof it points somewhere real.

## SCM package and build

- The SCM `spec` is a path relative to the repo root (`rpm/<app>.spec`).
- Trigger and poll `GET /api_3/build/<id>`; a fresh SCM build runs about 6–7
  minutes (`importing → starting → running → succeeded`).
- The spec's `Source0` must be the tag archive:
  `%{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz`; it unpacks to
  `<name>-<version>/`. Pin its sha256 in a `.sources` file AFTER the tag exists —
  that is a separate commit because the hash cannot be taken before the tag.

## Releasing: fetch first, and know what a pushed tag commits you to

The tag-archive ritual (`Version:` bump → commit → `git tag` → `bin/spec-sources`
→ commit the hash) has two failure modes that cost a round trip:

- **A local checkout is not the remote.** This repo's README gets edited through
  the GitHub web UI, so `git push origin main` silently becomes a rejected
  non-fast-forward (`hint: … use 'git pull' before pushing again`) and, worse, the
  `git push origin v<ver>` in the same scripted block still SUCCEEDS — you have
  published a tag pointing at a commit that is not on `main`, while COPR's SCM
  package builds the SPEC from `committish: main`. COPR builds from `main` with
  the OLD `Version:` and `Source0` hash then just rebuild the previous release, so
  nothing is damaged but nothing is released either. Always `git fetch origin` and
  compare `git rev-parse HEAD` against `origin/main` BEFORE the tag line, and read
  each push's output instead of the block's exit status.
- **A tag pushed before it was consumed can be moved.** If the tag points at an
  unpushed commit and no build has used it yet, `git rebase origin/main`,
  `git tag -d v<ver>`, re-tag, then `git push --force origin v<ver>` — cheaper and
  cleaner than burning a version number. Say so in the report; it is a forced ref
  update even when harmless.
- Build order that never fails the source-hash check: spec version + `.sources`
  hash both on `main` before any build imports the tree. A build that imports
  between the two commits fails on the hash, which is noise, not a real failure.

## RPM URL: read the repo metadata, never guess the path

- **`dnf5 repoquery` prints every matching package with NO separator between them**, so
  `--qf '%{name} …'` over `hyprglaze*` returns one run-together blob
  (`hyprglaze-…rpmhyprglaze-debuginfo-…rpm`). Neither `--qf '…\n'` nor a greedy
  `grep -oE 'name-[0-9][^ ]*\.rpm'` fixes it (the greedy pattern swallows the next
  filename). Split first, then match: `sed 's/\.rpm/.rpm\n/g' | grep -E '^<name>-[0-9].*\.rpm$'`.
- **Downloads 301-redirect off `download.copr.fedorainfracloud.org`** to
  `packages.redhat.com/api/pulp-content/public-copr/…` and then to an S3 signed URL on
  the Pulp backend (`storage: pulp`). `curl` needs `-L`; a `curl -I` that shows 301 is a
  file that EXISTS, not a broken URL.
- `.../fedora-<ver>-x86_64/<name>-<ver>-<rel>.rpm` answers 500. The RPM lives under
  `Packages/<first-letter>/`; get the exact href from `repodata/repomd.xml` →
  `primary.xml.gz` → `<location href="Packages/…">`. Follow redirects (`curl -L`).
- **The results directory is neither a repo nor a scrapeable index.** Under
  `copr-be.cloud.fedoraproject.org/results/<owner>/<project>/<chroot>/` the RPMs sit in
  `Packages/<first-letter>/`, and the sibling entries are **per-build directories**
  (`<build_id>-<package>/`) holding logs, the spec and a `success` marker — never an
  `.rpm`. That index is also served with **single-quoted** `href='…'` attributes, so a
  `href="…"` scrape matches nothing and reads exactly like "the package was never built".
  Resolve the URL from repo metadata (`dnf5 repoquery … %{location}`) or ask the API what a
  build produced (`GET /api_3/build/built-packages/{id}`); keep HTML scraping out of the
  loop. Note `GET /api_3/build/{id}` returns just the chroot **names**, and
  `api_3/build/list?build_id=` answers 400 — the id is a path segment, not a query arg.
- **Read the NEVRA to prove WHICH commit built the RPM.** The payload specs embed the git
  commit in the release (`…-1.202611181026gitd0068c9.fc45`), so after a push, matching that
  hash to HEAD is real proof the artifact came from your commit — far stronger than the
  newest build showing green, and it is the same string `rpm -q <pkg>` prints on a host, so
  it tells you which payload change a machine is actually running.

Verify the artifact rather than trusting the build's "succeeded":
`rpm -qip` shows `Release: …fc45`, the license, and the COPR signature
(`RSA/SHA256 … Key ID <key>`); `rpm -qlp` lists the payload.

## GitHub webhook

- **A configured webhook makes `copr-cli build-package` redundant.** The read-only
  `webhook_rebuild` field on the SCM package stays `null` even when a GitHub-side
  webhook exists and fires, so never conclude "tag pushes won't build" from the
  API: pushing a tag to the app repo created builds 11322609/11322613 on its own,
  and a `push` to `main` created another (11322614). Expect a solo build per push
  and read the build list before blaming a build for a broken release.
- URL: `https://copr.fedorainfracloud.org/webhooks/github/<project-id>/<uuid>/<pkgname>/`
- The trailing `<pkgname>` is required when the tag does not carry the package
  name (`v0.1.0`, not `airgraph-0.1.0`). Subscribe to `create` and `push`.
- `gh api repos/<owner>/<repo>/hooks --method POST -f "config[url]=…" -f "config[content_type]=json" -f "events[]=create" -f "events[]=push" -F "active=true"`.
  The first delivery is a ping; `last_response.code == 200` proves the URL.

## Verify the spec in a throwaway container first

Build from the real tag tarball in a Fedora container, not in the host's dnf:

```bash
podman run --rm -v "$PWD":/src:ro -v "$SCRATCH:/rpmbuild" --security-opt label=disable \
  registry.fedoraproject.org/fedora:45 bash -c '
    set -e
    dnf5 install -y rpm-build rpmdevtools desktop-file-utils gcc-c++ make \
        qt6-qtbase-devel qt6-qtdeclarative-devel
    mkdir -p /rpmbuild/SPECS /rpmbuild/SOURCES
    cp /src/rpm/<app>.spec /rpmbuild/SPECS/
    curl -sL "https://github.com/<owner>/<app>/archive/refs/tags/v<ver>/<app>-<ver>.tar.gz" \
        -o /rpmbuild/SOURCES/<app>-<ver>.tar.gz
    rpmbuild -bb --define "_topdir /rpmbuild" /rpmbuild/SPECS/<app>.spec'
```

- `mkdir -p` BOTH `SPECS` and `SOURCES`; copying into a missing `SPECS` fails with
  `cp: cannot create regular file '/rpmbuild/SPECS/': Not a directory`.
- `%check` runs `desktop-file-validate` plus `QT_QPA_PLATFORM=offscreen ./bin/test`,
  so the suite must run with no display, no D-Bus and no scanning. A release that
  fails its own tests must not publish.
- A Qt app's spec needs `%global debug_package %{nil}` (qmake release builds no
  debug info, and an empty debuginfo subpackage fails the build) and
  BuildRequires `qt6-qtbase-devel` + `qt6-qtdeclarative-devel` — Qt Quick Controls
  and the Material style live inside `qt6-qtdeclarative` on Fedora 44/45; there is
  no `qt6-qtquickcontrols2` package any more.

## Do not install the RPM on the host

The COPR is the delivery path and the host is immutable. Verify the artifact and
repo metadata, then hand over the `dnf copr enable <owner>/<app>` line. Installing
there layers a package on a bootc image.

## Image integration (the user's side)

In `build_files/build.sh` there are TWO seams; pick by whether the repo should
stay enabled on the host:

- **Bulk list:** the app name in `EXTRA_PACKAGES` (installed in one
  `install_packages "${PACKAGES[@]}" "${EXTRA_PACKAGES[@]}"` at ~line 230) plus
  `dnf5 -y copr enable <owner>/<app>` next to the other COPRs. Right for a
  package whose repo the host should keep consuming (that is why the Omedora
  COPR is deliberately left enabled).
- **Self-contained block:** for a baked-in app nothing updates from at runtime,
  install it in its own group and turn the repo off again (airgraph, 2026-11):
  ```bash
  dnf5 -y copr enable <owner>/<app>
  dnf5 install -y <app>
  dnf5 -y copr disable <owner>/<app>
  echo "<app> installed: $(rpm -q --qf '%{name}-%{version}-%{release}' <app>)"
  ```
  Leave the install UNGUARDED (no `|| echo warning`): a scheduled image build
  that silently ships without the app is worse than a loud failure.
- **Inserting a block means closing the block you landed in.** Anchoring the insert on
  the previous block's own `echo "::endgroup::"` puts your group INSIDE that block and
  lets its closer terminate yours — the earlier group is then never closed, and a fuzzy
  patch review reads as fine. Emit a closing `::endgroup::` for the block above as well,
  then verify by COUNTING rather than reading the diff: in the same file,
  `grep -c 'echo "::group::'` must equal `grep -c 'echo "::endgroup::"'`.

Never in `omarchy-base.packages` — that file is synced from the fork and would
revert the addition.

- **`dnf5 copr disable` leaves the repo file behind with `enabled=0`** (it does
  not delete it — that is `copr remove`). Expected, not a leak: reading the file
  in a built image shows `enabled=0` for the app repos and `enabled=1` only for
  the repos the host is meant to consume (omedora-4, ublue akmods, brave).
- **Prove it in the published image, not in the build log**: `podman pull` the
  GHCR image and, inside it, `rpm -q <app>`, `rpm -q --qf '%{rsaheader:pgpsig}'`
  (the COPR key ID), `<app> version`, `ls -l` the unit + any
  `/etc/systemd/user/graphical-session.target.wants/` symlink, the payload files
  and their `sha256sum`, `/etc/skel` seeding, and `grep enabled= /etc/yum.repos.d/*`.
- **A `command -v <app>` inside such an image may print `/usr/sbin/<app>` while
  the RPM says `/usr/bin/<app>`** — `/usr/sbin` is a symlink to `bin` on
  Fedora 45's userland merge, so the PATH lookup resolves through it. Check
  `rpm -ql`, not `command -v`, before suspecting the spec.

## Prove availability BEFORE the build, not from the build's exit code

Query the COPR repo directly, without touching `/etc/yum.repos.d` on the
immutable host:

```bash
dnf5 --setopt=cachedir="$SCRATCH/dnfcache" \
  --repofrompath=<name>,https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-45-x86_64/ \
  --repo=<name> repoquery --available --latest-limit=1 \
  --qf '%{name} %{evr} %{location}\n' <app>
```

`--latest-limit=1` matters: COPR repodata lists EVERY retained build, so a plain
query buries the current one under old versions (a hand-rolled regex over
`primary.xml` is worse — it printed a dozen stale NEVRAs and matched the wrong
one). Then verify the payload by extracting the shipped file from the RPM
(`rpm2cpio <pkg>.rpm | cpio -i --to-stdout --quiet ./usr/bin/<app>`), or the
checker script in the omedora case, and `diff` it against the committed source —
for the omedora payload that is how you prove a fix actually reached the RPM the
image consumes, rather than trusting the green COPR build.
- **A member that is a SYMLINK extracts to nothing**, so a path that IS in the RPM
  reads as `MISSING: <path> is not in <pkg>`: `cpio --to-stdout` has no data for a
  link member. The omedora payload mirrors omarchy's layout (real files in
  `/usr/bin`, `/usr/share/omarchy/bin/*` as symlinks into them — check with
  `rpm -qlvp`), so probe the real file or let
  `scripts/copr-verify-payload.sh` follow one link level (it now does). Two shell
  traps live in that fallback: never `exit` inside an `awk` reading an `rpm -qp`
  dump (`SIGPIPE` + `set -o pipefail` = a 141 failure of the whole substitution),
  and never pipe the probe into `head`/`tail`.

## After the image CI goes green: verify the PUBLISHED image

A green image build only proves the steps ran. Pull the artifact and look inside
it — that is how you catch an app COPR left enabled, a payload file that never
landed, or a unit shipped without its enablement:

```bash
podman pull -q ghcr.io/wegweg7979/hurunagus-hyprland:latest
podman run --rm --entrypoint bash ghcr.io/wegweg7979/hurunagus-hyprland:latest -c '
  rpm -q <app>; command -v <binary> && <binary> version
  ls -l /usr/lib/systemd/user/<unit>.service
  ls -l /etc/systemd/user/graphical-session.target.wants/<unit>.service
  ls /usr/share/hurunagus/config/.config/omarchy/plugins/
  grep -c "<plugin-id>" /usr/share/hurunagus/config/.config/omarchy/shell.json
  ls /etc/skel/.config/omarchy/plugins/
  ls /etc/yum.repos.d/ | grep -i "<app>" || echo "(app COPR left disabled: correct)"'
```

- **`--entrypoint bash` is required**: a bootc image's default command is systemd.
- Check the payload in `/usr/share/hurunagus/config` **and** in `/etc/skel` — a
  fresh install gets the skel copy, an existing box only after a payload replay.
- The app COPR must NOT be in `/etc/yum.repos.d`: the install block disables it
  again, and a leftover would put that third-party repo on every user's host.
- A green `gh run watch` exit can still be the wrong run: pushing twice within one
  build makes the workflow's concurrency group CANCEL the first
  (`Canceling since a higher priority waiting request …`). Read `gh run list` and
  confirm the sha you care about, rather than the newest run's exit code.

### Traps hit while verifying the install in a container

- `dnf5 --repofrompath=x,URL --repo=x` enables **only** x, so a package with a
  real dependency (`Requires: gnome-keyring`) fails with `nothing provides …`.
  Use the repo file the image itself uses — it also imports the GPG key:
  `curl -sSL -o /etc/yum.repos.d/<app>.repo https://copr.fedorainfracloud.org/coprs/<owner>/<project>/repo/fedora-45/<project>-fedora-45.repo`
  (without that key the install ends in `Signature verification failed`).
- Bind-mounting a **symlink** into the container fails
  (`statfs …: no such file or directory`); pass the target file or recreate the
  link with `ln -s` inside.
- A `podman run` whose stdout is piped into `head`/`tail` can die on SIGPIPE and
  look as if it produced no output at all, and a multi-line `bash -c '…'` payload
  loses its newlines easily. Write the check to a file, mount it, redirect the
  output to a file on a mounted dir, then read that file.
