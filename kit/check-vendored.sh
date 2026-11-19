#!/bin/sh
# Fails if any app's vendored copy of the kit differs from kit/ (drift) or is missing.
# Usage: sh kit/check-vendored.sh /path/to/app [...]
set -eu
KIT=$(cd "$(dirname "$0")" && pwd)
. "$KIT/vendor.sh"
[ $# -ge 1 ] || { echo "usage: $0 APPDIR..."; exit 2; }
bad=0
for app in "$@"; do
  app=$(cd "$app" && pwd)
  vendor_pairs "$KIT" "$app" > "${TMPDIR:-/tmp}/vendorc.$$"
  while read -r src dst; do
    if [ ! -f "$app/$dst" ]; then echo "MISSING $app/$dst"; bad=1
    elif ! cmp -s "$src" "$app/$dst"; then echo "DRIFT   $app/$dst differs from $src"; bad=1; fi
  done < "${TMPDIR:-/tmp}/vendorc.$$"
  rm -f "${TMPDIR:-/tmp}/vendorc.$$"
done
[ "$bad" = 0 ] && echo "vendored copies match the kit" || { echo "run: sh kit/sync-into.sh <app>"; exit 1; }
