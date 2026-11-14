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
  sh "$SCR" --check >/dev/null && cmp -s "$R/etc/httpd.conf" "$R/orig" && ok "$label: --check changes nothing" || bad "$label: --check"
  sh "$SCR" >/dev/null || bad "$label: first run failed"
  [ "$(grep -c 'BEGIN site-kit' "$R/etc/httpd.conf")" = 1 ] && ok "$label: one kit block" || bad "$label: block count"
  # the block must sit inside the 8080 server block, after its listen line and before its closing brace
  awk '/listen on 127\.0\.0\.1 port 8080/{s=1} s&&/BEGIN site-kit/{b=NR} s&&/^}/{c=NR; exit} END{exit !(b&&c&&b<c)}' "$R/etc/httpd.conf" && ok "$label: block inside the 8080 server" || bad "$label: block position"
  diff "$R/orig" "$R/etc/httpd.conf" | grep '^<' >/dev/null && bad "$label: an original line was changed" || ok "$label: only additions, no original line changed"
  cp "$R/etc/httpd.conf" "$R/after1"; sh "$SCR" >/dev/null; cmp -s "$R/after1" "$R/etc/httpd.conf" && ok "$label: second run changes nothing" || bad "$label: not idempotent"
  [ -f "$R/etc/httpd.conf.pre-kit" ] && cmp -s "$R/etc/httpd.conf.pre-kit" "$R/orig" && ok "$label: .pre-kit equals the original" || bad "$label: .pre-kit"
  sh "$SCR" --remove >/dev/null; cmp -s "$R/etc/httpd.conf" "$R/orig" && ok "$label: --remove restores the original byte for byte" || bad "$label: --remove"
done
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
