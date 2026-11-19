# One-click uploads with FreeFileSync (replaces your three upload scripts)

> **Layout update (2026-11-19).** The app install folders now live under `/home/me/staging/<app>` (computer: `server-mirror\home\me\staging\<app>`), and each app's backup and restore folders live on the
> data volume at `/mnt/data/apps/<app>/{backup,restore}`. `install.sh` for the site kit stays at `/home/me/install.sh` (pair B). Paths below are updated; `docs/UPLOAD-INSTALL-PLAN.md` extends this plan to all apps.

Goal: **one saved FreeFileSync job, one double-click, everything that changed is on the server**, and the folders on your computer **have the same
layout as the server's**, so reading a path on your screen tells you where the file lives on the website.

FreeFileSync only moves files. The one thing it cannot do is run a command as root, so after a Riffbox *code* change a single command must still run on the
server. Section 5 makes FreeFileSync run it for you as the last step of the same click.

## 1. What you have today and what replaces it

| Today (3 scripts) | Server destination | Replaced by |
|---|---|---|
| htdocs script | `/var/www/htdocs` | pair **A** |
| "server" script (the installer) | `/home/me/install.sh` | pair **B** |
| Riffbox script | `/home/me/staging/riffbox/` | pair **C** |

One job, three folder pairs. A pair is "this folder on my computer <-> that folder on the server". FreeFileSync lets **each pair have its own settings**
(Update vs Mirror, filters), and syncs all pairs in one run. That is why one job can replace three scripts.

Why still three pairs and not one: the server's files live in two unrelated places (`/var/www/...` and `/home/me/...`), and a pair is one folder to one
folder. Pointing one pair at `/` (everything) would make FreeFileSync read the whole server and gives a typo room to touch system files. Three small,
named pairs are the safe version.

## 2. Make the computer's folders match the server's

Make one parent folder, for example `C:\Users\YOU\server-mirror\`, and inside it **the same paths the server has**:

```
server-mirror\                       <- stands for "/" on the server
  var\
    www\
      htdocs\                        <- A. the public site (index.html, style.css, pub\, private\ ...)   = /var/www/htdocs
  mnt\data\apps\riffbox\
    backup\                          <- D. pulled backups arrive here (never put your own files in it)    = /mnt/data/apps/riffbox/backup
  home\
    me\                              <- your server login's home folder                                  = /home/me
      install.sh                     <- B. the site kit's installer                                       = /home/me/install.sh
      staging\
        riffbox\                     <- C. the Riffbox folder, named exactly "riffbox"                    = /home/me/staging/riffbox
          app\  static\  deploy\
