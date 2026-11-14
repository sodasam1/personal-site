# Plan v5: smaller server footprint, standard parts only, conventional password gate

## 0. Answers first

**Was the gate in v4 standard practice? Half of it, so I changed it.**
- *Static private pages behind httpd Basic auth over TLS*: yes, a long-established pattern for a small private area.
  Known weaknesses (from the sources in the list at the end): no real logout (the browser keeps the credentials until it is
  closed), the password travels with every request, the server re-checks it every time, and there is no session management.
  Acceptable for a few read-only pages with a long random passphrase.
- *Riffbox's API reading httpd's `htpasswd` file itself with `py3-bcrypt` and `Flask-HTTPAuth`*: **no, that is not how it is
  usually done.** It was a workaround for relayd having no authentication. Practitioners do one of two things: the app has
  its own login (login form, hashed password, session cookie), or a proxy in front does the login for many apps ("forward
  auth", e.g. Authelia), which needs a proxy that supports it and adds server-level software. The first is the standard fit
  here, and Riffbox already has it. Two services sharing one credential file is unusual and adds permission and
  dependency problems. Dropped.
- Industry guidance I found (secondary sources, since the OWASP cheat sheets themselves came back only in part): session
  cookies should be `HttpOnly`, `Secure` and `SameSite`; passwords should be stored only as slow salted hashes (Argon2id
  preferred, then scrypt, with bcrypt as the legacy option); login attempts should be limited. Riffbox already sets
  the cookie flags and limits attempts (`throttle.py`). **Its one real gap: the passphrase is stored in plain text in
  `/etc/riffbox.conf` and compared directly.** That is the fix in this plan.

**The cron reload and the "app host" from v3** (you asked what they meant): cron is OpenBSD's built-in scheduler; I had a
job that restarted Riffbox when its files changed. The app host was one process serving several apps. Neither is standard
(normal practice: one service per app, restart explicitly after a deploy). Both are gone.

**Dependencies.** Server level (the whole server): exactly TI's set, **nothing added**. Riffbox level: Flask, waitress, ffmpeg
(section 2). v4's `py3-bcrypt` and `Flask-HTTPAuth` are dropped, so the gate adds **no** dependency anywhere.

**Terms (fixed):** **Server rebuild** = wipe, follow TI, upload the kit, run the install script; result: the site and an
empty Riffbox work. **Riffbox data restore** = putting your recordings, tags and notes back, from inside the app (section 6).
**The kit** = the one folder (git repo `personal-site`) holding everything that must exist on your computer to recreate the
site on a fresh TI server (section 4 defines and justifies each part).

**Your other instructions, applied:** no forks of `ti.sh` or any dependency; nothing on the server fetches from GitHub (files
arrive only by your uploads); ffmpeg is part of the main install as a Riffbox dependency.

**One change for your approval:** with the standard design, private *apps* gate themselves, so Riffbox **stays at `/ideas/`**
(the Shortcut URL and bookmarks do not change at all). The `/private/` folder becomes the rule for static pages only.
This revises your earlier `/private/` choice, which I had assumed covered apps.

**Your four newest questions, short answers (detail in section 7):**
1. **iPhone Shortcut: yes, compatible, and unchanged.** The Shortcut authenticates with the `Authorization: Bearer <token>` header on
   `/ideas/api/upload`, never with a login or a cookie. v5 does not touch that path: the route stays outside `/private/` (so httpd never
   asks it for a password), relayd still routes it, and the app still accepts "valid token OR logged-in session". The login style
   (form + cookie) only matters to browsers. One real risk I found: the token lives in `/etc/riffbox.conf`, which a server rebuild
   would regenerate, silently breaking the phone. Fix: the install script asks you to paste your existing token (kept in your password
   manager) and only generates a new one if you press Enter (section 8, step 7). Each stage's gate re-runs `deploy/SHORTCUT.md` section 6.
2. **Existing vs bespoke for passwords, cookies, attempt limits:** hashing and signed cookies are already existing code (Werkzeug and
   Flask's session, both inside Flask). Attempt limiting is the one small bespoke piece (`throttle.py`, 55 lines, already written and
   tested, in memory, at app level). Ready-made packages exist (Flask-Login, Flask-Limiter, Flask-Security-Too) but each adds a
   dependency for work Riffbox already does in a few dozen lines. Recommendation: keep it bespoke and tiny, at app level, nothing at
   server level depends on it.
3. **Static private pages AND app login: different purposes, same passphrase.** Static private pages are plain files (notes, documents,
   scratch HTML) that need no server code, so the web server guards them. Apps (Riffbox) have data behind an API, so the app guards
   its own data. You do not need both for the same thing.
4. **Scaling path:** documented in section 7 and in a `docs/AUTH.md` deliverable. In short: now, one auth module per app plus httpd for
   static pages; next, a shared login module with one cookie across your apps (still no server-level dependency); only if you need
   several users, MFA or passkeys, a forward-auth proxy (a server-level change that needs your approval).

## 1. Tech Independence tests (each step is tagged)

Your TI page: the point is "not depending on any particular company or software", using "the common open source basics
built into any Linux or BSD operating system", so you can "set up a new server anywhere else in an hour".
**[TI-1]** standard parts; **[TI-2]** no bespoke replacements for stable software; **[TI-3]** you can follow it, every command
explained; **[TI-4]** rebuildable in an hour from your computer and the server alone; **[TI-5]** you own the data (plain files, SQLite).

## 2. Dependencies, by who needs them

**Server level:** OpenBSD base (httpd, relayd, acme-client, pf, cron, rc.d, `htpasswd`, `doas`) plus TI's `pkg_add` list (curl,
rsync, Radicale, links, mutt, dovecot). Python 3 is already there because Radicale needs it (`PHASES.md` Phase 0: 3.13.16).
**This plan adds nothing to this list.** [TI-1]

