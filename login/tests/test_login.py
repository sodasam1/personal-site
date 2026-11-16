import os
import sys

from conftest import PASSPHRASE
from siteauth import keys, read_token


def cookies(resp):
    out = {}
    for h in resp.headers.getlist("Set-Cookie"):
        first, *attrs = [x.strip() for x in h.split(";")]
        name, _, val = first.partition("=")
        out[name] = (val, {a.split("=")[0].lower(): (a.split("=", 1)[1] if "=" in a else True) for a in attrs})
    return out


def test_form_is_public_and_strict(client):
    r = client.get("/login?next=/ideas/")
    assert r.status_code == 200 and b'name="passphrase"' in r.data and b'value="/ideas/"' in r.data
    assert "script-src 'self'" in r.headers["Content-Security-Policy"] and r.headers["Cache-Control"] == "no-store"
    assert b"<script>" not in r.data and b"onclick" not in r.data


def test_next_is_never_reflected_unsafely(client):
    r = client.get('/login?next="><script>alert(1)</script>')
    assert b"<script>alert" not in r.data and b'value="/"' in r.data
    assert client.get("/login?next=//evil.com").data.count(b'value="/"') == 1


def test_wrong_passphrase_gets_401_and_no_cookies(client):
    r = client.post("/login", data={"passphrase": "nope", "next": "/ideas/"})
    assert r.status_code == 401 and not r.headers.getlist("Set-Cookie") and b"That did not work" in r.data


def test_right_passphrase_sets_one_cookie_per_app_with_that_apps_key_and_path(client):
    r = client.post("/login", data={"passphrase": PASSPHRASE, "next": "/ideas/"})
    assert r.status_code == 303 and r.headers["Location"] == "/ideas/"
    got = cookies(r)
    assert set(got) == {"site_sitelogin", "site_riffbox", "site_music"}
    master = keys.read_first_line(str(client.env["dir"] / "master"))
    for app, path in (("sitelogin", "/private"), ("riffbox", "/ideas"), ("music", "/music")):
        val, attrs = got[f"site_{app}"]
        assert attrs["path"] == path and "httponly" in attrs and attrs["samesite"] == "Lax"
        assert read_token(keys.derive(master, app, 1), val, client.clock()) is not None
        assert read_token(keys.derive(master, "other", 1), val, client.clock()) is None        # not valid for any other app


def test_open_redirect_is_refused(client):
    for bad in ("https://evil.example", "//evil.example", "/\\evil.example", "javascript:alert(1)"):
        r = client.post("/login", data={"passphrase": PASSPHRASE, "next": bad})
        assert r.headers["Location"] == "/"


def test_private_pages_need_the_cookie(client):
    assert client.get("/private/", headers={"Accept": "text/html"}).status_code == 303
    assert client.get("/private/index.html").status_code == 401
    client.post("/login", data={"passphrase": PASSPHRASE})
    # the test client only sends the /private cookie to /private paths, like a browser
    assert client.get("/private/").data == b"<p>secret index</p>"
    assert client.get("/private").data == b"<p>secret index</p>"
    assert client.get("/private/sub/").data == b"<p>secret sub</p>"
    assert client.get("/private/index.html").headers["Cache-Control"] == "private, no-cache"


def test_private_refuses_traversal_dotfiles_and_missing(client):
    client.post("/login", data={"passphrase": PASSPHRASE})
    for p in ("/private/.hidden", "/private/../outside.txt", "/private/%2e%2e/outside.txt", "/private/nothing.html", "/private/sub/.."):
        assert client.get(p).status_code in (404, 308, 301), p
    assert b"outside" not in client.get("/private/../outside.txt").data


def test_logout_expires_every_cookie(client):
    client.post("/login", data={"passphrase": PASSPHRASE})
    r = client.post("/login/logout")
    got = cookies(r)
    assert set(got) == {"site_sitelogin", "site_riffbox", "site_music"} and all(v[0] == "" for v in got.values())
    assert client.get("/private/index.html").status_code == 401


def test_per_client_throttle_after_five_failures(client):
    for _ in range(5):
        assert client.post("/login", data={"passphrase": "bad"}).status_code == 401
    r = client.post("/login", data={"passphrase": PASSPHRASE})
    assert r.status_code == 429 and int(r.headers["Retry-After"]) > 0
    client.clock.t += 901
    assert client.post("/login", data={"passphrase": PASSPHRASE}).status_code == 303


def test_a_spread_out_attack_slows_but_never_locks_out_the_owner(client):
    for i in range(35):                                    # 35 failures from 35 different addresses
        client.post("/login", data={"passphrase": "bad"}, headers={"X-Forwarded-For": f"10.0.0.{i}"}, environ_base={"REMOTE_ADDR": "127.0.0.1"})
    client.sleeps.clear()
    r = client.post("/login", data={"passphrase": PASSPHRASE}, headers={"X-Forwarded-For": "203.0.113.9"}, environ_base={"REMOTE_ADDR": "127.0.0.1"})
    assert r.status_code == 303 and client.sleeps == [2.0]             # the real owner still gets in, after a short delay


def test_oversize_login_body_is_refused_before_it_is_read(client):
    r = client.post("/login", data={"passphrase": "x" * 10000})
    assert r.status_code == 413


def test_cross_origin_login_post_is_refused(client):
    assert client.post("/login", data={"passphrase": PASSPHRASE}, headers={"Origin": "https://evil.example"}).status_code == 403


def test_every_route_is_declared(client):
    from siteauth import undeclared_routes
    assert undeclared_routes(client.application) == []


def test_unset_server_fails_safely(tmp_path):
    from sitelogin import create_app
    app = create_app({"SITELOGIN_AUTH_DIR": str(tmp_path / "empty"), "SITELOGIN_INSECURE_COOKIES": "1"})
    c = app.test_client()
    assert c.post("/login", data={"passphrase": "anything at all here"}).status_code == 401
    assert c.get("/private/x").status_code == 401
