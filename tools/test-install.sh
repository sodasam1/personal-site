#!/bin/sh
# Runs server/install.sh against copies of REAL config files (no OpenBSD needed). Usage: sh tools/test-install.sh
set -eu
cd "$(dirname "$0")/.."
SCR=$(pwd)/server/install.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

mkdir -p "$W/pristine"; tar xf reference/ti.tar -C "$W/pristine" httpd.conf
sed 's/example\.com/sanjaysubramanian.com/g' "$W/pristine/httpd.conf" > "$W/pristine/httpd.conf.fixed"
for name in pristine-ti:"$W/pristine/httpd.conf.fixed" live-2026-11-14:reference/live-2026-11-14/httpd.conf; do
  label=${name%%:*}; src=${name#*:}
  R="$W/$label"; mkdir -p "$R/etc" "$R/var/www"; cp "$src" "$R/etc/httpd.conf"; cp "$R/etc/httpd.conf" "$R/orig"
  export SITEKIT_ROOT="$R"
  sh "$SCR" >/dev/null 2>&1 && bad "$label: ran although relayd.conf had no /private rule" || ok "$label: refuses while relayd has no /private rule"
  cmp -s "$R/etc/httpd.conf" "$R/orig" && ok "$label: ...and changed nothing" || bad "$label: changed httpd.conf anyway"
  printf '  pass request quick path "/private/*" forward to <sitelogin>\n' > "$R/etc/relayd.conf"
  sh "$SCR" --check >/dev/null && cmp -s "$R/etc/httpd.conf" "$R/orig" && ok "$label: --check changes nothing" || bad "$label: --check"
  sh "$SCR" >/dev/null || bad "$label: first run failed"
  [ "$(grep -c 'BEGIN site-kit' "$R/etc/httpd.conf")" = 1 ] && ok "$label: one kit block" || bad "$label: block count"
  # the block must sit inside the 8080 server block, after its listen line and before its closing brace
  awk '/listen on 127\.0\.0\.1 port 8080/{s=1} s&&/BEGIN site-kit/{b=NR} s&&/^}/{c=NR; exit} END{exit !(b&&c&&b<c)}' "$R/etc/httpd.conf" && ok "$label: block inside the 8080 server" || bad "$label: block position"
  diff "$R/orig" "$R/etc/httpd.conf" | grep '^<' >/dev/null && bad "$label: an original line was changed" || ok "$label: only additions, no original line changed"
  cp "$R/etc/httpd.conf" "$R/after1"; sh "$SCR" >/dev/null; cmp -s "$R/after1" "$R/etc/httpd.conf" && ok "$label: second run changes nothing" || bad "$label: not idempotent"
  [ -f "$R/etc/httpd.conf.pre-kit" ] && cmp -s "$R/etc/httpd.conf.pre-kit" "$R/orig" && ok "$label: .pre-kit equals the original" || bad "$label: .pre-kit"
  grep -q 'block return 404' "$R/etc/httpd.conf" && ! grep -q 'authenticate' "$R/etc/httpd.conf" && ok "$label: the block refuses (404) and asks for no password" || bad "$label: block content"
  # an older install had the Basic-auth lines in the same markers: running the new installer must replace them in place
  sed 's/block return 404/authenticate "private" with "\/htpasswd"/' "$R/etc/httpd.conf" > "$R/old-style"; cp "$R/old-style" "$R/etc/httpd.conf"
  sh "$SCR" >/dev/null; cmp -s "$R/after1" "$R/etc/httpd.conf" && ok "$label: an old password rule is replaced by the refusal, one block" || bad "$label: upgrade from the old rule"
  printf 'x\n' > "$R/var/www/htpasswd"; sh "$SCR" >/dev/null; [ "$(cat "$R/var/www/htpasswd")" = x ] && ok "$label: the old password file is left alone" || bad "$label: password file touched"
  sh "$SCR" --remove >/dev/null; cmp -s "$R/etc/httpd.conf" "$R/orig" && ok "$label: --remove restores the original byte for byte" || bad "$label: --remove"
done
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