**Riffbox level** (installed with `pkg_add`, which is system-wide, but they belong to Riffbox and its uninstall removes them):

| Dependency | What it does for Riffbox | Why not removed |
|---|---|---|
| `py3-flask` (with Werkzeug) | web framework: 35 routes, JSON, file uploads, audio `Range` streaming, and the password-hash helpers used in section 7 | Measured in `app/riffbox/__init__.py` (1011 lines). Uploads need `request.files`; Python removed the `cgi` module in 3.13, so a stdlib version means writing a multipart parser, plus `Range`/ETag handling: a bespoke, worse copy of stable code. Trade-off: the package version can jump on `sysupgrade`; the 255 tests are the guard. |
| `py3-waitress` | listens on a port and runs Flask in production | Flask's built-in server is for development only. |
| `ffmpeg` | waveforms, lengths, FLAC copies of Apple Lossless so Chrome can play them | Core feature, so in the main install. The app already calls it as a plain subprocess. |

## 3. What happens to each install step

| Today | New | Why |
|---|---|---|
| install Python | gone | Already present via Radicale. |
| `pkg_add py3-flask py3-waitress`, `ffmpeg` | one `pkg_add` line in the install script | same tool TI uses |
| service user `_riffbox`, data folder | stay | an unprivileged user: your login user has `permit nopass` in `doas.conf` (from `ti.sh`), so an app bug running as that user would be root |
| `/etc/riffbox.conf` | stays, safer | holds the session secret, the passphrase **hash** (not the plain passphrase), and the upload token; mode 640 root:`_riffbox` |
| rc.d script, `rcctl enable` | stay | the standard way to run a service on OpenBSD |
| hand-edit of `relayd.conf` | stays, done as a marked block by the script | relayd is how this stack reaches a Python port; httpd cannot proxy |
| `install-riffbox.sh`, staging folder, `deploy.sh/.ps1` | **gone** | upload straight into place; code deploy = upload + `doas rcctl restart riffbox` |
| ffmpeg runbook (PHASE3_5) | folded in | core feature |
| backup cron line and folder | stay | existing `backup.py` nightly into a folder your login user can read |
| server-level restore drill | **gone** | Riffbox data restore is in-app (section 6) |

