import os
import subprocess
import sys

import pytest
from flask import Flask, jsonify

from siteauth import SiteAuth, GlobalGate, Limiter, keys, make_token, read_token, safe_next, undeclared_routes
from siteauth import passwords

HERE = os.path.dirname(__file__)
KEYS_PY = os.path.join(HERE, "..", "siteauth", "keys.py")


class Clock:
    def __init__(self, t=1_000_000):
        self.t = t

    def __call__(self):
        return self.t


@pytest.fixture
def setup(tmp_path):
    d = tmp_path / "site-auth"
    subprocess.run([sys.executable, KEYS_PY, "init", "--dir", str(d), "--no-chown"], check=True, capture_output=True)
    for app, path in (("alpha", "/alpha"), ("beta", "/beta")):
        subprocess.run([sys.executable, KEYS_PY, "ensure-app", "--dir", str(d), "--app", app, "--path", path, "--no-chown"],
                       check=True, capture_output=True)
    return d


def make_app(setup, name="alpha", clock=None, bearer=None):
    app = Flask(name)
    app.config["TESTING"] = True
    clock = clock or Clock()
    auth = SiteAuth(app, name=name, key_file=str(setup / "keys" / f"{name}.key"), cookie_path="/" + name, clock=clock,
                    secure=False, bearer_check=bearer)

    @app.get("/pub")
    @auth.public
    def pub():
        return "public"

    @app.get("/priv")
    @auth.owner
    def priv():
        return "private"

    @app.get("/undeclared")
    def undeclared():
        return "x"

    @app.post("/do")
    @auth.owner
    def do():
        return jsonify(ok=True)

    @app.post("/upload")
    @auth.token
    def upload():
        return jsonify(ok=True)

    @app.get("/who")
    @auth.public
    def who():
        return jsonify(owner=auth.is_owner())
    return app, auth, clock


def cookie_for(setup, name, now, **kw):
    master = keys.read_first_line(str(setup / "master"))
    gen = keys.read_first_line(str(setup / "generation"))
    return make_token(keys.derive(master, name, gen), now, **kw)


