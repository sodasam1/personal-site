#!/bin/sh
# Runs every offline test of the kit and the login service. No OpenBSD needed.
#   VENV_PY=/path/to/python-with-flask-and-pytest sh tools/test-kit.sh
# Make that python once:  python3 -m venv /tmp/kitvenv && /tmp/kitvenv/bin/pip install flask==3.1.3 werkzeug==3.1.9 itsdangerous==2.2.0 waitress==3.0.2 pytest
set -u
cd "$(dirname "$0")/.."
PY="${VENV_PY:-python3}"; fail=0
run() { echo "== $1"; shift; "$@" || fail=1; }
run "appkit installer logic (dash)" dash kit/appkit/test/test-appkit.sh
run "appkit installer logic (bash)" bash kit/appkit/test/test-appkit.sh
run "siteauth"            "$PY" -m pytest -q kit/siteauth/tests
run "audio helpers"       "$PY" -m pytest -q kit/audio/tests
run "login service"       "$PY" -m pytest -q login/tests
run "login installer"     env VENV_PY="$PY" dash login/tests/test-installer.sh
run "vendored copies match the kit" sh kit/check-vendored.sh login
[ "$fail" = 0 ] && echo "ALL KIT TESTS PASSED" || { echo "SOME KIT TESTS FAILED"; exit 1; }
