# Planned features and to-dos, all apps in one place

One list for the whole server: the site kit (`personal-site`), the login service, Riffbox, music-share, Version Control, and the server itself.
Last updated 2026-11-19. When something is done, move it to the bottom ("Done") with the date instead of deleting it.

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
| T-01 | **Expand the central login to Riffbox.** Today Riffbox signs you in with its own passphrase and cookie; the site login only covers `/private/`. Plan: (1) run the Riffbox installer once with no flags so it registers Riffbox and writes `/etc/site-auth/keys/riffbox.key`; (2) add `RIFFBOX_AUTH=both` to `/etc/riffbox.conf`, restart, sign in at `/login`, check `/ideas/`; (3) after a few days of normal use set `RIFFBOX_AUTH=site`; (4) later remove the local passphrase (T-12). The phone upload token is unaffected in every mode. Back out any time by setting `local`. | riffbox + site | `riffbox/docs/AUTH.md` section 6. Prerequisite (the login service) is installed and verified (2026-11-19). |
| T-02 | **Practise a restore once**, on your computer: pull a backup, run `deploy/practice_restore.py` on it. | riffbox | The first restore should not be an emergency. `riffbox/docs/PLAN.md` section 6. |
| T-03 | **Pull backups to your computer regularly.** A FreeFileSync pull job per app: `/mnt/data/apps/<app>/backup` to `server-mirror\mnt\data\apps\<app>\backup`. A backup on the same volume does not survive losing the volume. | server | `docs/UPLOAD-INSTALL-PLAN.md` section 3.2. Press *Back up now* in each app first. |
| T-04 | **Update music-share on the server, then the reboot test.** Its address is now `/music-share`: re-run its installer with `--repair` (it asks before touching `relayd.conf` and `/etc/musicshare.conf`), sign in again once, then `doas reboot` and check all services and both volumes come back by themselves. | music, server | Steps: `version-control/docs/DEPLOY.md` sections 3 and 5. Needs the polish branch merged first (T-09). Old `/music/...` links stop working (D-05). |
| T-05 | **Merge Version Control's branch** `version-control-visual-cohesion-and-deploy-docs`. It already contains `version-control-data-on-shared-volume`, so this one merge covers both; optionally rename the default branch to `main` afterwards (D-04). | vc | Built on the data volume and the login (both done). |
| T-06 | **Email via `ti.sh`.** Before running: `ls /root/my` must show `storageno` and `webok`; copy the baseline files again; diff afterwards (`docs/STORAGE.md` section 0). | server | Still pending. |
| T-07 | **Merge `planned-features-and-upload-workflow-docs`** (this file, the partition notes and the PowerShell gate-test fix) and delete its branch and `gate-test-powershell-passphrase-fix`. | site | |
| T-08 | **Prove the start guard works on OpenBSD**: temporarily rename `/mnt/data/.volume-ok`, `doas rcctl restart <app>` must refuse to start, then rename it back. I could not run this; the guard (`rc_pre`) is written from the documented behaviour. | server | `kit/appkit/appkit.sh`. |
| T-09 | **Merge music-share's `music-share-soundcloud-style-polish-and-speed`** (SoundCloud-style look with no social parts; accurate "played" counts; link-preview robots no longer inflate "opened"; cached, compressed assets; upload progress bar). | music | Based on today's `main`: a clean merge. What it does is listed in `music-share/README.md`, "Look and feel". |
| T-21 | **Install Version Control** (after T-05): `--check`, then the installer, then its five-point checklist and the pull job for its backup folder. | vc, server | `version-control/docs/DEPLOY.md` sections 4 and 7. Decision D-03 was waiting on the guide; it now exists. |

## P2: worth doing soon

