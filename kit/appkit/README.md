# appkit: the parameterized installer

An app's `deploy/install.sh` is three lines (see any app's folder); `deploy/app.manifest` holds what differs. Plain `KEY=value` lines,
sourced by the shell: **quote any value with spaces** (`TITLE="Site login"`).

| Key | Required | Default | Meaning |
|---|---|---|---|
| `NAME` | yes | | lowercase letters, digits, hyphens; folder names, labels |
| `UNIXNAME` | yes | | lowercase letters and digits only; service user is `_<UNIXNAME>`, rc.d script `<UNIXNAME>`, relayd table `<UNIXNAME>` |
| `BASE_PATH` | yes | | the URL prefix, e.g. `/music` |
| `PORT` | yes | | 1024-65535, on 127.0.0.1; refused if another app or relayd rule uses it |
| `TITLE` | no | `NAME` | human name |
| `PKGS` | no | `py3-flask py3-waitress` | OpenBSD packages (installed only if missing) |
| `CODE_DIR` | no | `/usr/local/NAME` | where code is copied (rsync, add/update/delete only here) |
| `SYNC` | no | `app static deploy` | folders of the upload copied into `CODE_DIR` |
| `SRC_MARKER` | no | `app/wsgi.py` | files that must exist in the upload (sanity check) |
| `DIRS` | no | | `path,owner,group,mode` entries; owner/group may be `@svc` (service user) or `@login` (you) |
| `CONF_FILE`, `CONF_LINES` | no | `/etc/UNIXNAME.conf` | created once, mode 640 root:`_UNIXNAME`, never overwritten; `@HEX32@` becomes a random 64-hex secret |
| `ROUTES` | no | `BASE_PATH` | URL prefixes relayd sends to this app (each as `/x` and `/x/*`) |
| `HEALTH_PATH` | no | `BASE_PATH/health` | must answer JSON containing `"ok"` |
| `REQUIRE_MOUNT` | no | | a path that must be a separately mounted volume containing `.volume-ok`: the installer stops before creating anything if not, **and the service script gets an `rc_pre` guard** so the service refuses to start (instead of filling the boot disk) when the volume is not mounted |
| `SITE_AUTH` | no | `0` | `1` = register with the site login and write this app's own key (`AUTH_COOKIE_PATH`, default `BASE_PATH`) |
| `MARK` | no | `app:NAME` | label inside the `# BEGIN/# END` markers of the relayd block |
| `RC_FLAGS`, `DAEMON`, `THREADS`, `RC_EXECDIR` | no | waitress on `127.0.0.1:PORT` | the rc.d script's settings |
| hooks (`deploy/hooks.sh`) | no | | `app_create_conf` (print a conf file), `app_repair_conf`, `app_before_site_auth` |

Flags: `--check` (change nothing), default (create what is missing), `--repair` (fix what exists, asking), `--app-files-only`, `--yes`.
Tested by `sh kit/appkit/test/test-appkit.sh`, under both `dash` and `bash`.

## Data on a separate volume (the convention for every app)
Program files, the service script, the conf file and the service user live on the boot disk and are rebuilt by the installer; **all data lives on the volume**,
so after a wipe you reinstall and point at the preserved data. The manifest is sourced as shell, so define the root once and build the paths from it:
```
DATA_ROOT=/mnt/data
REQUIRE_MOUNT=$DATA_ROOT
SVC_HOME=/var/empty
DIRS="$DATA_ROOT/NAME/data,@svc,@svc,750 $DATA_ROOT/NAME/backup,@svc,@svc,755 $DATA_ROOT/NAME/restore,@login,@login,755"
CONF_LINES="NAME_DATA_DIR=$DATA_ROOT/NAME/data
..."
```
Keep `data` and `backup` on the **same filesystem** if an app hard-links backups to save space (Version Control does). `DATA_ROOT` may differ per app (a second volume at `/mnt/data2`).
- **Rebuilds and uids:** files belong to a *number*. When the service user is created and a folder in `DIRS` owned by `@svc` already exists (uid/gid 500 or higher), the user and group are
  created with that folder's uid/gid (stops with a message if the number is taken by another account). If the user exists with a different uid than its data, the installer says so and changes nothing.
- The installer never deletes data and never runs `chown -R` on it.
- `ti.sh` (Tech Independence) never touches `/mnt`, `/etc/fstab`, `/etc/rc.d/<app>`, `/etc/<app>.conf` or an app's relayd block; see `RESTORE.html` for the two markers (`storageno`, `webok`) that keep it that way.
