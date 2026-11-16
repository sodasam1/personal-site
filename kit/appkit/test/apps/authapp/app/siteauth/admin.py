"""Owner tools, run as root by the login installer:  python3 admin.py set-passphrase --dir /etc/site-auth [--no-chown]
Reads the new passphrase from standard input (one line), refuses one under 15 characters, stores only a salted hash."""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from siteauth import passwords          # noqa: E402
from siteauth.keys import _write        # noqa: E402


def main(argv=None):
    p = argparse.ArgumentParser(prog="admin.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("set-passphrase")
    s.add_argument("--dir", required=True)
    s.add_argument("--no-chown", action="store_true")
    sub.add_parser("method")
    a = p.parse_args(argv)
    if a.cmd == "method":
        print(passwords.default_method())
        return 0
    phrase = sys.stdin.readline().rstrip("\r\n")
    try:
        hashed = passwords.hash_passphrase(phrase)
    except ValueError as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 1
    _write(os.path.join(a.dir, "passphrase.hash"), hashed + "\n", 0o600, None if a.no_chown else "_sitelogin")
    print(f"passphrase stored only as a salted hash ({passwords.default_method().split(':')[0]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
