#!/bin/sh
# Tests the generic installer (appkit.sh) against copies of REAL config files, no OpenBSD needed.
# Usage: sh kit/appkit/test/test-appkit.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); KIT=$(cd "$HERE/.." && pwd); FIX="$HERE/fixtures"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }
export DOAS_USER=me
unset APPKIT_TEST_ANSWER

# copy an app to a private upload folder and vendor appkit.sh into it, exactly as kit/sync-into.sh does
stage() { cp -R "$HERE/apps/$1" "$W/up-$1"; cp "$KIT/appkit.sh" "$W/up-$1/deploy/appkit.sh"; }
stage alpha; stage beta
A="sh $W/up-alpha/deploy/install.sh"; B="sh $W/up-beta/deploy/install.sh"

# --- fresh Tech Independence server: alpha ------------------------------------------------------------
R="$W/fresh"; mkdir -p "$R/etc"; cp "$FIX/relayd.pristine.conf" "$R/etc/relayd.conf"; cp "$R/etc/relayd.conf" "$R/orig"
export APPKIT_TEST_ROOT="$R"
$A --check > "$R/check.out" && cmp -s "$R/orig" "$R/etc/relayd.conf" && [ ! -e "$R/etc/alpha.conf" ] && [ ! -e "$R/etc/rc.d/alpha" ] && [ ! -d "$R/var" ] && ok "--check changes nothing" || bad "--check wrote something"
grep -q 'WILL CREATE' "$R/check.out" && grep -q 'WILL CHANGE' "$R/check.out" && grep -q '^Summary:' "$R/check.out" && ok "--check lists what it would create and change" || bad "--check summary"
$A > "$R/run0.out"
[ -f "$R/etc/rc.d/alpha" ] && [ -f "$R/etc/alpha.conf" ] && [ -d "$R/var/alpha" ] && ok "new files and folders are created without asking" || bad "creation"
cmp -s "$R/orig" "$R/etc/relayd.conf" && grep -q 'NOT CHANGED' "$R/run0.out" && ok "relayd.conf is not changed without a yes (and says so)" || bad "relayd changed without consent"
$A --yes > "$R/run1.out" || { bad "--yes run failed"; cat "$R/run1.out"; }
for need in '<alpha> { 127.0.0.1 }' 'path "/alpha" forward to <alpha>' 'path "/alpha/\*" forward to <alpha>' 'forward to <alpha> port 8101'; do
  [ "$(grep -c "$need" "$R/etc/relayd.conf")" = 1 ] && ok "relayd has exactly one: $need" || bad "relayd rule count: $need"
done
diff "$R/orig" "$R/etc/relayd.conf" | grep '^<' >/dev/null && bad "an original relayd line changed" || ok "relayd edit is additions only"
awk '/path "\/alpha\/\*"/{a=NR} /quick header "Host"/&&!h{h=NR} END{exit !(a&&h&&a<h)}' "$R/etc/relayd.conf" && ok "path rules sit before the Host rules" || bad "rule order"
grep -q '^# BEGIN app:alpha$' "$R/etc/relayd.conf" && grep -q '^# END app:alpha$' "$R/etc/relayd.conf" && ok "block is fenced by app:alpha markers" || bad "markers"
[ -f "$R/etc/relayd.conf.pre-alpha" ] && cmp -s "$R/etc/relayd.conf.pre-alpha" "$R/orig" && ok "backup equals original" || bad "backup"
grep -q '^ALPHA_SECRET=[0-9a-f]\{64\}$' "$R/etc/alpha.conf" && grep -q '^ALPHA_BASE_PATH=/alpha$' "$R/etc/alpha.conf" && ok "conf has a random 64-hex secret and the manifest's lines" || bad "conf content"
[ "$(stat -c %a "$R/etc/alpha.conf")" = 640 ] && ok "conf mode 640" || bad "conf mode"
grep -q 'daemon_flags="-m waitress --listen=127.0.0.1:8101 --threads=4 wsgi:app"' "$R/etc/rc.d/alpha" && grep -q 'daemon_user="_alpha"' "$R/etc/rc.d/alpha" && grep -q 'daemon_execdir="/usr/local/alpha/app"' "$R/etc/rc.d/alpha" && grep -q 'rc_cmd \$1' "$R/etc/rc.d/alpha" && ok "rc.d script has this app's port, user and folder" || bad "rc.d content"
cp "$R/etc/relayd.conf" "$R/a1"; cp "$R/etc/alpha.conf" "$R/c1"; cp "$R/etc/rc.d/alpha" "$R/r1"; $A --yes >/dev/null
cmp -s "$R/a1" "$R/etc/relayd.conf" && cmp -s "$R/c1" "$R/etc/alpha.conf" && cmp -s "$R/r1" "$R/etc/rc.d/alpha" && ok "second run changes nothing" || bad "not idempotent"