**What cannot be removed:** the service user, rc.d script, relayd block, backup cron line and `pkg_add`s live in root-owned
files, so an upload cannot create them. They go into one plain, linear script, `server/install.sh`, in the style of
`ti.sh` (safe to run twice, says what it is doing). You run it once per server rebuild. [TI-3, TI-4]

## 4. The kit: what is in it and why

```
personal-site/                     <- the kit (git repo; the folder you re-upload)
  htdocs/                          public pages and /pub/, as TI describes -> /var/www/htdocs
    private/                       static pages here are behind the password (section 7)
    ideas/                         Riffbox's page files (HTML, JS, CSS), served by httpd
  server/                          -> your home folder on the server
    install.sh                     the once-per-server-rebuild script (section 8)
    templates/                     small files install.sh copies into place: rc.d script, relayd block, httpd block
    apps/riffbox/                  Riffbox's Python code (a copy of riffbox/app, without tests)
  tools/gate-test.sh               checks from outside that private things really are private
  RESTORE.html                     your offline server-rebuild page, in TI's style
  reference/ti.sh, ti.tar, SHA256  your one-time copy of Tech Independence as it was when this site was built
  docs/                            PLAN.md, PHASES.md, AUTH.md (how login works, how to add it to an app, how to scale it), Stage 0 notes
  (not in the kit: password, hash, token, recordings, database, backups)
```

- **`htdocs/`**: what you already do. [TI-4]
- **`install.sh` and `templates/`**: root-owned wiring cannot be uploaded, so it must be run; one short script means "what did the
  kit change on my server?" has one readable answer. Templates are separate files so each is readable. [TI-3]
- **`apps/riffbox/`**: the app code lives in the kit so a rebuild needs only your computer and the server, never GitHub. You update
  it by copying the folder from your riffbox checkout. [TI-1, TI-4]
- **`gate-test.sh`**: only a test you run proves a stranger cannot reach a private page.
- **`RESTORE.html`**: a disaster page should sit on your disk like the TI page you attached.
- **`reference/ti.sh` and `ti.tar`**: **not a fork.** A frozen copy so you can see what TI set up and `diff` whether live TI changed. I will
  read `ti.tar` (it holds `httpd.conf`, `relayd.conf`, `pf.conf`) to write exact insertion blocks. **Please provide it and `ti.sh`**;
  that replaces most of Stage 0. `ti.sh` still fetches `ti.tar` from `sive.rs` when run, so this documents that dependency, not removes it.
- **Not in the kit:** secrets (not for a public repo) and data (must never be overwritten by a code upload). [TI-5]

## 5. Resulting flows

- **Server rebuild:** (1) Tech Independence. (2) Upload the kit: `htdocs/` to `/var/www/htdocs`, `server/` to your home folder.
  (3) `doas sh ~/server/install.sh`, once. Riffbox runs, empty. Riffbox data restore is separate and afterwards (section 6).
- **Edit a page:** upload, no command. **Change Riffbox code:** upload, then `doas rcctl restart riffbox` (stops and restarts the
  service so it loads the new files; the standard step).
- **Backup:** nightly `backup.py` into `/var/riffbox-backup`; your **Pull** sync copies it to your computer. A backup on the same
  VPS does not survive losing the VPS, so the pull is what protects the data. [TI-5]

## 6. Riffbox data restore (in the app; branch `restore-in-app`)

