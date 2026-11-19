# Planned features and to-dos, all apps in one place

One list for the whole server: the site kit (`personal-site`), the login service, Riffbox, music-share, Version Control, and the server itself.
Last updated 2026-11-19 (after the speed, busy-indicator and security round). When something is done, move it to the bottom ("Done") with the date instead of deleting it.

**Priority tags**
- **P1** do next: it protects your data, finishes something half-installed, or unblocks other work.
- **P2** worth doing soon: real improvement or hygiene, nothing is at risk while it waits.
- **P3** someday or optional: ideas, polish, "if you ever want it".
- **DECISION** needs a choice from you before anyone can start.
- **DEFERRED** you chose not to do it for now (kept so the reasoning is not lost).

**Repo tags:** `site` = personal-site (kit, login, installers, docs), `riffbox`, `music`, `vc` (Version Control), `server` (things done by hand on the OpenBSD box).
Items copied from another repo's own notes say where they came from. Those notes stay where they are; this file is the one place to prioritise.

## P1: do next

| ID | Item | Repo | Notes |
|---|---|---|---|
| T-01 | **Expand the central login to Riffbox** (recommendation 2 of the security review). Today Riffbox signs you in with its own passphrase and cookie; the site login only covers `/private/`. Exact steps, checklist and way back: `docs/DEPLOY.md` section 6 (the few-days wait is not technically needed; `both` then `site` can be the same day if the checklist passes). Original plan: (1) run the Riffbox installer once with no flags so it registers Riffbox and writes `/etc/site-auth/keys/riffbox.key`; (2) add `RIFFBOX_AUTH=both` to `/etc/riffbox.conf`, restart, sign in at `/login`, check `/ideas/`; (3) after a few days of normal use set `RIFFBOX_AUTH=site`; (4) later remove the local passphrase (T-12). The phone upload token is unaffected in every mode. Back out any time by setting `local`. | riffbox + site | `riffbox/docs/AUTH.md` section 6. Prerequisite (the login service) is installed and verified (2026-11-19). |
| T-02 | **Practise a restore once**, on your computer: pull a backup, run `deploy/practice_restore.py` on it. | riffbox | The first restore should not be an emergency. `riffbox/docs/PLAN.md` section 6. |
| T-03 | **Pull backups to your computer regularly.** A FreeFileSync pull job per app: `/mnt/data/apps/<app>/backup` to `server-mirror\mnt\data\apps\<app>\backup`. A backup on the same volume does not survive losing the volume. | server | `docs/UPLOAD-INSTALL-PLAN.md` section 3.2. Press *Back up now* in each app first. |
| T-04 | **Update music-share on the server, then the reboot test.** Its address is now `/music-share`: re-run its installer with `--repair` (it asks before touching `relayd.conf` and `/etc/musicshare.conf`), sign in again once, then `doas reboot` and check all services and both volumes come back by themselves. | music, server | Steps: `version-control/docs/DEPLOY.md` sections 3 and 5. Needs the polish branch merged first (T-09). Old `/music/...` links stop working (D-05). |
| T-05 | **Merge Version Control's branch** `version-control-visual-cohesion-and-deploy-docs`. It already contains `version-control-data-on-shared-volume`, so this one merge covers both; optionally rename the default branch to `main` afterwards (D-04). | vc | Built on the data volume and the login (both done). |
| T-06 | **Email via `ti.sh`.** Before running: `ls /root/my` must show `storageno` and `webok`; copy the baseline files again; diff afterwards (`docs/STORAGE.md` section 0). | server | Still pending. |
| T-07 | **Merge `planned-features-and-upload-workflow-docs`**: this file, `docs/DEPLOY.md`, the partition notes, the PowerShell gate-test fix, the login race fix with its 37 attack tests, and the new `server/install.sh` (T-13). It already contains `login-security-testing-and-hardening`; afterwards delete that branch and `gate-test-powershell-passphrase-fix`. | site | One merge covers all of it. |
| T-08 | **Prove the start guard works on OpenBSD**: temporarily rename `/mnt/data/.volume-ok`, `doas rcctl restart <app>` must refuse to start, then rename it back. I could not run this; the guard (`rc_pre`) is written from the documented behaviour. | server | `kit/appkit/appkit.sh`. |
| T-09 | **Merge music-share's `music-share-soundcloud-style-polish-and-speed`** (SoundCloud-style look with no social parts; accurate "played" counts; link-preview robots no longer inflate "opened"; cached, compressed assets; upload progress bar). | music | Based on today's `main`: a clean merge. What it does is listed in `music-share/README.md`, "Look and feel". |
| T-21 | **Install Version Control** (after T-05): `--check`, then the installer, then its five-point checklist and the pull job for its backup folder. | vc, server | `version-control/docs/DEPLOY.md` sections 4 and 7. Decision D-03 was waiting on the guide; it now exists. |

