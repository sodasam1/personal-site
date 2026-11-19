# The data volume: plain 100 GB Vultr block storage for every app's data and /pub/

Status: **written from `ti.sh`, the appkit installer and the plan; the OpenBSD commands below could not be run by the author. Every
command that changes something says so. Read-only steps first; anything marked UNVERIFIED is a guess to be confirmed on your server.**
Decision (yours): unencrypted, 100 GB, on Vultr. Program files stay on the boot disk; **all data lives on this volume**, so after a wiped
server you reinstall the programs and point them at the preserved data.

## What goes where
The top level of `/mnt/data` holds only three things: `apps/` (one folder per app, so a new app never adds clutter at the top), `_server/` (notes) and the `.volume-ok` marker.
| What | Where | Survives a wipe? | Rebuilt by |
|---|---|---|---|
| Program files, service script, relayd routes, packages, `/etc/<app>.conf`, service user `_<app>` | boot disk | no | the app's installer |
| Live data (database, audio, scratch) | `/mnt/data/apps/<app>/data` | **yes** | nothing: the installer points at it |
| Backups | `/mnt/data/apps/<app>/backup` | yes (still pull them to your computer) | nothing |
| Restore drop folder | `/mnt/data/apps/<app>/restore` | yes | nothing |
| Public files | their own partition, mounted at `/var/www/htdocs/pub` | yes | an fstab line |
| Notes for rebuild day (fstab lines, DUID, layout; **no secrets**) | `/mnt/data/_server/README` | yes | you |
Secrets (`/etc/<app>.conf`, the site login keys) stay on the boot disk: the volume is unencrypted. After a wipe the installers ask again
for the passphrase and the phone upload token (keep both in your password manager).
**Why a separate service user?** Each app runs as its own no-login account (`_riffbox`, `_musicshare`, `_versioncontrol`). `ti.sh` gives *your* login
`doas` with no password, so an app running as you would be effectively root. As its own user it can only touch its own data (folders `750`), and
other apps and the web server (`www`) cannot read it. Files belong to a **number** (uid), so on a rebuild the installer creates the user with
the uid/gid of the data already on the volume (appkit does this when the app's data folder exists and is owned by a uid of 500 or more).

## Why two partitions, in this order (decide before you format: the disk is blank now, so this is free today)
- `httpd` is locked inside `/var/www` and OpenBSD has no bind mount (check `man mount_null`), so `/pub/` cannot be a symlink into `/mnt`. It needs its own
  mount **inside** `/var/www`: partition `d`, mounted at `/var/www/htdocs/pub`.
- Only the **last** partition on a disk can grow. So: `d` (public files, small and fixed) comes **first on the disk**; `a` (all app data) comes **last** and takes the rest.
  Partition letters need not follow position.
- Chosen sizes for the 100 GB volume: `d` = 25 GB (`/pub/`), `a` = 75 GB (all app data). (`du -sh /var/www/htdocs/pub` shows what you have now.) `pub` cannot grow without moving data, so be generous.
- Mount by **DUID** (the disk's permanent name) so `sd1`/`sd2` renumbering never breaks a mount.
- Do not leave an unallocated gap at the end; give the last partition everything.
- Alternative with no split: one partition at `/var/www/data` with `pub` as a relative symlink or a changed `location "/pub/*"` root in `httpd.conf`. Growth is trivial but
  `httpd` may refuse a symlink that leaves its root (UNVERIFIED) and it edits `ti.sh`'s `httpd.conf`. Not recommended unless `pub` will be large.

## 0. Before anything: protect against `ti.sh` and look around
`ti.sh` is only safe to re-run (you need it for email) if two marker files exist. Check, then take a baseline of the files that matter:
```
doas ls /root/my          # must list: storageno  webok   (storageok may be there too)
mkdir -p ~/pre-ti && for f in relayd.conf httpd.conf pf.conf doas.conf fstab rc.conf.local passwd group; do cp -p /etc/$f ~/pre-ti/; done
```
Why: without `storageno`, `ti.sh` runs `disklabel`/`bioctl` on `sd1` (it would encrypt a blank volume, or wait forever for an upload on a formatted one). Without `webok`,
it copies its own `relayd.conf`/`httpd.conf` over `/etc` and **erases your `/ideas` and `/music` routes**. Nothing else in `ti.sh` touches `/etc/fstab`, `/mnt`, `/usr/local/<app>`, `/etc/rc.d/<app>`
or `/etc/<app>.conf`. If `webok` is missing, do not run `ti.sh`. After the run, `diff ~/pre-ti/<file> /etc/<file>` for each file: only mail-related differences are expected.

## 1. Clean up what the encrypted volume left (changes: removes two helper scripts, adds a marker)
```
mount | grep mnt; doas bioctl softraid0; ls -l /usr/local/sbin/m /usr/local/sbin/m-x; grep -n 'sd[0-9]' /etc/fstab; doas crontab -l      # look first
doas umount /mnt; doas bioctl -d sd2        # only if the look-first commands showed a mounted /mnt or a softraid sd2 (a reboot also clears it)
doas rm /usr/local/sbin/m /usr/local/sbin/m-x
doas sh -c 'touch /root/my/storageno; rm -f /root/my/storageok'
```
`/mnt` itself stays (it is OpenBSD's own empty folder).

## 2. Attach, identify, label, format (the one destructive part: it erases the volume's contents)
1. Vultr: the 100 GB volume attached to this server, **same region**. Reboot (OpenBSD only looks for disks at boot; `ti.sh` did the same).
2. Identify the disk: `sysctl hw.disknames` and `doas disklabel sd1`. It must be the new, empty 100 GB disk (zero `duid: 0000000000000000`, no partitions, size about 100 GB). **Stop here if not.**
   (If your root disk is `sd0` the new one is normally `sd1`; adjust every `sd1` below if it is not.)
3. Open the Vultr "View Console" in case a bad `fstab` line stops boot; restore with `cp /etc/fstab.pre-volume /etc/fstab` (made below).
4. Label: `doas disklabel -E sd1`, then at its prompt: `a d` (offset: press Enter to accept the default, normally 64 (if it offers 0, type 64); size: `25G`; FS type: `4.2BSD`), `a a` (offset: Enter; size: Enter, the default is all remaining space; FS type: `4.2BSD`), `p` to check (`d` near the start, `a` after it reaching the end), `w`, `q`. Nothing is written until `w`.
5. `doas newfs sd1a && doas newfs sd1d`
6. `doas disklabel sd1 | grep duid`  (a 16-hex-digit name; write it in your notes)
7. `doas cp /etc/fstab /etc/fstab.pre-volume`, then (replace DUID):
```
printf '%s.a /mnt/data ffs rw,nodev,nosuid,noexec,softdep 1 2\n%s.d /var/www/htdocs/pub ffs rw,nodev,nosuid,softdep 1 2\n' DUID DUID | doas tee -a /etc/fstab
doas mkdir -p /mnt/data && doas mount /mnt/data
doas touch /mnt/data/.volume-ok && doas mkdir -p /mnt/data/_server
df -h /mnt/data /var        # /mnt/data on sd1a, /var on another device
```
Save the two fstab lines, the DUID and the date in `/mnt/data/_server/README`. `noexec` means nothing can be run from the data partition (UNVERIFIED that no app needs it: none should; remove it if one does).
**Boot risk:** an fstab entry for a disk that is not attached stops `fsck` and drops boot to a single-user prompt; recover via the Vultr console. The service guard (below) protects the apps either way.

## 3. /pub/ onto its partition
Confirmed on your server (11/2026): `httpd.conf` has no `chroot` line (so `/var/www` is the default chroot) and no `root` override, so `/pub/` is `/var/www/htdocs/pub`, and `/` and `/usr/local` are the only mounted partitions (`/var` is on `/`). No `httpd.conf` edit is needed.
Look first: `cat /etc/httpd.conf; ls -ld /var/www /var/www/htdocs /var/www/htdocs/pub; ls -l /var/www/htdocs/pub; du -sh /var/www/htdocs/pub`.
A mount hides what is underneath, so save the files first:
```
doas rsync -a /var/www/htdocs/pub/ ~/pub-old/
doas mount /var/www/htdocs/pub
doas rsync -a ~/pub-old/ /var/www/htdocs/pub/
doas chown YOURUSER:YOURUSER /var/www/htdocs/pub          # ti.sh made pub yours; a fresh filesystem root is root:wheel
```
Check `https://YOURDOMAIN/pub/` loads and lists your files, upload one with rsync/FreeFileSync as your user, reboot, check again. Delete `~/pub-old` only after that.
(`ti.sh` does not touch `/pub/` again once `webok` exists. Do not move `/var/www/acme` or `index.html` onto the volume.)

## 4. Apps: move each one's data (after its updated folder is uploaded)
The installers refuse to run, and the services refuse to start, unless `/mnt/data` is mounted and holds `.volume-ok`.
For an app that already runs on the boot disk (Riffbox, music-share), per app (shown for Riffbox):
```
doas sh ~/riffbox/deploy/install.sh --check              # read what it would do
doas sh ~/riffbox/deploy/install.sh                      # creates /mnt/data/apps/riffbox/{data,backup,restore}; relayd and conf left alone
doas rcctl stop riffbox
doas rsync -a /var/riffbox/ /mnt/data/apps/riffbox/data/
doas rsync -a /var/riffbox-backup/ /mnt/data/apps/riffbox/backup/
doas rsync -a /var/riffbox-restore/ /mnt/data/apps/riffbox/restore/ 2>/dev/null
doas sh ~/riffbox/deploy/install.sh --repair             # offers to repoint the three conf lines (data only once riffbox.db is on the volume); answer y
doas rcctl restart riffbox; curl -s http://127.0.0.1:8100/ideas/health
```
Then play an old recording, press Back up now, and keep the old `/var/riffbox*` folders (renamed `.old`) for a week before deleting. `rsync -a` keeps the numeric owner, so the app's
existing uid still owns the data. A brand-new app (Version Control) needs only its installer (`--check`, then without).

## 5. Expanding later
Two ways; the layout above supports both. **Rehearse one while the volume is still empty.**
1. **Grow in place.** Vultr volumes can only grow, never shrink (Vultr docs). Stop the apps, unmount `/mnt/data`, resize the volume in the Vultr console, reboot if `doas disklabel sd1`
   still shows the old size (one source says expansion needs a reboot), then `doas disklabel -E sd1` and enlarge partition `a` (the last one) to the new end, `w`, `q`, `doas growfs /dev/rsd1a`,
   `doas fsck -f /dev/rsd1a`, `doas mount /mnt/data`, `df -h /mnt/data`. **UNVERIFIED on OpenBSD + Vultr:** whether `disklabel -E` accepts the larger size on a disk without MBR/GPT
   (it may need its `b` boundaries command), whether `growfs` needs the filesystem unmounted, and whether Vultr lets you resize without detaching. Vultr's docs name only FreeBSD, Linux and Windows for formatting and mounting.
   Write what actually happened here when you have done it.
2. **Add a second volume.** Attach another Vultr volume (`sd2`), `disklabel -E`, `newfs`, an fstab line by DUID, mount at `/mnt/data2`, `touch /mnt/data2/.volume-ok`. Move one app by setting `DATA_ROOT=/mnt/data2` in its
   `deploy/app.manifest`, copying its folder, `install.sh --repair`. No resize risk; on a rebuild you re-attach two volumes. Version Control (audio-heavy) is the natural tenant.

## 6. After a wiped server (the volume still holds your data)
**Do not run `disklabel -E` or `newfs` again.** See `RESTORE.html`, section B3, for the full order. In short: answer **n** to `ti.sh`'s storage question (or `mkdir -p /root/my && touch /root/my/storageno`
before running it); finish `ti.sh`; attach the volume, reboot, `doas disklabel sd1 | grep duid` (it equals the DUID in `/mnt/data/_server/README`), re-add the two fstab lines, `doas mkdir -p /mnt/data && doas mount -a`,
check `.volume-ok` and `/pub/`; then run each app's installer (`--check`, then for real): it creates the service user with the uid of the existing data folders, and starts pointing at `/mnt/data/apps/<app>/...`.
What still lives only on the boot disk and is lost: mail (`~/Maildir`), Radicale contacts/calendar (`radbak` copies into your home, the same disk), SSH host keys, secrets. Pull backups to your computer as before
(`/mnt/data/apps/*/backup`, and `/var/www/htdocs/pub`): a backup on the same volume does not protect against losing the volume.
