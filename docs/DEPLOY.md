# Deploying the personal-site changes (login service fix, `/private/` refusal, Riffbox single login)

Written 2026-11-19. Extends `docs/UPLOAD-INSTALL-PLAN.md` (the FreeFileSync design and install order) and `docs/UPLOAD-PLAN.md`; this file only covers **what changed in this round** and the exact steps.
Rules as always: Update never Mirror, read every preview, `--check` before every installer, nothing deleted without you saying so, one thing at a time with a way back.
**Not verified (I have no OpenBSD server here):** every command run on the server, FreeFileSync menu names, and `block return 404` inside an httpd `location` on 7.9 (the installer asks `httpd -n` to check it before it changes anything).

## 0. What changed, and what it needs

| Change | Where it lives | Needs uploading? | Needs a server command? |
|---|---|---|---|
| Login service: parallel-guess race fixed (30 simultaneous guesses used to be checked against a limit of 5; now check and count are one step) | `login/app/sitelogin/__init__.py` | yes: the `login` folder | `--app-files-only` (restarts the login service, a second or two) |
| `/private/` refused by httpd instead of a Basic-auth password (recommendation 3) | `server/install.sh` | yes: `install.sh` (pair B) | `doas sh ~/install.sh` |
| Riffbox: logs an error if the site login is chosen but its key is missing; extra tests (recommendation 2) | riffbox repo, branch `riffbox-site-login-only-mode` | optional; **not needed** to switch modes | none for the switch itself, see section 6 |
| Docs and tests | `docs/`, `RESTORE.html`, `tools/` | no (they stay on your computer) | no |

Nothing in `htdocs`, `kit`, relayd, pf or the other apps changes.

## 1. Branches and merges (merge count for you)
| Repo | Branch to merge | What it carries |
|---|---|---|
| personal-site | `planned-features-and-upload-workflow-docs` | **everything above for personal-site**: this file, TODO.md, the PowerShell gate-test fix (it already contains the earlier docs branch and `login-security-testing-and-hardening`, merged in) |
| riffbox | `riffbox-site-login-only-mode` | the startup error message and tests (optional but small and safe) |
| music-share | `music-share-soundcloud-style-polish-and-speed` | speed, busy indicators, long-file-name fix (unchanged from the earlier message; still the one merge, T-09) |
| version-control | `version-control-visual-cohesion-and-deploy-docs` | unchanged (T-05); its DEPLOY.md gained the speed-check and security notes |

After merging personal-site, you can delete the branches `login-security-testing-and-hardening` and `gate-test-powershell-passphrase-fix` (their commits are inside the merged branch) when you choose.