## P2: worth doing soon

| ID | Item | Repo | Notes |
|---|---|---|---|
| T-10 | **One FreeFileSync job instead of five** (htdocs, install.sh, and one pair for the whole `staging` folder). | server + site | Instructions: `docs/UPLOAD-PLAN.md` sections 2 to 5 and `docs/UPLOAD-INSTALL-PLAN.md` section 3.1. |
| T-11 | **Nightly backup** for each app's data (cron line from `riffbox/deploy/PHASE8.md`, untried on OpenBSD) and the same for music-share and Version Control. Deliberately not installed so far. | riffbox, music, vc | Riffbox README "Planned features". Needs T-02 first. |
| T-12 | **Remove the old plain-text `RIFFBOX_PASSPHRASE` setting** and, once `RIFFBOX_AUTH=site` has been stable, Riffbox's own passphrase code. | riffbox | `riffbox/docs/AUTH.md` section 7 ("not changed, on purpose"). Do after T-01. |
| T-13 | **Replace httpd's password rule for `/private/` with a refusal** (recommendation 3). The new `server/install.sh` swaps `authenticate` for `block return 404` (fail-closed if the relayd rule were ever lost) and refuses to run unless relayd already has a `/private` rule. The old `/var/www/htpasswd` stays until you delete it. Built and tested offline; **not yet run on the server**. | site, server | `docs/DEPLOY.md` section 5 (pre-flight, check, apply, verify, way back). |
| T-14 | **Free-space check in the installers.** Warn (or refuse) when `/usr/local` has less than, say, 300 MB free, before copying program files. | site (kit) | New idea; see `docs/STORAGE.md` "The boot disk's two partitions". |
| T-15 | **Large uploads through relayd**: timeouts are unverified (up to 300 MB for Riffbox and music-share, 1 GB for Version Control). Try one big upload per app and write down the result. | vc, music, riffbox | `version-control/README.md` "limits". |
| T-16 | **Record the real expansion result.** Grow the data partition once (or at least rehearse it) and replace the "unverified" notes in `docs/STORAGE.md` section 5 with what actually happened. | server | Needs a bigger Vultr volume; do it when you actually need space. |
| T-17 | **Keep mail and calendar safe on a wipe.** Today `~/Maildir` and Radicale (`radbak` copies into your home, the same disk) are lost with the boot disk. Options: point `radbak` and a Maildir copy at `/mnt/data/_server/`, or pull them to your computer. | server | `docs/STORAGE.md` section 6. |
| T-18 | **Monthly self-test and yearly-care checklist** for Riffbox; run the audio browser tests in Firefox on a machine with a sound device. | riffbox | Riffbox README "Planned features". |
| T-19 | **Make the site-kit `install.sh` tidy too**: it still lives at `/home/me/install.sh`; moving it to `~/staging/` means one `staging` pair covers everything. Any folder works (it is self-contained). | site | `docs/UPLOAD-PLAN.md` pair B. |
| T-20 | **Cross-link the lists**: a one-line pointer in each repo's README to this file, so planned work in one place is found from every repo. | site, riffbox, music, vc | |
| T-22 | **Move the shared look into the kit.** `static/listen.css` (round play button, cards, header, bottom bar, favicon) is the same file in music-share and Version Control, kept identical by hand. Make it a kit part (`kit/listen`) so `check-vendored.sh` catches drift. | site (kit), music, vc | Built this way to avoid a third merge; the risk is the two copies drifting. |
| T-23 | **Smaller kit parts.** Music-share vendors whole kit parts but does not use the loudness/slice helpers (`kitaudio/extras.py`), the passphrase tools (`siteauth/admin.py`, `passwords.py`) or the loop code in `wave.js` (about 7 KB of unused Python plus part of `wave.js`). Split the kit parts so an app ships only what it uses. | site (kit) | Measured 2026-11-19. Music-share's front end (CSS and JS) is 42 KB raw and about 15 KB gzipped (the server now sends the gzipped form). |
| T-25 | **Deploy the login race fix**: upload the `login` folder, `--app-files-only`, gate test. 30 simultaneous guesses used to be checked against a limit of 5. | site, server | `docs/DEPLOY.md` sections 2 to 4. |
| T-26 | **MEASURED 2026-11-19 (owner): the data volume takes 1285.7 ms for a durable write, the boot disk 1.9 ms; the public page's own work is 6.9 ms (about 106 ms in the browser). Next: move music-share's database to the boot disk (`version-control/docs/DEPLOY.md` section 9), then do the same measurement for Riffbox and Version Control, whose databases are on the same volume.** Original item: find out why the public page can take 5 to 10 s. After merging T-09 and deploying: Studio, Backup tab, **Speed check**; and look at the `Server-Timing` header (`db`, `render`, `app`) on a slow load. High `db` means only the small database needs faster storage (`MUSICSHARE_DB_DIR` on the SSD; audio stays on the HDD). Low `app` but a slow load means relayd, TLS or the network, not the disk. | music, server | The diagnosis is by measurement; an SSD is not assumed. |
| T-27 | **Security leftovers** (from the 2026-11-19 review): (a) run the attack-test battery against Version Control (same patterns as music-share's `tests/test_security.py`); (b) review `httpd.conf`, `pf.conf`, `ti.sh` mail and Radicale for password strength and exposure; (c) dependency audit: the repos have no requirements files `pip-audit` could read, so list pinned versions and check them by hand or with `pip-audit` on the server's `pip freeze`; (d) mark the SHA-1 ETag uses `usedforsecurity=False`; (e) cap the in-memory attempt table's size; (f) a passphrase of 60+ bits of randomness (5 to 6 random words) for the one login. | site, vc, music | See the final report of the review; (a) and (b) are the real gaps. |
| T-40 | **Phone check on a real iPhone** for music-share (and Version Control's waveform): `version-control/docs/DEPLOY.md` section 11. Tested in emulated Chromium on five device profiles only; iOS Safari's lock-screen controls, input zoom and home-bar spacing are unverified. | music, vc | Also never built: an Add-to-Home-Screen icon (Apple needs a PNG, not our inline SVG). |
| T-24 | **Check the new counts on real use.** After a week, do "played" and "opened" in the Studio match what friends actually did? If a chat app still inflates "opened", add its name to `ROBOT` in `app/musicshare/__init__.py`. | music | Robot detection is by browser-name keywords (unverified against every app). |

## P3: someday or optional

| ID | Item | Repo | Notes |
|---|---|---|---|
| T-38 | **Optional second factor (TOTP)** on the site login. Not built; a 6-digit code needs either a small package or about 40 lines (HMAC-SHA1 is in the standard library) plus recovery codes. Worth it only if you ever cannot guarantee a long random passphrase. | site | Decide in D-06. |
| T-39 | **SSH key passphrase and `doas` policy** (finding 11 of the review): `ssh-keygen -p` on your private key, and consider `permit persist me` instead of `permit nopass me` in `/etc/doas.conf`. Changes a system file: not done without your yes. | server | Today anyone who copies your key file is root. |
| T-30 | **Weekly email digest** of a few forgotten hearted ideas, through the server's `smtpd` and smtp2go relay. Needs email working (T-06). | riffbox | Riffbox README. |
| T-31 | **Verify-library button and an off-server-copy reminder.** | riffbox | Riffbox README "Candidate features". |
| T-32 | **Timestamped markers on the waveform**; **waveform thumbnails** in the list; **the memo's creation date** passed from the Shortcut as the date recorded; **a home-screen icon.** | riffbox | Riffbox README. |
| T-33 | **One row-actions (⋯) menu** and a **two-step edit form** ("More details" collapsed). Possible future features, not planned (owner, 15 Nov 2026). | riffbox | Riffbox README. |
| T-34 | **Longer phone check** of Resurface, Compact rows, grouping from the Inbox, the Menu's Style and Colors. | riffbox | `riffbox/docs/PLAN.md` section 6. |
| T-35 | **music-share: export to a zip or folder.** Not built; backup and restore only. (Comments and versions are deliberately not wanted here: versions are the Version Control app.) | music | `music-share/README.md`. |
| T-36 | **A second data volume** (option 2 in `docs/STORAGE.md` section 5), the natural home for Version Control if the first fills. | server | |
| T-37 | **Show the last list instantly on repeat visits** (keep the last Studio list in the browser, draw it at once, refresh behind it). Not built: with the menu and placeholders already instant it may not be needed. | music, vc | Measure first with the `Server-Timing` header. |

## DECISION: needs you

| ID | Question | Notes |
|---|---|---|
| D-01 | **When to switch Riffbox to `RIFFBOX_AUTH=both`, then `site`** (T-01). | After a few days of using the login for `/private/`. |
| D-02 | **How relaxed should the lockout be?** Settings exist per service: `SITELOGIN_MAX_FAILS`/`SITELOGIN_WINDOW_MINUTES`, `RIFFBOX_LOGIN_MAX_FAILS`/`RIFFBOX_LOGIN_WINDOW_MINUTES` (default 5 tries per 15 minutes). | Suggested relaxed values: 15 tries per 5 minutes. |
| D-03 | **Install Version Control now or later?** | The deploy guide exists (T-21); needs T-05 first. |
| D-04 | **Rename the Version Control default branch to `main`?** | personal-site, riffbox and music-share already use `main`. |
| D-06 | **Add TOTP to the site login (T-38)?** | Recommended only if the passphrase will not be long and random. |
| D-05 | **Redirect old `/music/...` links to `/music-share/...`?** | Links already sent under `/music` stop working after the rename (T-04). A redirect is a small relayd rule or app route; only needed if you sent links you still care about. |

## DEFERRED: you chose not to, for now

| Item | Why it was parked |
|---|---|
| Off-Vultr or object storage (Hetzner Storage Box, S3-style stores) as an off-site backup copy | Chosen 2026-11-19: stay on Vultr. A backup on the same volume does not protect against losing it, so T-03 (pull to your computer) is the stand-in. |
| Object storage as Riffbox's primary audio store | Needs an app rewrite; SQLite cannot live there; `/pub/` cannot be served from it. Revisit only if data outgrows the volume. |
| Encrypted storage | Dropped 2026-11-19 in favour of plain storage for app data. Secrets stay on the boot disk, never on the volume. |

## Decided against (Riffbox, owner, 15 Nov 2026)
Serving the page from `htdocs` instead of the app; a standard-library-only server (Flask and waitress stay); a record-and-send Shortcut (Voice Memos to Share to Shortcut stays).

## Known unverified (settle by doing; then remove from this list)
- OpenBSD behaviour of the start guard (`rc_pre`), `noexec` on the data partition, growing a partition in place with `disklabel` and `growfs` (T-08, T-16).
- iPhone Safari: the round play button icons (CSS masks), A/B switching in Version Control, and the bottom player bar. The browser tests cannot judge phones or sound.
- Whether gzip'd answers and `Server-Timing` pass through relayd unchanged (they should; look at the Network tab once).
- FreeFileSync menu names and filter syntax in your version (`docs/UPLOAD-PLAN.md` section 3).
- Whether `httpd` would follow a symlink out of its root (only matters if `/pub/` is ever moved into one filesystem with the apps).

## Done
- 2026-11-19: site login installed and verified from outside (gate test, all ten checks).
- 2026-11-19: data volume set up (25 GB `/pub/` + 75 GB app data), Riffbox data moved onto it, `/pub/` on its own partition.
- 2026-11-19: installers write start guards and rebuilt service users adopt the data's uid; apps live under `/mnt/data/apps/<app>/`; upload staging under `~/staging/<app>`.
- 2026-11-19: Riffbox and site-login lockout limits made configurable (defaults unchanged).
- 2026-11-19: big uploads park on the data volume (music-share, Version Control), as Riffbox already did.
- 2026-11-19: Studio paints its menu at once (menu 1367 ms to 67 ms in a test with a 300 ms API delay); music-share served at `/music-share`; quiet Studio link for the signed-in owner (merged to music-share `main`).
- 2026-11-19: built, waiting for you to merge: music-share look and speed (T-09); Version Control shares music-share's look and has a deploy guide (T-05, T-21).
- 2026-11-19: music-share public page no longer touches the database or disk when cached; Studio shows a busy bar, "Working...", dimmed rows and in-place updates; added a Speed check (T-26 to measure on the server).
- 2026-11-19: music-share made phone-friendly (touch-safe waveform in the shared kit, 44 px targets, no iOS zoom, safe areas, lock-screen controls, tabs that fit); tested on five emulated devices with screenshots (`tests/e2e/mobile.cjs`). Built, waiting for you to merge; real-iPhone check is T-40.
- 2026-11-19: security testing: login service (37 attack tests; one real race found and fixed, T-25), music-share (21 attack tests; one real bug found and fixed: a very long file name failed an upload with a 500), Riffbox startup warning for a missing site key. Built, waiting for you to merge and deploy.
- 2026-11-19: built and tested offline, not yet run on the server: `/private/` refusal in httpd (T-13) and the Riffbox move to the single login (T-01), with exact steps in `docs/DEPLOY.md`.
