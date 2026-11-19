"""Attack tests against the site login: each test is something an attacker would try, and what it must NOT achieve.
Run with the rest of the login tests. Nothing here touches a real server."""
import re
import subprocess
import sys
import threading
import time

import pytest

from conftest import ADMIN, KEYS, PASSPHRASE
from siteauth import keys, make_token, passwords, read_token

PEER = {"REMOTE_ADDR": "127.0.0.1"}                    # relayd is the only thing that talks to the service, from the loopback address


def attempt(client, phrase, ip="198.51.100.7", **kw):
    return client.post("/login", data={"passphrase": phrase, **kw.pop("data", {})}, headers={"X-Forwarded-For": ip}, environ_base=PEER, **kw)


# ---- guessing the passphrase online ----------------------------------------------------------------------------------------------------
def test_parallel_guesses_cannot_beat_the_attempt_limit(client, monkeypatch):
    """An attacker sends many guesses at the same instant, before the first has been judged wrong. Only `max_fails` of them may even be checked."""
    checked = []
    real = passwords.verify
    def slow_verify(stored, supplied):
        checked.append(supplied); time.sleep(0.05)
        return real(stored, supplied)
    monkeypatch.setattr(passwords, "verify", slow_verify)
    results = []
    def worker(i):
        c = client.application.test_client()
        results.append(attempt(c, f"wrong guess number {i}").status_code)
    threads = [threading.Thread(target=worker, args=(i,)) for i in range(30)]
    [t.start() for t in threads]; [t.join() for t in threads]
    assert len(checked) <= 5, f"{len(checked)} guesses were checked before the limit applied"
    assert results.count(429) >= 25


def test_changing_the_forwarded_address_does_not_reset_the_limit_for_a_direct_peer(client):
    """A client that reaches the service directly (not through relayd) cannot invent a new identity per guess with X-Forwarded-For."""
    direct = {"REMOTE_ADDR": "203.0.113.50"}
    codes = [client.post("/login", data={"passphrase": "nope"}, headers={"X-Forwarded-For": f"10.9.8.{i}"}, environ_base=direct).status_code for i in range(8)]
    assert codes[:5] == [401] * 5 and set(codes[5:]) == {429}


def test_only_the_last_forwarded_address_counts_so_a_prefix_cannot_dodge_the_limit(client):
    codes = [client.post("/login", data={"passphrase": "nope"}, headers={"X-Forwarded-For": f"1.1.1.{i}, 198.51.100.9"}, environ_base=PEER).status_code for i in range(7)]
    assert codes[:5] == [401] * 5 and codes[5] == 429


def test_error_answers_are_generic(client):
    wrong = attempt(client, "x", ip="198.51.100.20")
    long_wrong = attempt(client, "y" * 3000, ip="198.51.100.21")
    assert wrong.status_code == 401 and wrong.get_data(as_text=True).count("That did not work") == 1
    assert long_wrong.status_code in (401, 413)
    for banned in ("hash", "pbkdf2", "scrypt", "invalid", "incorrect", "attempts remaining"):
        assert banned not in wrong.get_data(as_text=True).lower()


@pytest.mark.slow
def test_checking_a_guess_takes_the_same_time_whatever_the_guess(tmp_path):
    """No timing difference between a short, a long and a nearly-right guess (the slow hash dominates)."""
    d = tmp_path / "t"
    subprocess.run([sys.executable, KEYS, "init", "--dir", str(d), "--no-chown"], check=True, capture_output=True)
    subprocess.run([sys.executable, ADMIN, "set-passphrase", "--dir", str(d), "--no-chown"], input="a long enough passphrase here\n", check=True, capture_output=True, text=True)
    stored = keys.read_first_line(str(d / "passphrase.hash"))
    def cost(guess):
        t = time.perf_counter(); passwords.verify(stored, guess); return time.perf_counter() - t
    times = {g: min(cost(g) for _ in range(3)) for g in ("x", "a long enough passphrase her", "a long enough passphrase here", "z" * 2000)}
    assert max(times.values()) / min(times.values()) < 1.6, times


def test_the_stored_hash_is_slow_salted_and_not_the_passphrase(tmp_path):
    out = []
    for n in range(2):
        d = tmp_path / f"h{n}"
        d.mkdir()
        r = subprocess.run([sys.executable, ADMIN, "set-passphrase", "--dir", str(d), "--no-chown"], input=PASSPHRASE + " extra words\n", capture_output=True, text=True)
        assert r.returncode == 0
        out.append(keys.read_first_line(str(d / "passphrase.hash")))
    assert out[0] != out[1] and PASSPHRASE not in out[0]                               # random salt each time
    m = re.match(r"(pbkdf2:sha256:(\d+)|scrypt:(\d+):(\d+):(\d+))\$", out[0])
    assert m, out[0]
    if m.group(2):
        assert int(m.group(2)) >= 600_000                                              # OWASP's figure for PBKDF2-HMAC-SHA256 (secondhand)
    else:
        assert int(m.group(3)) >= 2 ** 15


