#!/bin/sh
# Checks from OUTSIDE (run on your own computer) that /private/ really is private.
#   sh tools/gate-test.sh sanjaysubramanian.com USER      (asks for the password; nothing is stored)
# Needs curl. Prints PASS/FAIL per check.
set -u
D=${1:?usage: gate-test.sh DOMAIN USER}; U=${2:?usage: gate-test.sh DOMAIN USER}
printf 'Password for %s: ' "$U"; stty -echo 2>/dev/null; read -r P; stty echo 2>/dev/null; echo
fail=0
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
chk() { [ "$2" = "$3" ] && echo "PASS: $1 ($3)" || { echo "FAIL: $1 (wanted $2, got $3)"; fail=1; }; }
chk "public home page"                       200 "$(code "https://$D/")"
chk "private page, no password"              401 "$(code "https://$D/private/index.html")"
chk "private page, wrong password"           401 "$(code -u "$U:definitely-wrong" "https://$D/private/index.html")"
chk "private page, right password"           200 "$(code -u "$U:$P" "https://$D/private/index.html")"
chk "plain-http address redirects to https"  301 "$(code "http://$D/private/index.html")"
exit $fail
