#!/bin/sh
# Checks from OUTSIDE (run on your own computer) that the site login works and that private pages are private.
#   sh tools/gate-test-login.sh sanjaysubramanian.com        (asks for your passphrase; nothing is stored)
# Needs curl. Prints PASS/FAIL per check. Run it after installing the login service (login/deploy/install.sh).
# NOTE: it makes ONE wrong sign-in attempt on purpose (the limit is 5 per 15 minutes per address).
set -u
D=${1:?usage: gate-test-login.sh DOMAIN}
printf 'Passphrase: '; stty -echo 2>/dev/null; read -r P; stty echo 2>/dev/null; echo
J=$(mktemp); trap 'rm -f "$J"' EXIT
fail=0
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
chk() { [ "$2" = "$3" ] && echo "PASS: $1 ($3)" || { echo "FAIL: $1 (wanted $2, got $3)"; fail=1; }; }
chk "public home page"                                  200 "$(code "https://$D/")"
chk "sign-in page is public"                            200 "$(code "https://$D/login")"
chk "private page, not signed in (script)"              401 "$(code "https://$D/private/index.html")"
chk "private page, not signed in (browser): to sign-in" 303 "$(code -H 'Accept: text/html' "https://$D/private/index.html")"
chk "sign-in with a wrong passphrase"                   401 "$(code -c "$J" --data-urlencode 'passphrase=definitely-wrong' "https://$D/login")"
chk "sign-in with the right passphrase"                 303 "$(code -c "$J" --data-urlencode "passphrase=$P" "https://$D/login")"
chk "private page, signed in"                           200 "$(code -b "$J" "https://$D/private/index.html")"
chk "sign out"                                          303 "$(code -b "$J" -c "$J" -X POST "https://$D/login/logout")"
chk "private page, after signing out"                   401 "$(code -b "$J" "https://$D/private/index.html")"
chk "plain-http address redirects to https"             301 "$(code "http://$D/login")"
exit $fail
