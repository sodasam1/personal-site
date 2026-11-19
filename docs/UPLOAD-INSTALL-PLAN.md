# Upload and install plan: login, riffbox update, music-share, Version Control

Written to extend `docs/UPLOAD-PLAN.md` (your existing FreeFileSync design). Same rules: **Update, never Mirror, on `/home/me`; look at the preview every time;
nothing is deleted without you.** Verified: file counts and sizes below (measured on the built branches), and that each app's own installer works in test mode.
**Not verified (I have no server or FreeFileSync here):** FreeFileSync menu names and filter syntax in your version, SFTP permissions on your server, and every OpenBSD command. Each is marked.

## 0. The idea in one paragraph
Uploading only puts files in your home folder (`/home/me/<app>/`). **Nothing goes live until you run that app's installer on the server**, and every installer has a
`--check` that changes nothing. So uploading all four folders at once is safe; the order that matters is the *install* order (section 4): login first, then the apps.
The first three apps need no root for the upload; the installers use `doas`.

## 1. What you upload, and where it comes from
Branches (all pushed, none merged):

| Folder on the server | Comes from | Branch | Notes |
|---|---|---|---|
| `/home/me/login/` | repo `personal-site`, its **`login/`** folder | `shared-kit-installer-login-and-theme` | the site login service (new) |
| `/home/me/riffbox/` | repo `riffbox`, whole | `adopt-shared-kit-and-harden-login` | replaces your current riffbox folder |
| `/home/me/music-share/` | repo `music-share`, whole | `music-share-waveform-list-playlists-share-links` | new |
| `/home/me/version-control/` | repo `version-control`, whole | `version-control-ab-toggle-loops-comments-storage` | new |
| `/home/me/install.sh` | unchanged | | the site kit installer: **no re-upload needed** |
| `/var/www/htdocs` | unchanged | | **pair A needs no upload this time** |

Every app folder already carries its own copy of the shared kit (that is what "vendored" means), so you do **not** upload personal-site's `kit/` folder or its `docs/`.

**How to get the files (as before: ZIPs, not `git clone`, so Windows keeps Unix line endings):** on GitHub open each repo, use the branch selector to pick the branch in the table,
then Code, Download ZIP. A branch ZIP unpacks to a folder named like `repo-branchname`; **rename it** to the folder name in the table. For personal-site, open the unpacked folder and take only
its `login\` folder. Also keep the personal-site ZIP on your computer: you need its `tools\gate-test-login.ps1` and `RESTORE.html` (they stay on your computer).

## 2. Your computer's mirror folder (extends the one you already have)
```
server-mirror\
  var\
    www\htdocs\                       (unchanged, pair A)
    riffbox-backup\                   (pulled backups, as now)
    riffbox-restore\                  (empty)
    music-share-backup\               NEW  pulled backups
    music-share-restore\              NEW  empty
    version-control\
      backup\                         NEW  pulled backups (large: it holds your audio originals)
      restore\                        NEW  empty
  home\me\
    install.sh                        (unchanged)
    riffbox\        app\  static\  deploy\  kit.use      <- replace with the new ZIP's contents
    login\          app\  static\  deploy\  kit.use      <- NEW
    music-share\    app\  static\  deploy\  kit.use      <- NEW
    version-control\ app\ static\  deploy\  kit.use      <- NEW
