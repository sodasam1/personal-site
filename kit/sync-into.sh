#!/bin/sh
# Copy the kit parts an app lists in its kit.use into the app folder (vendoring: the server never fetches anything).
# Usage: sh kit/sync-into.sh /path/to/app [/path/to/another/app ...]      Only adds or updates files; never deletes.
set -eu
KIT=$(cd "$(dirname "$0")" && pwd)
. "$KIT/vendor.sh"
[ $# -ge 1 ] || { echo "usage: $0 APPDIR..."; exit 2; }
for app in "$@"; do
  app=$(cd "$app" && pwd); n=0
  vendor_pairs "$KIT" "$app" > "${TMPDIR:-/tmp}/vendor.$$"
  while read -r src dst; do
    mkdir -p "$(dirname "$app/$dst")"
    if ! cmp -s "$src" "$app/$dst" 2>/dev/null; then cp "$src" "$app/$dst"; n=$((n+1)); fi
  done < "${TMPDIR:-/tmp}/vendor.$$"
  rm -f "${TMPDIR:-/tmp}/vendor.$$"
  echo "$app: $n file(s) updated"
done