# --- a second app next to the first -------------------------------------------------------------------
cp "$R/etc/relayd.conf" "$R/before-beta"
$B --yes > "$R/runB.out" || { bad "second app run failed"; cat "$R/runB.out"; }
for need in '<alpha> { 127.0.0.1 }' 'forward to <alpha> port 8101' '<betaapp> { 127.0.0.1 }' 'forward to <betaapp> port 8102' 'path "/beta" forward to <betaapp>' 'path "/private/\*" forward to <betaapp>'; do
  [ "$(grep -c "$need" "$R/etc/relayd.conf")" = 1 ] && ok "two apps: exactly one: $need" || bad "two apps: count: $need"
done
sed -n '/^# BEGIN app:alpha$/,/^# END app:alpha$/p;/^  # BEGIN app:alpha$/,/^  # END app:alpha$/p' "$R/etc/relayd.conf" | wc -l > "$R/alpha-lines-after"
sed -n '/^# BEGIN app:alpha$/,/^# END app:alpha$/p;/^  # BEGIN app:alpha$/,/^  # END app:alpha$/p' "$R/before-beta" | wc -l > "$R/alpha-lines-before"
cmp -s "$R/alpha-lines-after" "$R/alpha-lines-before" && ok "two apps: alpha's block is unchanged by installing beta" || bad "alpha block changed"
cp "$R/etc/relayd.conf" "$R/both"; $A --yes >/dev/null; $B --yes >/dev/null
cmp -s "$R/both" "$R/etc/relayd.conf" && ok "two apps: re-running either installer changes nothing (neither strips the other)" || bad "two apps: re-run changed relayd"
[ -f "$R/etc/relayd.conf.pre-betaapp" ] && ok "each app keeps its own .pre- backup" || bad "beta backup"


# --- the site login step ---------------------------------------------------------------------------------
stage authapp
S="$W/auth"; mkdir -p "$S/etc"; cp "$FIX/relayd.pristine.conf" "$S/etc/relayd.conf"
AU="sh $W/up-authapp/deploy/install.sh"
APPKIT_TEST_ROOT="$S" $AU --yes > "$S/o1" 2>&1 || { bad "authapp: run failed"; cat "$S/o1"; }
grep -q 'site login is not installed yet' "$S/o1" && [ ! -e "$S/etc/site-auth/keys/authapp.key" ] && ok "site login: without the login service installed it holds back, creates no key" || bad "site login: missing-master handling"
APPKIT_TEST_ROOT="$S" python3 "$KIT/../siteauth/siteauth/keys.py" init --dir "$S/etc/site-auth" --no-chown >/dev/null
APPKIT_TEST_ROOT="$S" $AU --check > "$S/o2" 2>&1; [ ! -e "$S/etc/site-auth/keys/authapp.key" ] && ok "site login: --check writes no key" || bad "site login: --check wrote a key"
APPKIT_TEST_ROOT="$S" $AU --yes > "$S/o3" 2>&1 || { bad "authapp: 2nd run failed"; cat "$S/o3"; }
[ -f "$S/etc/site-auth/keys/authapp.key" ] && grep -qx 'authapp /authapp' "$S/etc/site-auth/apps.conf" && ok "site login: app registered and its key written" || bad "site login: key/registration"
want=$(python3 -c "import importlib.util as u;sp=u.spec_from_file_location('k','$KIT/../siteauth/siteauth/keys.py');m=u.module_from_spec(sp);sp.loader.exec_module(m);print(m.derive(open('$S/etc/site-auth/master').read().strip(),'authapp',1))")
[ "$(cat "$S/etc/site-auth/keys/authapp.key")" = "$want" ] && ok "site login: the key is HMAC(master, app|generation)" || bad "site login: key value"
cp "$S/etc/site-auth/keys/authapp.key" "$S/k1"; APPKIT_TEST_ROOT="$S" $AU --yes > "$S/o4" 2>&1
cmp -s "$S/k1" "$S/etc/site-auth/keys/authapp.key" && grep -q 'registered, key current' "$S/o4" && ok "site login: a second run changes nothing" || bad "site login: not idempotent"

