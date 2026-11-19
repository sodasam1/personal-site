# Site-login specifics: create /etc/site-auth (master key, generation) and store your passphrase's hash. Sourced by appkit.sh.
app_before_site_auth() {
  if [ "$CHECK" = 1 ]; then
    say "   (would create $AUTH_DIR/master and generation, and ask for your passphrase if no hash is stored)"
    return 0
  fi
  NOCHOWN=""; [ -n "$ROOT" ] && NOCHOWN="--no-chown"
  # shellcheck disable=SC2086
  out=$("$PY" "$SRC/$SITE_AUTH_TOOL" init --dir "$ROOT$AUTH_DIR" $NOCHOWN) || die "could not create $AUTH_DIR: $out"
  case "$out" in created*) made "$AUTH_DIR: $out" ;; *) left "$AUTH_DIR already initialised" ;; esac
  if [ -f "$ROOT$AUTH_DIR/passphrase.hash" ]; then
    left "your passphrase hash is stored (to change it: doas python3 /usr/local/login/app/siteauth/admin.py set-passphrase --dir $AUTH_DIR)"
  else
    PASS="${SITELOGIN_INSTALL_PASSPHRASE:-}"
    if [ -z "$PASS" ]; then
      say "   Choose ONE long passphrase (15+ characters, random or 5+ words): it opens every private app and page."
      printf '   Passphrase: '; stty -echo 2>/dev/null || true; read -r PASS; stty echo 2>/dev/null || true; echo
    fi
    # shellcheck disable=SC2086
    printf '%s\n' "$PASS" | "$PY" "$SRC/app/siteauth/admin.py" set-passphrase --dir "$ROOT$AUTH_DIR" $NOCHOWN || die "the passphrase was refused (15 characters minimum)."
    made "$AUTH_DIR/passphrase.hash"
  fi
}