| ID | Item | Repo | Notes |
|---|---|---|---|
| T-10 | **One FreeFileSync job instead of five** (htdocs, install.sh, and one pair for the whole `staging` folder). | server + site | Instructions: `docs/UPLOAD-PLAN.md` sections 2 to 5 and `docs/UPLOAD-INSTALL-PLAN.md` section 3.1. |
| T-11 | **Nightly backup** for each app's data (cron line from `riffbox/deploy/PHASE8.md`, untried on OpenBSD) and the same for music-share and Version Control. Deliberately not installed so far. | riffbox, music, vc | Riffbox README "Planned features". Needs T-02 first. |
| T-12 | **Remove the old plain-text `RIFFBOX_PASSPHRASE` setting** and, once `RIFFBOX_AUTH=site` has been stable, Riffbox's own passphrase code. | riffbox | `riffbox/docs/AUTH.md` section 7 ("not changed, on purpose"). Do after T-01. |
| T-13 | **Remove the old httpd password popup for `/private/`.** relayd now sends `/private` to the login, so the old rule is bypassed. `doas sh ~/install.sh --remove` takes it out (the password file is kept). | site | `docs/MULTI-APP.md`. Wait until you are sure the login is permanent. |
| T-14 | **Free-space check in the installers.** Warn (or refuse) when `/usr/local` has less than, say, 300 MB free, before copying program files. | site (kit) | New idea; see `docs/STORAGE.md` "The boot disk's two partitions". |
| T-15 | **Large uploads through relayd**: timeouts are unverified (up to 300 MB for Riffbox and music-share, 1 GB for Version Control). Try one big upload per app and write down the result. | vc, music, riffbox | `version-control/README.md` "limits". |
| T-16 | **Record the real expansion result.** Grow the data partition once (or at least rehearse it) and replace the "unverified" notes in `docs/STORAGE.md` section 5 with what actually happened. | server | Needs a bigger Vultr volume; do it when you actually need space. |
| T-17 | **Keep mail and calendar safe on a wipe.** Today `~/Maildir` and Radicale (`radbak` copies into your home, the same disk) are lost with the boot disk. Options: point `radbak` and a Maildir copy at `/mnt/data/_server/`, or pull them to your computer. | server | `docs/STORAGE.md` section 6. |
| T-18 | **Monthly self-test and yearly-care checklist** for Riffbox; run the audio browser tests in Firefox on a machine with a sound device. | riffbox | Riffbox README "Planned features". |
| T-19 | **Make the site-kit `install.sh` tidy too**: it still lives at `/home/me/install.sh`; moving it to `~/staging/` means one `staging` pair covers everything. Any folder works (it is self-contained). | site | `docs/UPLOAD-PLAN.md` pair B. |
| T-20 | **Cross-link the lists**: a one-line pointer in each repo's README to this file, so planned work in one place is found from every repo. | site, riffbox, music, vc | |
| T-22 | **Move the shared look into the kit.** `static/listen.css` (round play button, cards, header, bottom bar, favicon) is the same file in music-share and Version Control, kept identical by hand. Make it a kit part (`kit/listen`) so `check-vendored.sh` catches drift. | site (kit), music, vc | Built this way to avoid a third merge; the risk is the two copies drifting. |
| T-23 | **Smaller kit parts.** Music-share vendors whole kit parts but does not use the loudness/slice helpers (`kitaudio/extras.py`), the passphrase tools (`siteauth/admin.py`, `passwords.py`) or the loop code in `wave.js` (about 7 KB of unused Python plus part of `wave.js`). Split the kit parts so an app ships only what it uses. | site (kit) | Measured 2026-11-19. Music-share's front end (CSS and JS) is 42 KB raw and about 15 KB gzipped (the server now sends the gzipped form). |
| T-24 | **Check the new counts on real use.** After a week, do "played" and "opened" in the Studio match what friends actually did? If a chat app still inflates "opened", add its name to `ROBOT` in `app/musicshare/__init__.py`. | music | Robot detection is by browser-name keywords (unverified against every app). |

## P3: someday or optional

| ID | Item | Repo | Notes |
|---|---|---|---|
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