## 2. Get the files (on your computer)
1. On GitHub, personal-site, branch selector: pick `planned-features-and-upload-workflow-docs` (or `main` once merged), **Code, Download ZIP**. A ZIP (not `git clone`) keeps Unix line endings in `install.sh`.
2. Unpack it. You need only:
   - `login\` -> put it at `server-mirror\home\me\staging\login\` (replace the folder's contents; it holds `app`, `static`, `deploy`, `kit.use`).
   - `server\install.sh` -> put it at `server-mirror\home\me\install.sh` (replace the old one).
   - Keep `tools\` and `RESTORE.html` on your computer (the gate-test scripts run from there).
3. Do **not** upload `docs\`, `kit\`, `tests\`, `reference\` or `htdocs\` this time (htdocs is unchanged).

## 3. Upload (FreeFileSync)
Your existing `Deploy.ffs_gui` pair for `server-mirror\home\me` -> `/home/me` already includes `\install.sh` and `\staging\login\*` (the filter from `docs/UPLOAD-INSTALL-PLAN.md` section 3.1). **No filter change.**
1. Open `Deploy.ffs_gui`, press **Compare**.
2. The preview should show **exactly**: `install.sh` (update) and the files of `staging\login` that changed. Expected for login: only `app\sitelogin\__init__.py`, plus the three `__pycache__` files only if your copy included them (they are excluded by the filter, so none). If you also see `riffbox`, `music-share` or `version-control` files, that is fine only if you downloaded newer copies on purpose; otherwise stop.
3. If you see anything under `.ssh`, `Maildir` or anything outside `install.sh` and `staging`: **stop**, the Include filter is not applied.
4. Synchronize. Direction stays **Update, left to right** (never deletes on the server).
5. On the server confirm (read-only): `ls -l ~/install.sh ~/staging/login/app/sitelogin/__init__.py`. The times should be today.

## 4. Deploy the login service fix
```
doas sh ~/staging/login/deploy/install.sh --check
```
Reads: shows what it would change and changes nothing. Expect "LEFT ALONE" for system files and the app files marked as changed.
```
doas sh ~/staging/login/deploy/install.sh --app-files-only
```
Copies only the program files and restarts `sitelogin` (a second or two; people signed in keep their cookies, since keys do not change). Ends with `PASS: Site login answers on 127.0.0.1:8099`.
From your computer: `powershell -ExecutionPolicy Bypass -File tools\gate-test-login.ps1 -Domain sanjaysubramanian.com` (or `sh tools/gate-test-login.sh sanjaysubramanian.com`). All PASS. It makes one wrong sign-in on purpose.
**Way back:** re-upload the previous login folder and run the same `--app-files-only` command.

## 5. Recommendation 3: stop httpd asking for the old password
**What this does.** `/private/` is already served by the login service (relayd sends it there before httpd sees it). The old httpd rule (`authenticate ... with "/htpasswd"`) is therefore bypassed, but it
is still a second, unthrottled password check using the same passphrase. The new `install.sh` replaces those three lines, in the same marked block, with `block return 404`: if a request ever reaches httpd for
`/private/...` it is refused, so losing the relayd rule fails **closed** (404) instead of open. It does not delete `/var/www/htpasswd` (you do that yourself, section 5.5).

**5.1 Pre-flight (proves the login is really in front; read-only).**
From your computer (any browser or PowerShell with `curl.exe`):
```
curl.exe -s -o NUL -D - https://sanjaysubramanian.com/private/index.html
```
Expect `HTTP/1.1 302` (or 401 JSON) from the login service and **no** `WWW-Authenticate: Basic` header. If you see `WWW-Authenticate: Basic`, relayd is still sending `/private` to httpd: stop, tell me, do not continue.
Also sign in at `https://sanjaysubramanian.com/login` in a browser and open `https://sanjaysubramanian.com/private/index.html`: your private page appears without a password popup.
On the server: `doas grep -n '"/private' /etc/relayd.conf` shows two lines (`/private` and `/private/*`). The new installer checks this itself and refuses without it.

**5.2 Dry run.**
```
doas sh ~/install.sh --check
```
Expect a diff that changes **one line** inside the `# BEGIN site-kit` block: `authenticate "private" with "/htpasswd"` becomes `block return 404`, and the comment above it. Nothing else.
If it shows anything else (other lines of httpd.conf), stop.

**5.3 Apply.**
```
doas sh ~/install.sh
```
It keeps your original in `/etc/httpd.conf.pre-kit` (made the first time), asks `httpd -n` to check the new file (it will not copy it if httpd rejects it), copies it, reloads httpd, and ends with
`PASS: httpd itself refuses /private/index.html (404)`. It also tells you the old password file is still there.

**5.4 Verify from outside.**
- `sh tools/gate-test-login.sh sanjaysubramanian.com` (or the `.ps1`): all PASS.
- Browser, signed in: `/private/index.html` still opens. Signed out (private window): it sends you to `/login`.
- Server: `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: sanjaysubramanian.com' http://127.0.0.1:8080/private/index.html` prints `404`. (That is httpd directly, bypassing relayd: it must refuse.)
- The public site (`https://sanjaysubramanian.com/`, `/pub/...`) still loads.

**5.5 Tidy later, only when you say so.** The old password file is unused. `doas rm /var/www/htpasswd` deletes it. Keep it a week if you want a way back (see below).

**Way back.**
- Put httpd back exactly as before this step: `doas cp -p /etc/httpd.conf.pre-kit /etc/httpd.conf; doas httpd -n && doas rcctl reload httpd` (that is the original Tech Independence file, so it removes the whole block; the login service still guards `/private/`).
- To get the old Basic-auth rule itself back, use the previous `install.sh` (git history of personal-site `main` before this merge) with the password file kept.
- `doas sh ~/install.sh --remove` removes only the kit block, with the same effect as the first bullet but keeping other edits.
If something unexpected answers 404 on `/private/` in a browser while signed in, the relayd rule is missing: the installer would have refused, so this means relayd.conf changed afterwards; check `doas grep -n '"/private' /etc/relayd.conf`.

