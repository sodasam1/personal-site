#!/bin/sh
# Site kit: server-level installer. Adds ONE thing to a Tech Independence server: a rule that makes httpd REFUSE /private/ (404).
# /private/ is now served by the site login service (relayd sends it there; it needs the login cookie). The refusal is a safety net:
# if the relayd rule were ever lost, /private/ would answer 404 instead of leaking the files. It replaces the older rule that asked
# httpd for a Basic-auth password (the same lines are replaced in place; the password file /var/www/htpasswd is NOT deleted).
#   doas sh ~/install.sh            apply (safe to run twice)
#   doas sh ~/install.sh --check    show exactly what would change; change nothing
#   doas sh ~/install.sh --remove   take the rule out again (leaves /private/ unprotected in httpd: only the login service guards it)
# It never touches Riffbox, relayd, pf, or any line of /etc/httpd.conf that Tech Independence wrote.
# One self-contained file: no other file is needed. Test hook: SITEKIT_ROOT=/some/dir runs against a copy and skips every OpenBSD-only command.
set -eu

ROOT="${SITEKIT_ROOT:-}"
HTTPD_CONF="$ROOT/etc/httpd.conf"
RELAYD_CONF="$ROOT/etc/relayd.conf"
PWFILE="$ROOT/var/www/htpasswd"                     # only looked at, never changed or deleted (left over from the older password rule)
BEGIN="# BEGIN site-kit"
END="# END site-kit"
TMP=$(mktemp)
BLOCK=$(mktemp)
trap 'rm -f "$TMP" "$BLOCK"' EXIT

# The exact text added to httpd.conf (the same lines are written out by hand in RESTORE.html).
cat > "$BLOCK" <<'BLOCKEOF'
  # /private/ is served by the site login service, never by httpd. If a request ever reaches httpd, refuse it.
  location "/private/*" {
    block return 404
  }
BLOCKEOF

MODE=apply
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
  --remove) MODE=remove ;;
  *) echo "usage: $0 [--check|--remove]"; exit 2 ;;
esac

say() { printf '%s\n' "$*"; }

# Write the new httpd.conf to $TMP: any old kit block removed, then (unless removing) a fresh one inserted
# just before the closing brace of the server block that listens on 127.0.0.1 port 8080.
build_conf() {
  awk -v begin="$BEGIN" -v end="$END" -v blockfile="$BLOCK" -v remove="$1" '
    $0 == begin { skip = 1; next }
    $0 == end   { skip = 0; next }
    skip        { next }
    { line[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (line[i] ~ /^server[ \t]/) start = i
        if (line[i] ~ /listen on 127\.0\.0\.1 port 8080/) target = start
      }
      if (remove != "1" && !target) { print "no server block listening on 127.0.0.1 port 8080" > "/dev/stderr"; exit 3 }
      closeat = 0
      if (remove != "1") for (i = target; i <= n; i++) if (line[i] ~ /^}/) { closeat = i; break }
      if (remove != "1" && !closeat) { print "could not find the end of that server block" > "/dev/stderr"; exit 3 }
      for (i = 1; i <= n; i++) {
        if (i == closeat) {
          print begin
          while ((getline l < blockfile) > 0) print l
          print end
        }
        print line[i]
      }
    }' "$HTTPD_CONF" > "$TMP"
}

domain_name() { awk '/^server /{gsub(/"/,"",$2); d=$2} /127\.0\.0\.1 port 8080/{print d; exit}' "$HTTPD_CONF"; }

[ -f "$HTTPD_CONF" ] || { say "No $HTTPD_CONF: is this a Tech Independence server?"; exit 1; }
[ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || { say "Run with doas (needs root)."; exit 1; }

# Refusing /private/ in httpd is only right when relayd already sends /private to the login service; otherwise the owner would be refused too.
if [ "$MODE" != remove ] && ! grep -q '"/private' "$RELAYD_CONF" 2>/dev/null; then
  say "relayd.conf has no rule for /private yet: install the login service first (login/deploy/install.sh), then run this again."
  say "Nothing was changed."
  exit 1
fi

if [ "$MODE" = remove ]; then build_conf 1; else build_conf 0; fi

if cmp -s "$HTTPD_CONF" "$TMP"; then
  say "httpd.conf: already up to date"
else
  say "httpd.conf: would change:"; diff -u "$HTTPD_CONF" "$TMP" || true
  if [ "$MODE" = check ]; then say "(--check: nothing was changed)"; exit 0; fi
  [ -f "$HTTPD_CONF.pre-kit" ] || { cp -p "$HTTPD_CONF" "$HTTPD_CONF.pre-kit"; say "backup: $HTTPD_CONF.pre-kit"; }
  if [ -z "$ROOT" ]; then
    httpd -n -f "$TMP" || { say "httpd rejected the new file: nothing was changed."; exit 1; }
  fi
  cp "$TMP" "$HTTPD_CONF"
  if [ -z "$ROOT" ]; then rcctl reload httpd 2>/dev/null || rcctl restart httpd; fi
  say "httpd.conf: updated"
fi

[ "$MODE" = apply ] || exit 0
if [ -f "$PWFILE" ]; then say "note: the old password file $PWFILE is still there and no longer used. Delete it yourself when you are sure: doas rm /var/www/htpasswd"; fi

if [ -z "$ROOT" ]; then
  d=$(domain_name)
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $d" http://127.0.0.1:8080/private/index.html || true)
  case "$code" in
    404) say "PASS: httpd itself refuses /private/index.html (404). The real check is from outside: sh tools/gate-test-login.sh DOMAIN" ;;
    *)   say "FAIL: expected 404 from httpd for /private/index.html, got $code (the rule is not in effect)" ;;
  esac
fi
