#!/bin/sh
# Shared by sync-into.sh and check-vendored.sh. An app lists the kit parts it uses, one per line, in <app>/kit.use:
#   appkit   siteauth   minimal   wave   audio
# vendor_pairs KITDIR APPDIR prints "source destination" pairs (destinations relative to the app folder).
vendor_pairs() {
  k=$1; a=$2
  [ -f "$a/kit.use" ] || { echo "no kit.use in $a" >&2; return 1; }
  while read -r part; do
    case "$part" in
      ''|'#'*) ;;
      appkit)   echo "$k/appkit/appkit.sh deploy/appkit.sh" ;;
      siteauth) for f in "$k"/siteauth/siteauth/*.py; do echo "$f app/siteauth/$(basename "$f")"; done ;;
      audio)    for f in "$k"/audio/kitaudio/*.py; do echo "$f app/kitaudio/$(basename "$f")"; done ;;
      minimal)  for f in minimal.css theme.js theme-menu.js; do echo "$k/minimal/$f static/minimal/$f"; done ;;
      wave)     echo "$k/wave/wave.js static/wave/wave.js" ;;
      *) echo "unknown kit part '$part' in $a/kit.use" >&2; return 1 ;;
    esac
  done < "$a/kit.use"
}