Separate from server rebuild: it concerns only the audio and notes inside Riffbox. Existing: `restorer.py` restores from an
*export bundle* with checksum checks; `backup.py` writes a different layout (`db/riffbox-*.db` plus `audio/`). New: a **Restore**
section on the Backup and export page that reads a folder you upload to `~/restore/` with your usual sync tool, accepts either
layout, reuses the existing checks, and refuses if the library already has recordings. Why a server folder and not a browser
upload: the library may be GBs and the app caps one upload at 300 MB (`MAX_CONTENT_LENGTH`). Tests extend `test_restore.py`.

## 7. The password gate

**Rule:** one passphrase, and two conventional mechanisms, each the normal one for its kind of thing. [TI-1, TI-2]

| Thing | Mechanism | Why it is the standard choice |
|---|---|---|
| Static private page (anything under `htdocs/private/`) | `httpd` `authenticate` on `location "/private/*"`, bcrypt hash from the base `htpasswd` tool | The web server protects its own files; the file path is relative to httpd's chroot and readable by `www` (confirmed in search results). No code of mine. |
| An app (Riffbox) | the app's own login: form, hashed passphrase, signed session cookie (`HttpOnly`, `Secure`, `SameSite=Lax`), attempt limit (`throttle.py`) | The normal pattern for a web app. Already built and tested. relayd has no authentication of its own, so the app must do it. |
| Public | nothing | |

Changes to Riffbox: store only a salted **hash**, using Werkzeug's `generate_password_hash` / `check_password_hash` (part of Flask,
so no new dependency; scrypt by default in current Werkzeug, which the sources rank as acceptable after Argon2id). Stage 1 confirms
its parameters against the current OWASP sheet and raises them if the server can afford it (low volume, so it can). The config key
`RIFFBOX_PASSPHRASE` becomes `RIFFBOX_PASSPHRASE_HASH`. About five lines change in `login()` and one test file.
**One passphrase for both:** `install.sh` (or `install.sh --passwd` later) asks for it once, or generates 20+ random characters
and shows it once (about 100 bits), then writes the httpd hash (via `htpasswd`) and the Riffbox hash (via Python) from it.
**Add-only token:** unchanged, as you decided: upload accepts a Bearer token or a logged-in session. URL unchanged.
**CSRF:** the existing `SameSite=Lax` cookie is the standard defence; the extra header check from v4 is no longer needed.

### 7.1 Why the Shortcut is unaffected, and what does touch it
- Today and in v5 the Shortcut sends `POST /ideas/api/upload` with header `Authorization: Bearer <token>` (see `deploy/SHORTCUT.md`
  sections 1 and 3, confirmed working on your phone). Shortcuts passes credentials as explicit headers on each call; reports in the
  Shortcuts community do the same for token APIs (search results listed below). A cookie login would not suit it, which is exactly why the
  add-only token exists and stays.
- Route rule: `/ideas/*` is never under the httpd `authenticate` rule (that rule covers only `/private/*`), so a Bearer request is never
  asked for a Basic password. `gate-test.sh` includes this case.
- Rebuild risk: the token must survive a server rebuild or the Shortcut breaks. Handled in section 8 step 7.
- Unverified: nothing in the Shortcut's request changes, so I expect no change, but I cannot run Shortcuts. Each stage's owner gate repeats
  `SHORTCUT.md` section 6 (upload a memo, upload it again to see the duplicate message, wrong token refused).

### 7.2 Existing packages versus a small bespoke module (app level only)
| Job | Existing package | What it covers | Verdict for Riffbox |
|---|---|---|---|
| Salted password hash | Werkzeug (inside Flask) | `generate_password_hash`, `check_password_hash` | **use**; not bespoke, nothing new |
| Signed session cookie with flags | Flask's built-in session (itsdangerous, inside Flask) | signing; `HttpOnly`, `Secure`, `SameSite` settings | **use**; already configured |
| Session handling (current user, login required) | Flask-Login | sessions only; leaves hashing to you | not worth a dependency for one user |
| Attempt limits | Flask-Limiter | per-route rate limits | `throttle.py` already does it in 55 lines with a fake-clock test; keep |
| Everything (registration, reset, roles, MFA) | Flask-Security-Too | built on Flask-Login and passlib | far more than one passphrase needs |
All of these are Riffbox dependencies at most, never server dependencies. Principle I will follow: use what Flask already
contains; write the glue myself only where it is shorter than the package's own configuration. Keeping it bespoke is the lower-dependency
choice here, and it stays contained in one file (7.4).

