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
| `REQUIRE_MOUNT` | no | | a path that must be a separately mounted volume containing `.volume-ok`, else the installer stops before creating anything |
| `SITE_AUTH` | no | `0` | `1` = register with the site login and write this app's own key (`AUTH_COOKIE_PATH`, default `BASE_PATH`) |
| `MARK` | no | `app:NAME` | label inside the `# BEGIN/# END` markers of the relayd block |
| `RC_FLAGS`, `DAEMON`, `THREADS`, `RC_EXECDIR` | no | waitress on `127.0.0.1:PORT` | the rc.d script's settings |
| hooks (`deploy/hooks.sh`) | no | | `app_create_conf` (print a conf file), `app_repair_conf`, `app_before_site_auth` |

Flags: `--check` (change nothing), default (create what is missing), `--repair` (fix what exists, asking), `--app-files-only`, `--yes`.
Tested by `sh kit/appkit/test/test-appkit.sh`, under both `dash` and `bash`.
