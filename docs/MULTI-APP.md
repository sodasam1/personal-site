# Several apps, one server, one login

Status: **merged to `main`; the login service and Riffbox are deployed (2026-11-19), music-share is being installed, Version Control is not installed yet.** Written so it can be read cold.
Principles are Tech Independence's: your data as plain files and SQLite; base tools first; few, slow-changing dependencies (Flask,
waitress, ffmpeg) at app level only; no bespoke code where something mature exists; upload with FreeFileSync, the server never fetches.

## Apps and where they live
| App | URL | Port | Unix user | Repo |
|---|---|---|---|---|
| Static site, `/pub/` | `/` | httpd 8080 | www | personal-site `htdocs/` |
| Site login + private pages | `/login`, `/private/*` | 8099 | `_sitelogin` | personal-site `login/` |
| riffbox | `/ideas` | 8100 | `_riffbox` | riffbox |
| music-share | `/music` | 8101 | `_musicshare` | music-share |
| Version Control | `/version-control` | 8102 | `_versioncontrol` | version-control |

## The parameterized installer
*Problem:* riffbox's installer has its names typed into the script; a second app would mean copy-and-rename with silent failure modes
(stripping another app's relayd block, port clashes, fixes that must be repeated in every copy). *Method:* one generic script
(`kit/appkit/appkit.sh`, POSIX sh) plus a ~15-line `deploy/app.manifest` per app. "Parameterized" = the values that differ are supplied
from outside instead of written inside. Reference: `kit/appkit/README.md`. It adds no package or tool beyond sh, sed, awk, rsync (already
installed by Tech Independence) and `pkg_add` for the same packages as before. It is still code we maintain: no existing tool does
"patch a validated block into relayd.conf, show the diff, ask, keep a backup" (Ansible and ports add far more machinery; httpd/relayd have
no drop-in directory inside a block). It is vendored into each app so each upload folder is self-contained.

## Login (approach C): one central login, one key per app
- You sign in once at `/login`. The login service checks your passphrase against the one stored hash (throttled), then sets **one cookie per
  app, each signed with that app's own key and scoped to that app's path**. Each app verifies only its own cookie with `kit/siteauth`.
- Keys: `/etc/site-auth/` holds `master` (login service only), `generation`, `apps.conf`, `passphrase.hash` (login service only) and
  `keys/<app>.key` = HMAC-SHA256(master, `app|generation`), readable only by that app. A break-in to one app cannot forge another's login.
- **Who gets in:** with the passphrase you reach every private app and page; without it every owner-only route answers 401 (or sends a
  browser to `/login`); there are no other accounts. Public pages and share links never check the cookie. A link proves access to that one
  item only. Fail-closed: a route with no `@public`/`@owner`/`@token` declaration is owner-only, and each app's tests fail if any is undeclared.
- **The two older systems:** httpd Basic auth on `/private/*` is replaced because relayd now sends `/private` to the login service, which
  serves the same files behind the cookie (one hash instead of two, throttled). The httpd block can be removed later with
  `doas sh ~/staging/server/install.sh --remove` (kept until you say). The riffbox phone-upload bearer token is unchanged.
- **How strict the wrong-passphrase limit is:** by default 5 wrong tries per client in 15 minutes, then that client waits. Relax it in `/etc/sitelogin.conf` with `SITELOGIN_MAX_FAILS=15` and
  `SITELOGIN_WINDOW_MINUTES=5` (whole numbers; a typo stops the service at start-up), then `doas rcctl restart sitelogin`. The spread-out-attack slow lane never locks anyone out. Riffbox has its own pair (`RIFFBOX_LOGIN_MAX_FAILS`, `RIFFBOX_LOGIN_WINDOW_MINUTES`) for its local passphrase.
- **Lifetimes:** 30 days from sign-in, 7 days idle; use refreshes the idle clock hourly. `Secure`, `HttpOnly`, `SameSite=Lax`.
- **Log everyone out of everything:** `doas python3 /usr/local/login/app/siteauth/keys.py rotate --dir /etc/site-auth` (bumps the
  generation; apps re-read their key file on change, no restart).
- **Change the passphrase:** `doas python3 /usr/local/login/app/siteauth/admin.py set-passphrase --dir /etc/site-auth` (15+ characters).
- **Add an app:** write its `deploy/app.manifest` with `SITE_AUTH=1`, vendor `appkit` and `siteauth`, run its installer. It registers itself.
- Deliberate costs: one more small service; cookies for sibling paths are set from `/login` (RFC 6265 allows it; confirm in the gate);
  path-scoped cookies do not isolate apps against script injection on the same origin, so apps send a strict CSP and render user text as text only.

## Install order on a server
1. Tech Independence, then `server/install.sh` (existing, the httpd `/private/` rule).
2. `~/staging/login`: `doas sh ~/staging/login/deploy/install.sh --check`, then without `--check` (asks your passphrase once). Then `sh tools/gate-test-login.sh DOMAIN` from your computer.
3. Each app's installer, same pattern. Apps with `SITE_AUTH=1` need step 2 first (they hold back and say so otherwise).

## Verification
`VENV_PY=... sh tools/test-kit.sh` (offline). On the server only `--check` runs and the gate scripts. Unverified by me (no OpenBSD here):
`useradd`/`rcctl`/`relayd -n`, group file access, sibling-path cookies in every browser, `python3` hashing speed on the 1 vCPU box.

All planned work, with priorities, for every app and the server: `docs/TODO.md`.

## Where each app's data lives
**Program files and settings on the boot disk; all data on one plain data volume**, so a wiped server is rebuilt by reinstalling the programs and pointing them at the kept data.
| App | Program files | Data, backups, restore folder |
|---|---|---|
| riffbox | `/usr/local/riffbox` | `/mnt/data/apps/riffbox/{data,backup,restore}` |
| music-share | `/usr/local/music-share` | `/mnt/data/apps/music-share/{data,backup,restore}` |
| Version Control | `/usr/local/version-control` | `/mnt/data/apps/version-control/{data,backup,restore}` (backups hard-link audio: data and backup stay on the same filesystem) |
| `/pub/` | n/a | the volume's first partition, mounted at `/var/www/htdocs/pub` |
| Site login | `/usr/local/login`; state in `/etc/site-auth` (boot disk, secrets) | none |
Each app's manifest sets `DATA_ROOT=/mnt/data` and `REQUIRE_MOUNT=$DATA_ROOT`: the installer refuses to run, and the service script (`rc_pre`) refuses to start, unless the volume is mounted and holds
`/mnt/data/.volume-ok`. On a rebuild the installer gives the service user the uid of the existing data folder. An app may override `DATA_ROOT` (a second volume). Procedure, expansion and the
rebuild order: `docs/STORAGE.md` and `RESTORE.html` section B3. Each app's backups are still pulled to your computer with FreeFileSync; a backup on the same volume does not protect against losing it.