### 7.3 Static private pages versus app login: what each is for
| | Static private page | App login (Riffbox) |
|---|---|---|
| What it protects | plain files: notes, documents, scratch HTML under `htdocs/private/` | an app's API and data: recordings, tags, notes, export |
| Who enforces | httpd (`authenticate`) | the app itself |
| Needs code | none | yes (small, section 7.4) |
| Prompt | browser's Basic-auth box | Riffbox's login form (works with Shortcut token for uploads) |
| Used together? | No: a given thing is guarded by exactly one of them. The same passphrase opens both, set once by `install.sh` |
Riffbox's own page files (HTML/JS/CSS) are public and contain no data; every data route demands a session or the token, as today.

### 7.4 Making per-app auth easy to migrate later (done in Stage 4, documented in `docs/AUTH.md`)
- **One seam:** move all of Riffbox's auth (`login`, `logout`, `session`, `require_auth`, `token_ok`, the throttle hook) out of the
  1011-line `__init__.py` into one file, `app/riffbox/auth.py`, with a tiny interface: `is_authenticated(request)`,
  `login(passphrase)`, `require_auth(allow_token)`. Nothing else in the app knows how auth works, so replacing it is one file.
- **Portable hash:** the stored hash is Werkzeug's self-describing string (`scrypt:...`), so any later system can verify it without conversion.
- **Escalation path, with triggers:**
  1. *Now (1 or 2 apps):* per-app `auth.py` + httpd for static pages.
  2. *Third app, or tired of logging in separately:* a **shared login module**: one small file in the kit, one login page, one signed cookie
     scoped to `/`, verified by each Flask app with the same secret. Still no server-level dependency. `docs/AUTH.md` lists the exact steps:
     copy the module, set the shared secret, replace each app's `auth.py` body with a call into it.
  3. *Several users, MFA or passkeys:* a forward-auth proxy (Authelia-style). relayd cannot do forward auth, so this needs a server-level
     change (a new front proxy or service); it requires your explicit approval, and `docs/AUTH.md` records what would change and what
     would be lost.
  The shipped `docs/AUTH.md` also has a "how to give a new app a login" recipe (copy `auth.py`, set two config values, add a gate-test line).

Honest costs and residuals:
- Two mechanisms to understand. Each future *app* must have its own login; Riffbox's login code is small and copyable, but it is a
  recurring cost per app. If apps multiply, revisit a forward-auth proxy (Authelia-style); it needs a proxy that supports it, so
  it would be a server-level change needing your approval.
- httpd has no login throttle, so the static private area relies on the long random passphrase.
- Basic auth has no logout and prompts per browser session; acceptable for a handful of reading pages.

**Is there existing code for what I called bespoke?**

| Function | Existing software | Verdict |
|---|---|---|
| password hashing for Riffbox | Werkzeug (already installed with Flask); OWASP ranks Argon2id, scrypt, bcrypt | use Werkzeug; nothing new |
| static page protection | httpd `authenticate`, `htpasswd` (base) | use |
| login limits, cookie flags | already in Riffbox | keep |
| several apps behind one login | Authelia and similar forward-auth proxies | not part of TI; revisit only if apps multiply |
| FastCGI so httpd could gate apps | `flup6`, `flipflop` (old forks, doubtful maintenance) | rejected |
| restart after deploy | none in OpenBSD | explicit `doas rcctl restart riffbox` |

Bespoke code left in the whole plan: ~5 lines in `login()`, the linear `install.sh`, the Restore button's glue.

## 8. Every command you will paste, line by line