```
Replace the old `home\me\riffbox\` by deleting it **on your computer** and putting the new one in its place (the server copy is only a staging copy; Update will overwrite it).
Reading `server-mirror\home\me\login` is reading `/home/me/login`: if a path looks wrong on screen, it is wrong on the server.

## 3. Build the FreeFileSync jobs

### 3.1 Edit `Deploy.ffs_gui`: it keeps pair A and pair B+C; only the filter of B+C changes
Open your saved `Deploy.ffs_gui`. Pair B+C is: left `server-mirror\home\me`, right `/home/me` (your SFTP connection), synchronization **Update**. Do not change the paths. Open that pair's **filter**
(in FreeFileSync, the funnel/Filter button; for a single pair, the small gear icon next to the pair opens its local settings including its own filter: *from memory, unverified*) and set:

**Include** (one per line; only these are ever considered):
```
\install.sh
\riffbox\*
\login\*
\music-share\*
\version-control\*
```
**Exclude** (one per line):
```
*\tests\*
*\docs\*
*\archive\*
*\.git*
*__pycache__*
*\.pytest_cache\*
*.coverage
*.pyc
*sync.ffs_db
```
Why each: Include is the safety net (your home folder also holds Maildir and `.ssh`; they are never named, so they are never touched). The excludes keep tests, docs, old archive notes,
git files, Python caches and the stray `app\.coverage` file out of the upload; the installers' own copy step ignores them anyway, so this only saves bandwidth. FreeFileSync's filter
wildcard rules (`*`, leading `\`, trailing `\`) are as I remember them: **the preview is the test** (next paragraph).

**Sync direction for this pair: Update, left to right.** Update copies new and changed files and never deletes on the server.
Press **Compare** and check the preview against these expected numbers (files that do not already exist on the server will show as "create"; riffbox will show mostly "update"):

| Folder | Files | Size |
|---|---|---|
| `login` | 16 | about 96 KB |
| `riffbox` | 52 | about 656 KB |
| `music-share` | 33 | about 216 KB |
| `version-control` | 31 | about 228 KB |

If you see `tests`, `docs`, `.git`, `__pycache__` or anything outside those four folders and `install.sh`, **stop and fix the filter before pressing Synchronize.**
Stale files: Update never deletes, so a file I removed between versions would stay in the staging folder. It is harmless for the new folders (first upload). For riffbox
I did not remove anything; if a later version does, I will tell you which file to delete on the server (you do it, nothing automatic).

### 3.2 Pull jobs: server to computer (backups)
Keep `Pull-backup.ffs_gui` for riffbox. Make two more by copying it (File, Save as) and changing only the two paths:

| Job | Left (computer) | Right (server) | Synchronization |
|---|---|---|---|
| `Pull-backup.ffs_gui` (exists) | `server-mirror\var\riffbox-backup` | `/var/riffbox-backup` | Custom: new and changed items copy right to left; nothing is deleted |
| `Pull-music-share.ffs_gui` NEW | `server-mirror\var\music-share-backup` | `/var/music-share-backup` | same |
| `Pull-version-control.ffs_gui` NEW | `server-mirror\var\version-control\backup` | `/var/version-control/backup` | same |

Read the preview: for Version Control the first pull is every audio original you have (plan for gigabytes and time). **Never put anything of yours in these left-hand folders.**
Why they matter: the on-server backups share the VPS (and, for Version Control, the same volume), so these pulls are what protects you if the server or volume is lost.
SFTP permission needed: your login `me` must be able to read these folders. The installers create them world-readable (755) and `/var/version-control` is traversable (751): *unverified on your server*;
if FreeFileSync says "permission denied", tell me the folder and I will adjust the mode.

### 3.3 Restore jobs: computer to server (only after a wipe)
| Job | Left | Right | Synchronization |
|---|---|---|---|
| `Restore.ffs_gui` (exists) | `server-mirror\var\riffbox-restore` | `/var/riffbox-restore` | Update |
| `Restore-music-share.ffs_gui` NEW | `server-mirror\var\music-share-restore` | `/var/music-share-restore` | Update |
| `Restore-version-control.ffs_gui` NEW | `server-mirror\var\version-control\restore` | `/var/version-control/restore` | Update |

Put the pulled backup folder (the one holding `db\` and `audio\`) inside the left folder, run the job, then press **Restore** in that app's Backup page. The restore folder for Version Control lives on the big
volume on purpose (a restore of many GB must not land on the 25 GB boot disk).

### 3.4 What I did **not** automate
FreeFileSync can run a command after a sync (`docs/UPLOAD-PLAN.md` section 6). For these first installs, **do not**: the installers ask questions (passphrase, `y` to edit relayd.conf).
Later, for routine code-only updates, `ssh me@sanjaysubramanian.com doas sh /home/me/<app>/deploy/install.sh --app-files-only` is safe to automate (it touches no system file); unverified in your FreeFileSync edition.

## 4. Install order (the part that matters)
Open one SSH terminal (`ssh me@sanjaysubramanian.com`) **and the Vultr "View Console"** in a browser tab (a safety net if a reboot or config mistake locks you out of SSH).
`~` below is `/home/me`; `doas` runs the command as root.

### Step 0: before touching anything (10 minutes, no risk)
1. In Riffbox press **Back up now**, then run `Pull-backup.ffs_gui`. Reason: riffbox's code and installer are about to change; you want a copy of your recordings first.
2. On the server, keep copies of the files the installers will edit:
```
doas cp -p /etc/relayd.conf /etc/relayd.conf.pre-multiapp
doas cp -p /etc/riffbox.conf /etc/riffbox.conf.pre-multiapp
```
`cp -p` copies and keeps owner and mode. The installers also keep their own `.pre-<app>` copies; these two are the "everything as it was before today" set.
3. Optional: `doas syspatch -c` lists pending OS patches (read-only).

### Step 1: upload (FreeFileSync, `Deploy.ffs_gui`)
Compare, check the preview (section 3.1), Synchronize. Then on the server confirm the files arrived (read-only):
```
ls ~/login/deploy ~/riffbox/deploy ~/music-share/deploy ~/version-control/deploy
```
You should see `install.sh`, `appkit.sh`, `app.manifest` in each. If FreeFileSync says it cannot replace files in `~/riffbox`, a file there is owned by root:
`doas chown -R me:me ~/riffbox` (only that staging folder).

### Step 2: the site login (new)
```
doas sh ~/login/deploy/install.sh --check
```
Reads: prints what it *would* create (packages, user `_sitelogin`, `/etc/site-auth`, service script, relayd rules). Changes nothing. Read it; anything about files you do not expect: stop.
```
doas sh ~/login/deploy/install.sh
```
It installs the packages if missing, makes the user and folders, **asks for your one passphrase** (15 characters or more; it is stored only as a salted hash), and asks **y** before adding `/login` and `/private` routes
to `/etc/relayd.conf` (it validates with `relayd -n` first and keeps `/etc/relayd.conf.pre-sitelogin`). It ends with `PASS: Site login answers on 127.0.0.1:8099`.
Then from your computer: `powershell -ExecutionPolicy Bypass -File tools\gate-test-login.ps1 -Domain sanjaysubramanian.com` (personal-site ZIP). All lines should say PASS (it makes one wrong sign-in on purpose).
**Good state:** `https://sanjaysubramanian.com/login` shows the sign-in form; `/private/index.html` now needs the cookie login instead of the browser's password popup (the old htpasswd rule is still on the server, unused, until you remove it).

