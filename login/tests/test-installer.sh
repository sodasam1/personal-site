#!/bin/sh
# Runs the login service's installer (deploy/install.sh) in test mode against a copy of your real relayd.conf. No OpenBSD needed.
# Needs a python3 that has Flask/Werkzeug: VENV_PY=/path/to/venv/bin/python sh login/tests/test-installer.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); LOGIN=$(cd "$HERE/.." && pwd); FIX="$LOGIN/../kit/appkit/test/fixtures"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0; ok() { echo "PASS: $*"; }; bad() { echo "FAIL: $*"; fail=1; }
export DOAS_USER=me APPKIT_TEST_PYTHON="${VENV_PY:-python3}" SITELOGIN_INSTALL_PASSPHRASE='a long test passphrase'
cp -R "$LOGIN" "$W/up"; rm -rf "$W/up/tests"
R="$W/root"; mkdir -p "$R/etc"; cp "$FIX/relayd.pristine.conf" "$R/etc/relayd.conf"; export APPKIT_TEST_ROOT="$R"
A="sh $W/up/deploy/install.sh"
$A --check > "$R/c.out" 2>&1; [ ! -e "$R/etc/site-auth/master" ] && [ ! -e "$R/etc/sitelogin.conf" ] && ok "--check writes nothing" || bad "--check wrote something"
$A --yes > "$R/o1" 2>&1 || { bad "install failed"; cat "$R/o1"; }
D="$R/etc/site-auth"
[ -f "$D/master" ] && [ "$(stat -c %a "$D/master")" = 640 ] && [ "$(cat "$D/generation")" = 1 ] && ok "master key (mode 640: the service group can read it, others cannot) and generation 1 created" || bad "master/generation"
[ -f "$D/passphrase.hash" ] && [ "$(stat -c %a "$D/passphrase.hash")" = 640 ] && ! grep -q 'long test passphrase' "$D/passphrase.hash" && ok "passphrase stored only as a hash, mode 640" || bad "passphrase hash"
grep -qx 'sitelogin /private' "$D/apps.conf" && [ -f "$D/keys/sitelogin.key" ] && ok "the login service registered itself with its own key" || bad "self registration"
for need in '<sitelogin> { 127.0.0.1 }' 'path "/login" forward to <sitelogin>' 'path "/private/\*" forward to <sitelogin>' 'forward to <sitelogin> port 8099'; do
  [ "$(grep -c "$need" "$R/etc/relayd.conf")" = 1 ] && ok "relayd has exactly one: $need" || bad "relayd: $need"
done
grep -q '^SITELOGIN_PRIVATE_DIR=/var/www/htdocs/private$' "$R/etc/sitelogin.conf" && ok "conf points at the private pages folder" || bad "conf"
cp -R "$D" "$W/d1"; cp "$R/etc/relayd.conf" "$W/r1"; $A --yes > "$R/o2" 2>&1
diff -r "$W/d1" "$D" >/dev/null && cmp -s "$W/r1" "$R/etc/relayd.conf" && ok "a second run changes nothing (the passphrase is not asked again)" || bad "not idempotent"
R2="$W/root2"; mkdir -p "$R2/etc"; cp "$FIX/relayd.pristine.conf" "$R2/etc/relayd.conf"
SITELOGIN_INSTALL_PASSPHRASE='too short' APPKIT_TEST_ROOT="$R2" sh "$W/up/deploy/install.sh" --yes > "$R2/o" 2>&1 && bad "a short passphrase was accepted" || { [ ! -e "$R2/etc/site-auth/passphrase.hash" ] && ok "a passphrase under 15 characters is refused and no hash is written" || bad "short passphrase left a file"; }
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
