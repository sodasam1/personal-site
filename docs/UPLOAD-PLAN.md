# One-step uploads with FreeFileSync (you build it by hand; this is the plan)

Goal: after editing, **double-click one saved job, look at the preview, press Synchronize**, and everything that changed is on the server. And the
folders on your computer **mirror the server's folders**, so you can see at a glance where each thing lands.

Everything here is about moving files. The one thing a file transfer cannot do is run a command as root, so after a Riffbox *code* change there is
still one command (section 6 shows how to make FreeFileSync run it for you).

## 1. Where everything goes on the server

| # | Goes to (server) | What it is | Direction | Sync mode | How often |
|---|---|---|---|---|---|
| A | `/var/www/htdocs` | your public pages, `pub/`, and `private/` pages | up | **Update** | every site edit |
| B | `/home/me/install.sh` | the site kit's one-file installer | up | Update | rarely (when it changes) |
| C | `/home/me/riffbox/` | the Riffbox folder (`app/`, `static/`, `deploy/`); its installer copies it into place | up | **Update** | every Riffbox update |
| D | `/var/riffbox-backup` | the Riffbox backup (made by the **Back up now** button or `backup.py`; a nightly schedule is a planned feature, not installed) | **down** (server to computer) | Update, right to left | after each backup you make |
| E | `/var/riffbox-restore` | the drop folder for Riffbox data restore | up | Update | only after a wipe |

`me` is your server login. `/var/riffbox-backup` and `/var/riffbox-restore` are created by Riffbox's installer (branch `one-file-installer`).
Your login can write A, B, C and E and can read D, so FreeFileSync needs no root.

## 2. The folder tree on your computer (mirrors the server's absolute paths)

Make one parent folder, for example `C:\Users\YOU\server-mirror\`, and inside it the same paths the server has:

```
server-mirror\
  var\
    www\
      htdocs\                  <- A. copy of personal-site's htdocs\   (index.html, style.css, pub\, private\ ...)
    riffbox-backup\            <- D. pulled backups land here (nothing of yours is ever put in it)
    riffbox-restore\           <- E. leave empty; fill only for a restore
  home\
    me\
      install.sh               <- B. from personal-site's server\install.sh
      riffbox\                 <- C. the riffbox ZIP from GitHub, unpacked and renamed to "riffbox"
        app\  static\  deploy\