**Stage 0 recon (read-only):**
```sh
rcctl ls on                               # list services that start at boot, to see what TI enabled
ls -la /var/www /var/www/htdocs           # show the web folder and who owns it (httpd's chroot)
which python3; pkg_info | grep -i python  # prove Python is installed, and which package brought it
pkg_info -Q ffmpeg                        # search OpenBSD's package list for ffmpeg (changes nothing)
man httpd.conf | col -b | grep -n -i -B1 -A5 'authenticate\|location'
```
`man httpd.conf` prints the manual; `col -b` strips formatting; `grep -n -i -B1 -A5` searches ignoring case, with line numbers and
context. Why: the manual on your own server is the authority for your OpenBSD version, and I could not read it from here.

**`doas sh ~/server/install.sh`** (`doas` = run as root; `sh` = run with the standard shell; the path is the uploaded file). In order
(draft; each config change is checked with `relayd -n` / `httpd -n` first):
1. `pkg_add py3-flask py3-waitress ffmpeg`: Riffbox's dependencies.
2. `groupadd _riffbox` then `useradd -g _riffbox -L daemon -s /sbin/nologin _riffbox`: an account that cannot log in and owns only
   Riffbox's files, so a web-app bug cannot touch the rest of the server.
3. `install -d -o YOURUSER -g _riffbox -m 2775 /var/riffbox /var/riffbox-backup /home/YOURUSER/restore`: data, backup and restore
   folders, owned by you, group-writable by the app; the leading `2` (setgid) keeps new files in the app's group, so you can read and
   upload data with your own login and no `doas`.
4. Copy the rc.d template to `/etc/rc.d/riffbox`; `rcctl enable riffbox; rcctl start riffbox`: start at boot and now.
5. `cp -p /etc/relayd.conf /etc/relayd.conf.pre-kit`; add a block between `# BEGIN site-kit` and `# END site-kit` sending `/ideas/api/*`
   and `/ideas/` as today to Riffbox's local port; `relayd -n`; `rcctl reload relayd`. The marked block lets the script replace it
   later without touching Derek's lines; the `.pre-kit` copy is your undo.
6. Same pattern for `httpd.conf` with the `/private/*` `authenticate` rule; write `/var/www/htpasswd` from the passphrase.
7. Write `/etc/riffbox.conf` (data folder, session secret, passphrase hash, upload token), mode 640 root:`_riffbox`. Prompt:
   "Paste your existing upload token, or press Enter for a new one." Why: the phone Shortcut holds the token; reusing it means a server
   rebuild never breaks the Shortcut. A new token means editing the Shortcut once (`deploy/SHORTCUT.md` section 0). Keep the token in
   your password manager, not in the kit.
8. Root crontab line `30 3 * * * <python3> <path>/backup.py /var/riffbox /var/riffbox-backup` (minute, hour, day, month, weekday,
   command: every night at 03:30 run the backup you already have).
9. Print PASS/FAIL from `curl` checks against localhost.

## 9. Stages (each ends with a gate only you can run)

0. **Recon.** You provide `ti.tar`, `ti.sh` and the output above.
1. **Spike (throwaway):** the relayd block reaches waitress; httpd `authenticate` works on `/private/*`; Basic prompt on iPhone Safari
   and Chrome; Werkzeug hash parameters checked against OWASP; per-request cost of the httpd check on your 1-vCPU box.