# --- refusals --------------------------------------------------------------------------------------
sed 's/^PORT=.*/PORT=8101/' "$HERE/apps/beta/deploy/app.manifest" > "$W/up-beta/deploy/app.manifest"
$B --yes > "$R/clash.out" 2>&1 && bad "port clash was accepted" || { grep -q 'port 8101' "$R/clash.out" && ok "a port used by another app is refused" || bad "port clash message"; }
cp "$HERE/apps/beta/deploy/app.manifest" "$W/up-beta/deploy/app.manifest"
sed 's/^NAME=.*/NAME=Bad_Name/' "$HERE/apps/beta/deploy/app.manifest" > "$W/up-beta/deploy/app.manifest"
$B --check > "$R/badname.out" 2>&1 && bad "bad NAME accepted" || ok "a NAME with unsafe characters is refused"
cp "$HERE/apps/beta/deploy/app.manifest" "$W/up-beta/deploy/app.manifest"
E="$W/notti"; mkdir -p "$E/etc"; printf 'http protocol "https" {\n}\n' > "$E/etc/relayd.conf"
APPKIT_TEST_ROOT="$E" $A --yes > "$E/out" 2>&1 && bad "non-TI relayd.conf accepted" || { grep -q 'Tech Independence layout' "$E/out" && ok "a relayd.conf without the TI anchor lines is refused, nothing changed" || bad "anchor message"; }

# --- the storage volume guard -----------------------------------------------------------------------
V="$W/vol"; mkdir -p "$V/etc" "$V/var/alpha"; cp "$FIX/relayd.pristine.conf" "$V/etc/relayd.conf"
cp "$HERE/apps/alpha/deploy/app.manifest" "$W/up-alpha/deploy/app.manifest"; echo 'REQUIRE_MOUNT=/var/alpha' >> "$W/up-alpha/deploy/app.manifest"
APPKIT_TEST_ROOT="$V" $A --yes > "$V/o1" 2>&1 && bad "unmounted volume accepted" || { grep -q 'volume-ok' "$V/o1" && ok "REQUIRE_MOUNT: refuses when the sentinel file is missing" || bad "mount message"; }
[ ! -e "$V/etc/rc.d/alpha" ] && ok "REQUIRE_MOUNT: nothing was created before the refusal" || bad "created despite refusal"
touch "$V/var/alpha/.volume-ok"; APPKIT_TEST_ROOT="$V" $A --yes > "$V/o2" 2>&1 && ok "REQUIRE_MOUNT: proceeds once the sentinel exists" || bad "mount with sentinel failed"

# --- --app-files-only -----------------------------------------------------------------------------------
C="$W/codeonly"; mkdir -p "$C/etc"; cp "$FIX/relayd.pristine.conf" "$C/etc/relayd.conf"
cp "$HERE/apps/alpha/deploy/app.manifest" "$W/up-alpha/deploy/app.manifest"
APPKIT_TEST_ROOT="$C" $A --app-files-only --yes > "$C/out" && [ ! -e "$C/etc/alpha.conf" ] && [ ! -e "$C/etc/rc.d/alpha" ] && cmp -s "$FIX/relayd.pristine.conf" "$C/etc/relayd.conf" && ok "app-files-only: no config, service script or relayd change" || bad "app-files-only touched system files"
grep -q 'rsync' "$C/out" && ! grep -q 'groupadd\|pkg_add\|crontab' "$C/out" && ok "app-files-only: only the code copy" || bad "app-files-only: extra steps"

# --- a live server where relayd rules were written by hand: untouched --------------------------------------
L="$W/live"; mkdir -p "$L/etc"; cp "$FIX/relayd.live.conf" "$L/etc/relayd.conf"; cp "$L/etc/relayd.conf" "$L/orig"
mkdir -p "$W/up-live"; cp -R "$HERE/apps/alpha/." "$W/up-live/"; cp "$KIT/appkit.sh" "$W/up-live/deploy/appkit.sh"
sed -e 's/^NAME=.*/NAME=riffbox/' -e 's/^UNIXNAME=.*/UNIXNAME=riffbox/' -e 's/^PORT=.*/PORT=8100/' -e 's/^BASE_PATH=.*/BASE_PATH=\/ideas/' -e '/^DIRS/d' -e '/^CONF_LINES/,$d' "$HERE/apps/alpha/deploy/app.manifest" > "$W/up-live/deploy/app.manifest"
APPKIT_TEST_ROOT="$L" sh "$W/up-live/deploy/install.sh" --yes > "$L/out" 2>&1 || { bad "live: run failed"; cat "$L/out"; }
cmp -s "$L/orig" "$L/etc/relayd.conf" && grep -q 'did not write' "$L/out" && ok "live: hand-written relayd rules are reported and left byte-for-byte untouched" || bad "live: relayd changed"

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
