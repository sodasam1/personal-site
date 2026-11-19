import os
import subprocess
import sys

import pytest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "app"))
KEYS = os.path.join(HERE, "..", "app", "siteauth", "keys.py")          # the vendored copy: what actually ships
ADMIN = os.path.join(HERE, "..", "app", "siteauth", "admin.py")
PASSPHRASE = "correct horse battery staple"


class Clock:
    def __init__(self, t=2_000_000):
        self.t = t

    def __call__(self):
        return self.t


@pytest.fixture
def env(tmp_path):
    d = tmp_path / "site-auth"
    priv = tmp_path / "private"
    (priv / "sub").mkdir(parents=True)
    (priv / "index.html").write_text("<p>secret index</p>")
    (priv / "sub" / "index.html").write_text("<p>secret sub</p>")
    (priv / ".hidden").write_text("nope")
    (tmp_path / "outside.txt").write_text("outside")
    run = lambda *a, **k: subprocess.run([sys.executable, *a], check=True, capture_output=True, text=True, **k)   # noqa: E731
    run(KEYS, "init", "--dir", str(d), "--no-chown")
    for app, path in (("sitelogin", "/private"), ("riffbox", "/ideas"), ("music", "/music")):
        run(KEYS, "ensure-app", "--dir", str(d), "--app", app, "--path", path, "--no-chown")
    from werkzeug.security import generate_password_hash        # a cheap hash keeps the tests fast; the real one is tested in test_admin
    (d / "passphrase.hash").write_text(generate_password_hash(PASSPHRASE, method="pbkdf2:sha256:1000") + "\n")
    return {"dir": d, "private": priv, "tmp": tmp_path}


@pytest.fixture
def client(env):
    from sitelogin import create_app
    clock, sleeps = Clock(), []
    app = create_app({"SITELOGIN_AUTH_DIR": str(env["dir"]), "SITELOGIN_PRIVATE_DIR": str(env["private"]),
                      "SITELOGIN_INSECURE_COOKIES": "1", "clock": clock, "sleep": sleeps.append})
    app.config["TESTING"] = True
    c = app.test_client()
    c.clock, c.sleeps, c.env = clock, sleeps, env
    return c


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: uses the real (slow) password hash")