2. **Kit and install script** (branches `kit`): section 4; riffbox page moved to `htdocs`; delete `deploy.sh/.ps1` and PHASE2's manual
   steps; rewrite `UNINSTALL.md`. Local tests: `sh -n`, `shellcheck`, a fake-root run, riffbox's 255 server tests and 15 browser
   scripts. Measure with `tests/perf/measure.cjs`: httpd does not gzip (from memory), so page files from it may lose `webcache.py`'s
   compression; if so the app keeps serving its own page. **Gate: server rebuild drill** on a new Vultr instance with a **throwaway
   domain** (`ti.sh` deletes the domain's existing Vultr DNS records when re-run, so a rehearsal on the real domain would rewrite live DNS).
3. **Riffbox data restore in the app** (branch `restore-in-app`). Gate: restore your real backup in the drill.
4. **Gate** (branches `gate`): extract auth into `app/riffbox/auth.py` (section 7.4), write `docs/AUTH.md`, hashed passphrase in Riffbox,
   `/private/*` rule, repeat the Shortcut phone test (`SHORTCUT.md` section 6), `gate-test.sh` (public 200; private 401 without
   password and 200 with; wrong password 401; Riffbox data routes 401 without a session; token upload accepted, wrong token refused).
   Gate: run it from outside; iPhone checks; change the password with `--passwd` and confirm the old one fails.

## 10. Rejected, against the TI tests

App host and cron reload (not standard); Basic auth for the API via a shared `htpasswd` (not standard); custom FastCGI server
(bespoke); running the app as your login user from `@reboot` cron (root-equivalent); `slowcgi` (chroot has no Python or ffmpeg);
copying Flask into the kit (you would carry its security patches); forking `ti.sh`; forward-auth proxy (server-level addition);
VPN or client certificates (not a password; awkward on the phone); standard-library-only server (rewrites multipart and `Range`).

## 11. Unverified, and housekeeping

- **Unverified (Stage 0/1 settle it):** httpd match order between locations; relayd path-glob syntax; httpd not gzipping; Basic auth
  on iOS including audio; `useradd` flags; ffmpeg package size on 7.9; Flask staying compatible after a `sysupgrade`; Werkzeug's
  scrypt defaults against the current OWASP numbers (secondary sources disagree on Argon2id values). Nothing OpenBSD-specific can
  run on the build machine, so every deploy gate is yours.
- Update `PHASES.md`, `about.html` roadmap and Last updated, `README.md` and `docs/PLAN.md` in riffbox, and the new `docs/` in
  personal-site, each stage. Develop personal-site on `claude/zealous-fermi-gabbaw`; riffbox changes need push access added to this session.

## Sources
- [OpenBSD httpd.conf(5)](https://man.openbsd.org/httpd.conf)
- [Password-protecting httpd(8) with htpasswd(1)](https://ratfactor.com/openbsd/blog-14-httpd-and-htpasswd)
- [OpenBSD httpd Basic authentication with htpasswd](https://dev.to/nabbisen/openbsd-httpd-basic-authentication-with-htpasswd-4p72)
- [OpenBSD Handbook: relayd](https://www.openbsdhandbook.com/relayd/)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) (only partly retrieved; confirm numbers there)
- [OWASP wiki: Basic Authentication](https://wiki.owasp.org/index.php/Basic_Authentication)
- [UT Austin: avoid HTTP Basic authentication when possible](https://security.utexas.edu/content/avoid-http-basic-authentication-when-possible)
- [OWASP WSTG: testing cookie attributes](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/06-Session_Management_Testing/02-Testing_for_Cookies_Attributes)
- [Authelia forward-auth overview (blog)](https://akashrajpurohit.com/blog/setup-authelia-for-sso-authentication/)
- [flup6 on PyPI](https://pypi.org/project/flup6/1.0/) and [flipflop](https://pypi.python.org/pypi/flipflop)
- [Flask-Security-Too features](https://flask-security-too.readthedocs.io/en/latest/features.html) (built on Flask-Login, passlib hashing)
- [Flask auth options compared (WorkOS blog)](https://workos.com/blog/top-authentication-solutions-flask-2026)
- [Shortcuts with a Bearer header: Coda webhooks thread](https://connect.superhuman.com/t/siri-ios-and-coda-webhooks/31647) and [Home Assistant thread](https://community.home-assistant.io/t/ios-shortcuts-with-ha-no-ssl-required/89529) (the search did not cover how Shortcuts handles cookies)