```
Reading `server-mirror\var\www\htdocs` is reading `/var/www/htdocs`. If a path looks wrong on screen, it is wrong on the server.

**Keeping it fresh** (by hand, a few minutes): download the `personal-site` ZIP from GitHub, copy its `htdocs\` over `server-mirror\var\www\htdocs\` and
`server\install.sh` to `server-mirror\home\me\install.sh`. Download the `riffbox` ZIP, delete the old `riffbox\` folder in `home\me\`, and put the new
one there. Use the ZIP, not `git clone`, so Windows keeps Unix line endings in `install.sh` (the repos also force LF).

## 3. Build the jobs

FreeFileSync lets **each folder pair have its own settings**, and lets you switch a pair off temporarily. That is what makes one job possible.
(Menu names below are from memory of FreeFileSync and may differ slightly in your version; the ideas are what matters.)

### Job 1: Deploy.ffs_gui (the one you run all the time): pairs A, B, C
For every pair, the **left** side is the folder in `server-mirror`, the **right** side is the same path on the server through the SFTP connection you
already use (host `sanjaysubramanian.com`, your key file, your login). Build the first pair as you do now, then for each further pair copy the right-hand
connection and change only the path at the end.

| Pair | Left (computer) | Right (server) | Synchronization | Filter (Exclude) |
|---|---|---|---|---|
| A | `server-mirror\var\www\htdocs` | `/var/www/htdocs` | Update | `*sync.ffs_db` and `*.bak` |
| B+C | `server-mirror\home\me` | `/home/me` | Update, with an **Include** filter | include only: `install.sh` and `riffbox\*`; exclude: `riffbox\tests\*`, `riffbox\docs\*`, `riffbox\archive\*`, `*.git*`, `*__pycache__*` |

- **Update** copies new and changed files from left to right and **never deletes** anything on the server. Why: your server's `htdocs` has files that are
  not on your computer (the `sync.ffs_db` bookkeeping, `Tour Watch.html`); Mirror would delete them. TI's page uses Mirror once your computer holds the
  complete site; switch pair A to Mirror only on purpose, after you have looked at the preview and seen that nothing you want to keep would go.
- **Pair B+C uses an Include filter on purpose.** The right side is your whole home folder. Anything not named in the filter is ignored, so a mistake
  cannot touch Maildir, `.ssh` or anything else. **Never use Mirror on this pair.**
- Why B and C share a pair: both live under `/home/me`, and one pair with a filter is simpler than two.

Save as `Deploy.ffs_gui` (File, Save as...). Double-click it to open it ready to go, press **Compare**, read what will change (nothing outside the three places
should appear), then **Synchronize**. First run: expect "create" for everything you do not already have on the server.

### Job 2: Pull-backup.ffs_gui: pair D (server to computer)
| Left (computer) | Right (server) | Synchronization |
|---|---|---|
| `server-mirror\var\riffbox-backup` | `/var/riffbox-backup` | **Custom**: new items on the right copy to the left; items only on the left: do nothing; changed items: copy right to left; never delete |

Why separate: it runs the other direction and on a different schedule, and a mix-up here is the dangerous one (a pull that goes the wrong way would
overwrite or delete the backup). A backup on the same VPS does not survive losing the VPS, so this job is what actually protects your recordings.

### Job 3: Restore.ffs_gui: pair E (only after a wipe)
| Left | Right | Synchronization |
|---|---|---|
| `server-mirror\var\riffbox-restore` (put your pulled backup folder inside it) | `/var/riffbox-restore` | Update |

Then open Riffbox, Backup and export, **Restoring**, press the button (branch `in-app-restore`).

### Optional: one master job
If you prefer one file: put pairs A, B+C, D and E in one job. Use the checkbox on each pair to switch off D and E for everyday runs.
I recommend the three small jobs instead: a job that can pull and push in one click has more ways to go wrong.

## 4. A rebuild after a wipe
1. Tech Independence. 2. Run **Deploy** (A, B, C). 3. On the server, the installers: `doas sh ~/install.sh` (the kit) and
`doas sh ~/riffbox/deploy/install.sh` (Riffbox). 4. Run **Restore**. 5. Press Restore in Riffbox. The backup comes from your last **Pull-backup**,
so make a backup (Back up now) and run it regularly.

## 5. Safety rules
- If FreeFileSync reports it cannot delete or replace files in `/home/me/riffbox`, a file there is owned by root. Fix once on the server: `doas chown -R me:me ~/riffbox` (only that staging folder). Cause and permanent fix: riffbox branch `clean-upload-folder`.
- Read the **Compare** preview every time. A surprising "delete" or a file you do not recognise: stop.
- `Update` everywhere; `Mirror` only for pair A and only on purpose. Never on `/home/me`, `/var`, `/` or `/usr`.
- Never put anything of yours in `server-mirror\var\riffbox-backup`.
- Passwords, tokens and the password hash are not in these folders and must not be added.

## 6. Optional: make the upload also run the Riffbox installer
After a Riffbox code change the new files must be copied into place and the service restarted: that is `doas sh ~/riffbox/deploy/install.sh`, which needs
root, so a file transfer cannot do it. FreeFileSync can run a command on your computer after a synchronization (a setting in Synchronization settings,
"run a command after sync"). Setting it to
`ssh me@sanjaysubramanian.com doas sh /home/me/riffbox/deploy/install.sh`
runs the installer on the server over SSH (Windows 10 and later include `ssh`; `doas` has no password for your login, `permit nopass me`). Routine runs need
no questions; only a first install asks for a passphrase, and that needs `ssh -t`. I have not verified the exact setting or that the free edition of
FreeFileSync offers it; do it by hand until you have checked.

## 7. Unverified
FreeFileSync menu names, per-pair settings, and the post-sync command in your edition and version; whether `.ffs_gui` is all you need (batch jobs may be
a donation-edition feature); SFTP writing to `/home/me` and `/var/www/htdocs` as your login (it works for `htdocs` today); that your login can read
`/var/riffbox-backup` (the Riffbox installer makes it world-readable).
