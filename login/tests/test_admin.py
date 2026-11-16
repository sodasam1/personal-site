import subprocess
import sys

from conftest import ADMIN
from siteauth import passwords


def run(d, phrase):
    return subprocess.run([sys.executable, ADMIN, "set-passphrase", "--dir", str(d), "--no-chown"], input=phrase + "\n", capture_output=True, text=True)


def test_set_passphrase_stores_only_a_hash_with_private_mode(tmp_path):
    r = run(tmp_path, "a perfectly long passphrase")
    assert r.returncode == 0
    stored = (tmp_path / "passphrase.hash").read_text().strip()
    assert "a perfectly long passphrase" not in stored and passwords.verify(stored, "a perfectly long passphrase")
    assert oct((tmp_path / "passphrase.hash").stat().st_mode & 0o777) == "0o600"


def test_short_passphrase_is_refused_and_nothing_is_written(tmp_path):
    r = run(tmp_path, "too short")
    assert r.returncode == 1 and "at least 15" in r.stderr and not (tmp_path / "passphrase.hash").exists()