### Step 3: Riffbox (updated code; changes nothing about how you log in yet)
```
doas sh ~/riffbox/deploy/install.sh --check
```
Expected: most things "LEFT ALONE"; `relayd.conf already has rules for <riffbox> that this installer did not write: untouched` (normal: your rules were hand-written); the service script "same settings"; and under "5b. Site login" a line saying
it would register riffbox and write its key. Nothing else. Then:
```
doas sh ~/riffbox/deploy/install.sh
```
It copies the new code, registers riffbox with the login (writes `/etc/site-auth/keys/riffbox.key`, readable only by `_riffbox`), and **restarts riffbox** (a few seconds without service: do it when you are not mid-listen). Ends with `PASS: Riffbox answers on 127.0.0.1:8100`.
Check: you are still logged in or can log in with the old passphrase; upload from the iPhone Shortcut once (unchanged).
**Optional move to the single login** (do it later, any time; section 6): `RIFFBOX_AUTH=both` then `site` in `/etc/riffbox.conf`.

### Step 4: music-share (new)
```
doas sh ~/music-share/deploy/install.sh --check
doas sh ~/music-share/deploy/install.sh
```
Same pattern: packages, user `_musicshare`, folders `/var/music-share`, `/var/music-share-backup`, `/var/music-share-restore`, `/etc/musicshare.conf`, service on port 8101, registers its own key, asks **y** for the `/music` routes. Ends with `PASS: Music share answers on 127.0.0.1:8101`.
Check in a browser: `https://sanjaysubramanian.com/music/` (public, empty), `/music/studio` sends you to `/login`, sign in, drop a track, copy its link and open it in a private window (no login needed).

