#!/bin/sh
# Run with: doas sh ~/login/deploy/install.sh --check   (then without --check). Same flags as every app; see deploy/appkit.sh.
. "$(dirname "$0")/appkit.sh"
appkit_main "$@"