## 6. Recommendation 2: Riffbox on the single login (`RIFFBOX_AUTH=site`)
**What this does.** Riffbox stops accepting its own passphrase and its own cookie; only the central login (throttled once, one hash, log-out-everywhere) opens `/ideas/`. The phone Shortcut's upload token is unchanged
(tested: `app/tests/test_site_auth.py`). Back out at any time by changing the setting back; no data is touched.
**Is the few-days wait in T-01 needed?** Not technically. `both` exists so you can prove the new door opens before you close the old one; that takes minutes. What must be true before `site` is the checklist in 6.3.

**6.1 Preconditions (read-only).**
- The login service answers (section 4's PASS) and Riffbox has been registered: `doas ls -l /etc/site-auth/keys/riffbox.key` exists (owner `root`, group `_riffbox`, readable by the group). If not, run `doas sh ~/staging/riffbox/deploy/install.sh --check`, then without `--check`: it registers Riffbox and restarts it.
- Back up the conf: `doas cp -p /etc/riffbox.conf /etc/riffbox.conf.pre-site-auth`.

**6.2 Step one: `both` (either login works).**
```
doas vi /etc/riffbox.conf
```
Add a line `RIFFBOX_AUTH=both` (if a `RIFFBOX_AUTH=` line already exists, change it instead; there must be exactly one). Save (`Esc`, `:wq`, Enter). Then:
```
doas grep RIFFBOX_AUTH /etc/riffbox.conf
doas rcctl restart riffbox
```
The first shows the single line; the second restarts Riffbox (a few seconds).
Test: private window, `https://sanjaysubramanian.com/ideas/` sends you to `/login?next=/ideas/`; sign in with the **site** passphrase; Riffbox opens.

**6.3 Checklist before `site` (all four):**
1. Signed in through `/login`, `/ideas/` lists your recordings and plays one.
2. A brand-new private window: `/ideas/` -> `/login` -> back to `/ideas/` after signing in.
3. **Phone:** run the Voice Memos Shortcut once; the upload lands in the Inbox (this proves the Bearer token path).
4. You know the site passphrase by heart or have it in your password manager (after `site`, Riffbox's own passphrase stops working).

**6.4 Step two: `site`.**
```
doas vi /etc/riffbox.conf
```
Change the line to `RIFFBOX_AUTH=site`; save. `doas rcctl restart riffbox`.
Check from outside:
```
curl.exe -s https://sanjaysubramanian.com/ideas/api/auth-info
curl.exe -s -o NUL -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "{\"passphrase\":\"x\"}" https://sanjaysubramanian.com/ideas/api/login
curl.exe -s -o NUL -w "%{http_code}" https://sanjaysubramanian.com/ideas/api/session
```
Expect `{"mode":"site","site_login":"/login"}`, then `410` (the old login is retired), then `401` (not signed in). Then re-run checklist items 1 to 3.
If the server log (`doas tail -n 30 /var/log/daemon`) shows "RIFFBOX_AUTH=site but the site key ... is missing" (needs the riffbox branch, section 1), nobody can sign in: set `local` and fix the registration (6.1).
**Way back:** set `RIFFBOX_AUTH=local` (or `both`), `doas rcctl restart riffbox`. If locked out of `/login` itself by wrong guesses: `doas rcctl restart sitelogin` clears the in-memory limits.

**6.5 After a calm week (T-12, separate step).** Remove `RIFFBOX_PASSPHRASE_HASH` (and any old `RIFFBOX_PASSPHRASE`) from `/etc/riffbox.conf`, so a stolen or guessed old passphrase opens nothing. Not required for the switch.

## 7. Everything in one order
1. Merge personal-site (and riffbox, optional). 2. Download, replace `login\` and `install.sh` in the mirror. 3. Preview, synchronize. 4. Login `--check` then `--app-files-only`, gate test.
5. Section 5 (httpd refusal). 6. Section 6 (Riffbox `both`, checklist, `site`). Each step has its own way back; do them on different days if you prefer, but 4 before 5 and `both` before `site`.

## 8. Unverified, and what settles it
- `block return 404` accepted inside `location` in httpd.conf on OpenBSD 7.9: `httpd -n` in the installer (it refuses to apply if rejected).
- relayd really routes `/private` before httpd: the 5.1 header check.
- iPhone Shortcut after `site`: checklist item 3.