### Step 5: the storage volume, then Version Control
Version Control refuses to install until the volume is mounted. **Do the storage steps first**, from `version-control\docs\STORAGE.md` (also summarised in `RESTORE.html` B3). They include **one destructive step** that erases the old encrypted volume; the doc has a "STOP and decide" point
after you have copied anything you need off `/mnt`. Do not continue past that point until you say you are sure. When the volume is mounted at `/var/version-control` and `.volume-ok` exists:
```
doas sh ~/version-control/deploy/install.sh --check
doas sh ~/version-control/deploy/install.sh
```
Ends with `PASS: Version Control answers on 127.0.0.1:8102`. Check: `/version-control/` sends you to `/login`; sign in; New song; upload two versions; create a link; open it in a private window and try switching, a loop and a comment.
Then the **reboot rehearsal** (the only way to prove the volume and all four services come back by themselves): `doas reboot`, wait a minute, ssh back in, and run `df -h` (volume mounted), `rcctl ls started` (login, riffbox, musicshare, versioncontrol listed), and open the sites.

### Step 6: confirm from outside, then set up the backup pulls
- `https://sanjaysubramanian.com/login`, `/music/health`, `/version-control/health`, `/ideas/health` each answer.
- Run the new Pull jobs once (section 3.2) after pressing **Back up now** in each app.

## 5. If something goes wrong
| Problem | What to do |
|---|---|
| An installer says `STOP: ...` | it changed nothing past that line; read the message, tell me what it says |
| relayd rejected the file | the installer already refused to copy it; the live `relayd.conf` is untouched |
| You want an app's routes gone | there is **no automatic uninstall yet** (I can write one). By hand: `doas rcctl stop <name>; doas rcctl disable <name>`, then `doas vi /etc/relayd.conf`, delete the lines between each `# BEGIN app:<name>` and `# END app:<name>` (three small blocks), `doas relayd -n -f /etc/relayd.conf && doas rcctl reload relayd`. Data folders are never touched. Names: `sitelogin`, `musicshare`, `versioncontrol`. |
| Everything about riffbox must go back | `doas cp -p /etc/relayd.conf.pre-multiapp /etc/relayd.conf` (only if you have not made other relayd changes since), re-upload your old riffbox folder, `doas sh ~/riffbox/deploy/install.sh --app-files-only` |
| Boot stops after the volume step | in the Vultr console restore `/etc/fstab.pre-volume` (made in the storage steps) |
| Locked out of a login | `doas rcctl restart sitelogin` clears the in-memory attempt limits |

## 6. Moving riffbox to the single login (later, whenever you like)
1. `doas vi /etc/riffbox.conf`, add the line `RIFFBOX_AUTH=both`, save; `doas rcctl restart riffbox`.
2. Sign in at `https://sanjaysubramanian.com/login?next=/ideas/`; riffbox opens without asking again. Your old riffbox passphrase still works too (that is what `both` means).
3. When you are happy, change the line to `RIFFBOX_AUTH=site` and restart: the old login page is retired and `/ideas/` sends you to `/login`. To go back, set it to `local`.
The iPhone Shortcut token is unaffected in every mode. To log every device out of every app: `doas python3 /usr/local/login/app/siteauth/keys.py rotate --dir /etc/site-auth`.

## 7. Routine updates afterwards
Edit or re-download an app, replace its folder in `server-mirror\home\me\`, run `Deploy.ffs_gui` (check the preview), then on the server `doas sh ~/<app>/deploy/install.sh --app-files-only` (copies code and restarts that app; touches no system file).
Use the full installer (without `--app-files-only`) when a release says the manifest, conf or routes changed.

## 8. Unverified, and what would settle it
- FreeFileSync: per-pair filter location, wildcard syntax, the Custom sync direction labels. Settled by the preview.
- SFTP permissions to the new backup/restore folders (3.2, 3.3). Settled by the first Compare.
- `useradd`, `rcctl`, `relayd -n`, `fstab`/`disklabel` on OpenBSD 7.9. Settled by each installer's `--check` and the reboot rehearsal.
- The browser behaviours (cookies set for sibling paths, iPhone Safari playback) are checked by the gate script and by you listening; see each app's README.