# ---- forging or stealing a login --------------------------------------------------------------------------------------------------------
def test_forged_cookies_are_refused(client):
    master = keys.read_first_line(str(client.env["dir"] / "master"))
    good_key = keys.derive(master, "sitelogin", 1)
    forged = {
        "unsigned json": '{"r":"owner","iat":1,"seen":1}',
        "base64 json": "eyJyIjoib3duZXIiLCJpYXQiOjEsInNlZW4iOjF9",
        "empty": "",
        "signed with the wrong key": make_token("not-the-key", client.clock()),
        "signed with another app's key": make_token(keys.derive(master, "riffbox", 1), client.clock()),
        "signed with the master key": make_token(master, client.clock()),
        "old generation": make_token(keys.derive(master, "sitelogin", 0), client.clock()),
        "tampered role": make_token(good_key, client.clock(), role="admin"),
        "garbage": "A" * 400,
    }
    for name, value in forged.items():
        client.set_cookie("site_sitelogin", value, path="/")
        assert client.get("/private/index.html").status_code == 401, name
    # a genuine one still works (so the test above is not passing for the wrong reason)
    client.set_cookie("site_sitelogin", make_token(good_key, client.clock()), path="/")
    assert client.get("/private/index.html").status_code == 200


def test_a_cookie_cannot_be_made_valid_by_editing_its_dates(client):
    master = keys.read_first_line(str(client.env["dir"] / "master"))
    key = keys.derive(master, "sitelogin", 1)
    old = make_token(key, client.clock() - 40 * 86400)                                   # signed 40 days ago
    assert read_token(key, old, client.clock()) is None
    assert read_token(key, make_token(key, client.clock() - 10 * 86400, iat=client.clock() - 10 * 86400), client.clock()) is None     # unused for 10 days


def test_cookies_are_hardened_and_scoped_when_the_site_runs_over_https(env):
    from sitelogin import create_app
    app = create_app({"SITELOGIN_AUTH_DIR": str(env["dir"]), "SITELOGIN_PRIVATE_DIR": str(env["private"])})      # secure cookies are the default
    from werkzeug.security import generate_password_hash
    (env["dir"] / "passphrase.hash").write_text(generate_password_hash(PASSPHRASE, method="pbkdf2:sha256:1000") + "\n")
    r = app.test_client().post("/login", data={"passphrase": PASSPHRASE}, base_url="https://example.test")
    assert r.status_code == 303
    flags = {}
    for h in r.headers.getlist("Set-Cookie"):
        name = h.split("=", 1)[0]
        low = h.lower()
        assert "secure" in low and "httponly" in low and "samesite=lax" in low, h
        assert re.search(r"max-age=2592000", low), h                                      # 30 days, not forever
        path = re.search(r"path=([^;]+)", low).group(1)
        assert path != "/", "a cookie scoped to the whole site would be sent to every app and public page: " + h
        flags[name] = path
    assert set(flags) == {"site_sitelogin", "site_riffbox", "site_music"}


def test_one_apps_key_cannot_open_another_app(client):
    master = keys.read_first_line(str(client.env["dir"] / "master"))
    k_riff = keys.derive(master, "riffbox", 1)
    assert read_token(keys.derive(master, "sitelogin", 1), make_token(k_riff, client.clock()), client.clock()) is None


# ---- getting somewhere you should not ----------------------------------------------------------------------------------------------------------
REDIRECTS = ["//evil.example", "///evil.example", "/\\evil.example", "\\\\evil.example", "https://evil.example", "http:evil.example", "javascript:alert(1)",
             "data:text/html,x", "/\t/evil.example", "/ /evil.example", "/%0d%0aSet-Cookie:%20pwn=1", "/x\r\nSet-Cookie: pwn=1", "\\/evil.example", "/..//evil.example",
             "mailto:a@b", "  //evil.example", "//", "/‮evil", ""]


