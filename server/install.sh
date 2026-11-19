#!/bin/sh
# Site kit: server-level installer. Adds ONE thing to a Tech Independence server: a password rule for /private/.
#   doas sh ~/staging/server/install.sh            apply (safe to run twice)
#   doas sh ~/staging/server/install.sh --check    show exactly what would change; change nothing
#   doas sh ~/staging/server/install.sh --passwd   set or change the password for /private/
#   doas sh ~/staging/server/install.sh --remove   take the rule out again (the password file is kept)
# It never touches Riffbox, relayd, pf, or any line of /etc/httpd.conf that Tech Independence wrote.
# One self-contained file: no other file is needed. Test hook: SITEKIT_ROOT=/some/dir runs against a copy and skips every OpenBSD-only command.
set -eu

ROOT="${SITEKIT_ROOT:-}"
HTTPD_CONF="$ROOT/etc/httpd.conf"
PWFILE="$ROOT/var/www/htpasswd"
BEGIN="# BEGIN site-kit"
END="# END site-kit"
TMP=$(mktemp)
BLOCK=$(mktemp)
trap 'rm -f "$TMP" "$BLOCK"' EXIT

# The exact text added to httpd.conf (the same lines are written out by hand in RESTORE.html).
cat > "$BLOCK" <<'BLOCKEOF'
  # Everything under /private/ needs the site password. The file is relative to the web chroot (/var/www).
  location "/private/*" {
    authenticate "private" with "/htpasswd"
  }
BLOCKEOF

MODE=apply
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
  --passwd) MODE=passwd ;;
  --remove) MODE=remove ;;
  *) echo "usage: $0 [--check|--passwd|--remove]"; exit 2 ;;
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

set_password() {
  if [ -n "$ROOT" ]; then say "(test mode: password step skipped)"; return 0; fi
  user_default="${DOAS_USER:-me}"
  printf 'User name for /private/ [%s]: ' "$user_default"; read -r u
  u=${u:-$user_default}
  say "Choose a long random passphrase (20+ characters). It is stored only as a bcrypt hash."
  htpasswd "$PWFILE" "$u"
  chown root:www "$PWFILE"; chmod 640 "$PWFILE"
  say "Password file: /var/www/htpasswd (owner root, group www, mode 640)."
}

if [ "$MODE" = passwd ]; then set_password; exit 0; fi

[ -f "$HTTPD_CONF" ] || { say "No $HTTPD_CONF: is this a Tech Independence server?"; exit 1; }
[ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || { say "Run with doas (needs root)."; exit 1; }

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
[ -f "$PWFILE" ] || { say "No password file yet."; set_password; }

if [ -z "$ROOT" ]; then
  d=$(domain_name)
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $d" http://127.0.0.1:8080/private/index.html || true)
  case "$code" in
    401) say "PASS: /private/index.html refuses a visitor without the password (401)" ;;
    404) say "NOTE: no /private/index.html uploaded yet; upload htdocs/private/ and run tools/gate-test.sh" ;;
    *)   say "FAIL: expected 401 from /private/index.html, got $code" ;;
  esac
fi