```

Rule to remember: **delete `server-mirror` from the front of any path on your screen and you have the server path.**
`server-mirror\home\me\staging\riffbox\deploy\install.sh` is `/home/me/staging/riffbox/deploy/install.sh`.

Where the content comes from: your two GitHub repos. To refresh, download each as a ZIP and copy:

| From the ZIP | Copy to |
|---|---|
| `personal-site\htdocs\` (contents) | `server-mirror\var\www\htdocs\` |
| `personal-site\server\install.sh` | `server-mirror\home\me\install.sh` |
| `riffbox\` (the whole folder; delete the old `riffbox` folder in `home\me\staging\` first) | `server-mirror\home\me\staging\riffbox\` |

(ZIP, not `git clone`, so Windows does not rewrite line endings in `install.sh`; the repos also force LF.)

Optional improvement, no new software: since FreeFileSync can sync any two folders, a **fourth, local-only job** can copy from your unpacked ZIP folders into
`server-mirror` (Update). Not needed; do it only if the copying annoys you.

## 3. Build the job (once)

Menu names are from memory of FreeFileSync and can differ slightly in your version; the ideas are what matters.

1. Open FreeFileSync. Make the **first pair** the way you do now: left = `server-mirror\var\www\htdocs`, right = the SFTP connection you already use
   (host `sanjaysubramanian.com`, your key file, user `me`) with path `/var/www/htdocs`.
2. Add the other two pairs (the "+" next to the folder row, or "Add folder pair"). For each, set the right side the same way and change only the path.
   For the SFTP login, copy the right-hand field of pair A and edit the path at the end.
3. Give **each pair** its own settings (the small gear icon on the pair, "Local synchronization settings" / "Local filter"):

| Pair | Left (computer) | Right (server) | Variant | Filter |
|---|---|---|---|---|
| A | `server-mirror\var\www\htdocs` | `/var/www/htdocs` | **Update** | Exclude: `*sync.ffs_db`, `*.bak` |
| B | `server-mirror\home\me` | `/home/me` | **Update** | Include: `install.sh` only |
| C | `server-mirror\home\me\staging\riffbox` | `/home/me/staging/riffbox` | **Update** | Exclude: `tests\*`, `docs\*`, `archive\*`, `*.git*`, `*__pycache__*` |

Pair B points at your whole home folder, so its **Include `install.sh`** filter is what keeps it from ever touching `.ssh`, `Maildir` or anything else. Do not
skip it. Never use **Mirror** on pair B. (If your FreeFileSync wants one filter per pair and the Include filter looks odd on B, an equivalent is to make B's
left folder a tiny folder that holds only `install.sh` and point it at `/home/me`; the result is the same.)

Why **Update** everywhere: Update copies new and changed files from your computer to the server and **never deletes** anything on the server. Your server's
`htdocs` has files that are not on your computer, and Mirror would delete them. Switch pair A to **Mirror** only on purpose, after you have read the preview and
nothing you want to keep is listed for deletion. Because nothing in this job can delete, it is safe to run without reading every line, but see section 4.

4. **Save it** as `Deploy.ffs_batch` (File, "Save as batch job"). A batch job runs the whole thing when you double-click it. If you want to look at the
   preview before anything is copied, also save a `Deploy.ffs_gui` copy (File, "Save as"); double-click that one to review, press **Compare**, then **Synchronize**.
   Suggestion: use the `.ffs_gui` for the first few weeks, then the `.ffs_batch` when you trust it.

## 4. Your routine

1. Edit or refresh files in `server-mirror` (section 2).
2. Double-click `Deploy.ffs_batch` (or `.ffs_gui` and press Synchronize). Done: pages are live at once.
3. Riffbox code changes need the restart. If you did section 5, that already happened. Otherwise run on the server: `doas sh ~/staging/riffbox/deploy/install.sh --app-files-only`.

Check in the result window that only files you expected were copied, and that there are no errors.

## 5. Optional: make the same click run the installer (and so restart Riffbox)

FreeFileSync can run a command on your computer after a successful synchronization (Synchronization settings, "run a command after synchronization";
the box has a free-text command line). Use:

```
ssh me@sanjaysubramanian.com "doas sh /home/me/staging/riffbox/deploy/install.sh --app-files-only"
```

What each part does: `ssh me@sanjaysubramanian.com` opens a login to your server (Windows 10 and later include `ssh`); the quoted text is the command it runs there;
`doas` runs it as root (your login has `permit nopass me`, so it asks nothing); `--app-files-only` copies only Riffbox's code into place and restarts it, and touches no system
file. This is safe to run on every upload: the installer says "nothing changed, no restart needed" when the files are identical and then does not restart Riffbox.

Needs your SSH key to work without a prompt (the one FreeFileSync already uses; with a passphrase, load it into the Windows `ssh-agent` or the command will wait for it).
Test the `ssh` line once by itself in PowerShell before putting it in FreeFileSync. I have not verified the exact setting name or that your edition offers it; if it does not,
step 3 of section 4 is one command.

## 6. The other two jobs (different direction, so kept separate on purpose)

### Pull-backup.ffs_gui (server to computer; pair D)
| Left (computer) | Right (server) | Variant |
|---|---|---|
| `server-mirror\mnt\data\apps\riffbox\backup` | `/mnt/data/apps/riffbox/backup` | **Custom**: new items on the right copy to the left; items only on the left: do nothing; changed items: right to left; never delete |

A backup on the same VPS does not survive losing the VPS; this job is what protects your recordings. Run it after pressing **Back up now** in Riffbox, and regularly.
It must stay a separate job: a click that can both push and pull has one more way to go wrong, and the wrong way here overwrites the backup.

### Restore.ffs_gui (computer to server; only after a wipe)
| Left | Right | Variant |
|---|---|---|
| `server-mirror\mnt\data\apps\riffbox\restore` (put your pulled backup folder inside it) | `/mnt/data/apps/riffbox/restore` | Update |

Then open Riffbox, Backup and export, **Restoring**, and press the button. Full steps: `RESTORE.html`.

## 7. Rebuild after a wipe (short; `RESTORE.html` has the full explained version)
1. Tech Independence. 2. Run `Deploy` (A, B, C). 3. On the server: `doas sh ~/install.sh` (the kit), then `doas sh ~/staging/riffbox/deploy/install.sh` (Riffbox).
4. Run `Restore`. 5. Press Restore in Riffbox.

## 8. Safety rules
- Read the preview whenever you change a filter or a path. A surprising "delete" or an unknown file: stop.
- `Update` everywhere; `Mirror` only for pair A and only on purpose. Never on `/home/me`, `/var`, `/` or `/usr`.
- If FreeFileSync reports it cannot replace or delete files in `/home/me/staging/riffbox`, a file there is owned by root. One-time fix on the server: `doas chown -R me:me ~/riffbox`.
- Passwords, tokens and the password hash are not in these folders and must not be added.

## 9. Unverified
FreeFileSync menu names and per-pair filter behavior in your version; whether your edition offers batch jobs and the after-sync command; SFTP writing to `/home/me` and
`/var/www/htdocs` as your login (it works for `htdocs` today); that your login can read `/mnt/data/apps/riffbox/backup` (the Riffbox installer makes it world-readable); that `ssh` in
PowerShell connects with your key without a prompt. Nothing here could be run from the build machine.