@pytest.mark.parametrize("target", REDIRECTS)
def test_the_after_login_redirect_never_leaves_the_site(client, target):
    r = attempt(client, PASSPHRASE, ip=f"192.0.2.{abs(hash(target)) % 250 + 1}", data={"next": target})
    loc = r.headers.get("Location", "")
    assert r.status_code == 303 and loc.startswith("/") and not loc.startswith("//") and "\\" not in loc and "\n" not in loc and "\r" not in loc, loc
    assert "pwn" not in "".join(r.headers.getlist("Set-Cookie"))
    page = client.get("/login", query_string={"next": target}).get_data(as_text=True)
    assert "evil.example" not in page.replace("/evil.example", "") or 'value="/' in page


def test_private_pages_cannot_be_reached_by_path_tricks(client):
    client.post("/login", data={"passphrase": PASSPHRASE})
    (client.env["tmp"] / "secret.txt").write_text("OUTSIDE")
    (client.env["private"] / "link.txt").symlink_to(client.env["tmp"] / "secret.txt")
    for p in ("/private/link.txt", "/private/../secret.txt", "/private/%2e%2e/secret.txt", "/private/%252e%252e/secret.txt", "/private/..%2fsecret.txt",
              "/private/sub/../../secret.txt", "/private//etc/passwd", "/private/%00", "/private/index.html%00.txt", "/private/.hidden", "/private/\\..\\secret.txt"):
        r = client.get(p)
        assert b"OUTSIDE" not in r.data and b"root:" not in r.data and r.status_code in (301, 308, 400, 404), (p, r.status_code)
    assert client.get("/private/sub").status_code in (200, 301, 308)                        # a folder serves its index.html, never a listing
    assert b"Index of" not in client.get("/private/sub/").data


def test_only_the_expected_methods_exist(client):
    for m in ("put", "delete", "patch", "trace"):
        assert getattr(client, m)("/login").status_code in (403, 405), m
    assert client.options("/login").status_code in (200, 405)
    assert client.get("/login/logout").status_code == 405                                      # signing out is a POST, so a link cannot do it


def test_every_route_is_either_public_or_needs_the_cookie(client):
    app = client.application
    seen = {}
    for rule in app.url_map.iter_rules():
        if "GET" in rule.methods and "<" not in rule.rule:
            seen[rule.rule] = client.get(rule.rule).status_code
    open_routes = {r for r, code in seen.items() if code == 200}
    assert open_routes <= {"/login", "/login/health"}, open_routes
    assert seen["/private"] == 401 and seen["/private/"] == 401


def test_cross_site_requests_to_the_login_are_refused(client):
    for hdr in ({"Origin": "https://evil.example"}, {"Origin": "null"}, {"Sec-Fetch-Site": "cross-site"}):
        assert client.post("/login", data={"passphrase": PASSPHRASE}, headers=hdr).status_code == 403
        assert client.post("/login/logout", headers=hdr).status_code == 403


def test_the_login_page_cannot_be_framed_cached_or_scripted(client):
    r = client.get("/login")
    csp = r.headers["Content-Security-Policy"]
    assert "frame-ancestors 'none'" in csp and "script-src 'self'" in csp and "'unsafe-inline'" not in csp and "object-src 'none'" in csp
    assert r.headers["Cache-Control"] == "no-store" and r.headers["X-Content-Type-Options"] == "nosniff"
    assert re.search(r"<script(?![^>]*\bsrc=)", r.get_data(as_text=True)) is None, "inline script"
    assert 'type="password"' in r.get_data(as_text=True) and 'autocomplete="current-password"' in r.get_data(as_text=True)


def test_a_passphrase_is_never_echoed_or_logged(client, caplog):
    import logging
    caplog.set_level(logging.DEBUG)
    r = attempt(client, "tell-nobody-this-secret-123", ip="198.51.100.88")
    assert "tell-nobody-this-secret-123" not in r.get_data(as_text=True) + str(r.headers)
    assert "tell-nobody-this-secret-123" not in caplog.text


def test_a_huge_or_malformed_request_does_not_crash_or_leak(client):
    assert attempt(client, "p" * 100_000).status_code == 413
    r = client.post("/login", data=b"\x00\xff\xfe", content_type="application/x-www-form-urlencoded", headers={"X-Forwarded-For": "198.51.100.99"}, environ_base=PEER)
    assert r.status_code in (400, 401) and b"Traceback" not in r.data and b"werkzeug" not in r.data.lower()
    assert client.get("/login", query_string={"next": "A" * 100000}).status_code in (200, 414)


def test_error_pages_do_not_reveal_the_software_or_paths(client):
    r = client.get("/definitely/not/here")
    assert r.status_code == 404 and b"/home/" not in r.data and b"site-packages" not in r.data and b"Traceback" not in r.data