def test_public_is_open_owner_is_not(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    assert c.get("/pub").status_code == 200
    assert c.get("/priv").status_code == 401
    assert c.get("/priv", headers={"Accept": "text/html"}).status_code == 303


def test_undeclared_route_is_owner_only_and_listed(setup):
    app, auth, clock = make_app(setup)
    assert undeclared_routes(app) == ["undeclared"]
    assert app.test_client().get("/undeclared").status_code == 401


def test_valid_cookie_opens_owner_routes(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", clock()), path="/alpha")
    # cookie path /alpha is not sent to "/priv" by a real browser; test client matches path, so set it for "/"
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", clock()), path="/")
    assert c.get("/priv").status_code == 200
    assert c.get("/who").json == {"owner": True}


def test_cookie_for_another_app_is_rejected(setup):
    app, auth, clock = make_app(setup, "alpha")
    c = app.test_client()
    c.set_cookie("site_alpha", cookie_for(setup, "beta", clock()), path="/")
    assert c.get("/priv").status_code == 401


def test_tampered_and_garbage_cookies_are_rejected(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    good = cookie_for(setup, "alpha", clock())
    for bad in (good[:-2] + "xx", "garbage", "", good + "A"):
        c.set_cookie("site_alpha", bad, path="/")
        assert c.get("/priv").status_code == 401


def test_absolute_and_idle_expiry(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    t0 = clock()
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", t0), path="/")
    clock.t = t0 + 6 * 86400
    assert c.get("/priv").status_code == 200
    clock.t = t0 + 31 * 86400                       # past 30 days from login, even though "seen" was refreshed
    assert c.get("/priv").status_code == 401
    clock.t = t0
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", t0), path="/")
    clock.t = t0 + 8 * 86400                        # unused for 8 days
    assert c.get("/priv").status_code == 401


def test_use_refreshes_the_idle_clock_once_an_hour(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    t0 = clock()
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", t0), path="/")
    r = c.get("/priv")
    assert "Set-Cookie" not in r.headers            # fresh: no refresh yet
    clock.t = t0 + 2 * 3600
    r = c.get("/priv")
    assert "site_alpha=" in r.headers.get("Set-Cookie", "") and "HttpOnly" in r.headers["Set-Cookie"]


def test_rotate_logs_everyone_out(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", clock()), path="/")
    assert c.get("/priv").status_code == 200
    subprocess.run([sys.executable, KEYS_PY, "rotate", "--dir", str(setup)], check=True, capture_output=True)
    os.utime(setup / "keys" / "alpha.key", ns=(10**18, 10**18 + 5))     # mtime changes on a real rewrite; make it certain
    assert c.get("/priv").status_code == 401


def test_missing_key_file_fails_closed(tmp_path):
    app = Flask("x")
    sa = SiteAuth(app, name="x", key_file=str(tmp_path / "nokey"), secure=False)

    @app.get("/p")
    @sa.owner
    def p():
        return "p"
    assert app.test_client().get("/p").status_code == 401


def test_cross_origin_posts_are_refused_same_origin_allowed(setup):
    app, auth, clock = make_app(setup)
    c = app.test_client()
    c.set_cookie("site_alpha", cookie_for(setup, "alpha", clock()), path="/")
    assert c.post("/do", headers={"Origin": "https://evil.example"}).status_code == 403
    assert c.post("/do", headers={"Origin": "null"}).status_code == 403
    assert c.post("/do", headers={"Sec-Fetch-Site": "cross-site"}).status_code == 403
    assert c.post("/do", headers={"Origin": "http://localhost"}).status_code == 200
    assert c.post("/do").status_code == 200


def test_bearer_only_on_token_routes(setup):
    app, auth, clock = make_app(setup, bearer=lambda r: r.headers.get("Authorization") == "Bearer s3cret")
    c = app.test_client()
    assert c.post("/upload", headers={"Authorization": "Bearer s3cret"}).status_code == 200
    assert c.post("/upload", headers={"Authorization": "Bearer nope"}).status_code == 401
    assert c.post("/do", headers={"Authorization": "Bearer s3cret"}).status_code == 401


@pytest.mark.parametrize("value,ok", [("/ideas/", True), ("/a?b=c", True), ("//evil.com", False), ("https://evil.com", False),
                                      ("/\\evil.com", False), ("javascript:alert(1)", False), ("/x\r\nSet-Cookie: a=b", False), ("", False)])
def test_safe_next(value, ok):
    assert (safe_next(value) == value) is ok
    if not ok:
        assert safe_next(value) == "/"


def test_derived_keys_differ_per_app_and_generation():
    assert keys.derive("m", "a", 1) != keys.derive("m", "b", 1) != keys.derive("m", "a", 2)
    assert keys.derive("m", "a", 1) == keys.derive("m", "a", "1")


def test_ensure_app_is_idempotent_and_needs_the_login_service(tmp_path, setup):
    again = subprocess.run([sys.executable, KEYS_PY, "ensure-app", "--dir", str(setup), "--app", "alpha", "--path", "/alpha", "--no-chown"],
                           capture_output=True, text=True)
    assert "already registered" in again.stdout
    nodir = subprocess.run([sys.executable, KEYS_PY, "ensure-app", "--dir", str(tmp_path / "none"), "--app", "alpha", "--path", "/alpha", "--no-chown"],
                           capture_output=True, text=True)
    assert nodir.returncode == 3
    assert keys.read_apps(str(setup)) == [("alpha", "/alpha"), ("beta", "/beta")]
    assert oct(os.stat(setup / "master").st_mode & 0o777) == "0o600"


def test_limiter_per_client_and_never_blocks_others():
    clock = Clock(0)
    lim = Limiter(clock, per_key_max=5, window=900)
    for _ in range(5):
        assert lim.wait_for("a") == 0
        lim.failed("a")
    assert lim.wait_for("a") > 0
    assert lim.wait_for("b") == 0                       # a stranger's failures never block anyone else
    clock.t = 901
    assert lim.wait_for("a") == 0
    lim.failed("a"); lim.succeeded("a")
    assert lim.wait_for("a") == 0


def test_global_gate_slows_but_does_not_lock_out():
    clock = Clock(0)
    gate = GlobalGate(clock, soft_max=3, window=900, max_waiters=2)
    assert not gate.under_pressure()
    for _ in range(3):
        gate.note_failure()
    assert gate.under_pressure()
    assert gate.try_enter() and gate.try_enter() and not gate.try_enter()
    gate.leave(); assert gate.try_enter()
    clock.t = 901
    assert not gate.under_pressure()


def test_passphrase_hash_and_minimum_length():
    with pytest.raises(ValueError):
        passwords.hash_passphrase("only 14 chars!")          # 14 characters: refused (minimum is 15)
    h = passwords.hash_passphrase("a long enough passphrase")
    assert passwords.verify(h, "a long enough passphrase") and not passwords.verify(h, "wrong") and not passwords.verify("junk", "x")
