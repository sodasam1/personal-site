"""The site's one login (approach C). Public-facing, so it is small and strict.

  GET  /login          the sign-in form
  POST /login          check the passphrase (throttled); on success set ONE cookie PER APP (each signed with that app's own key,
                       scoped to that app's path) and go back to `next`
  POST /login/logout   expire every app's cookie
  GET  /login/health   {"ok": true}
  GET  /private/...    your private static pages, served only with a valid cookie (replaces httpd's Basic-auth prompt)

State lives in /etc/site-auth (see siteauth/keys.py). This service alone can read the master key and the passphrase hash.
"""
import os
import time
from html import escape
from pathlib import Path

from flask import Flask, Response, abort, jsonify, redirect, request, send_file, send_from_directory
from werkzeug.security import safe_join

from siteauth import GlobalGate, Limiter, SiteAuth, keys, make_token, passwords, safe_next

LOOPBACK = ("127.0.0.1", "::1")
CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
       "base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'")

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Sign in</title>
<link rel="stylesheet" href="/login/static/minimal.css"><script src="/login/static/theme.js"></script></head>
<body><div class="wrap"><header class="site"><h1>Sign in</h1></header>
<form method="post" action="/login" autocomplete="on">
<input type="hidden" name="next" value="{next}">
<label for="pw">Passphrase</label>
<input id="pw" name="passphrase" type="password" autocomplete="current-password" autofocus required>
<p class="err" role="alert">{message}</p>
<p><button class="primary" type="submit">Sign in</button></p></form></div></body></html>"""


def load_conf(path):
    out = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def create_app(overrides=None):
    conf = load_conf(os.environ.get("SITELOGIN_CONFIG", "/etc/sitelogin.conf"))
    conf.update({k: v for k, v in os.environ.items() if k.startswith("SITELOGIN_")})
    conf.update(overrides or {})
    auth_dir = conf.get("SITELOGIN_AUTH_DIR", "/etc/site-auth")
    private_dir = conf.get("SITELOGIN_PRIVATE_DIR", "/var/www/htdocs/private")
    static_dir = conf.get("SITELOGIN_STATIC_DIR", str(Path(__file__).resolve().parents[2] / "static"))
    secure = conf.get("SITELOGIN_INSECURE_COOKIES") != "1"
    clock = conf.get("clock") or time.time
    sleep = conf.get("sleep") or time.sleep

    app = Flask(__name__, static_folder=None)
    auth = SiteAuth(app, name="sitelogin", key_file=os.path.join(auth_dir, "keys", "sitelogin.key"), cookie_path="/private",
                    login_url="/login", clock=clock, secure=secure, samesite="Lax")
    # Wrong-passphrase limit per client: SITELOGIN_MAX_FAILS failures within SITELOGIN_WINDOW_MINUTES, then that client waits (default 5 in 15).
    # A typo stops the service at start-up rather than silently using the default.
    def whole(name, default):
        raw = str(conf.get(name, "")).strip()
        if not raw:
            return default
        try:
            value = int(raw)
        except ValueError:
            raise RuntimeError(f"{name} must be a whole number (got '{raw}')") from None
        if value < 1:
            raise RuntimeError(f"{name} must be at least 1 (got {value})")
        return value
    max_fails, window = whole("SITELOGIN_MAX_FAILS", 5), whole("SITELOGIN_WINDOW_MINUTES", 15) * 60
    limiter, gate = Limiter(clock, per_key_max=max_fails, window=window), GlobalGate(clock, window=window)

    @app.after_request
    def headers(resp):
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "same-origin")
        if request.path.startswith("/login"):
            resp.headers.setdefault("Content-Security-Policy", CSP)
            resp.headers.setdefault("Cache-Control", "no-store")
        return resp

    def client_key():
        addr = request.remote_addr or "?"
        if addr in LOOPBACK:
            last = request.headers.get("X-Forwarded-For", "").split(",")[-1].strip()
            if last:
                return last
        return addr

    def page(next_url, message="", status=200):
        body = PAGE.format(next=escape(safe_next(next_url), quote=True), message=escape(message))
        return Response(body, status=status, mimetype="text/html")

    @app.get("/login/health")
    @auth.public
    def health():
        return jsonify(ok=True)

    @app.get("/login/static/<path:name>")
    @auth.public
    def static_files(name):
        if name.startswith(".") or "/." in name:
            abort(404)
        return send_from_directory(static_dir, name, max_age=3600)

    @app.get("/login")
    @auth.public
    def form():
        return page(request.args.get("next", "/"))

    @app.post("/login")
    @auth.public
    def sign_in():
        request.max_content_length = 4096                      # nobody needs more than a passphrase here
        nxt = request.form.get("next", "/")
        key = client_key()
        wait = limiter.wait_for(key)
        if wait:
            resp = page(nxt, "Too many attempts. Try again later.", 429)
            resp.headers["Retry-After"] = str(wait)
            return resp
        pressure = gate.under_pressure()
        if pressure:                                            # a spread-out guessing attack: slow everyone a little, lock nobody out
            if not gate.try_enter():
                resp = page(nxt, "Busy. Try again in a moment.", 429)
                resp.headers["Retry-After"] = "2"
                return resp
            sleep(gate.delay)
        try:
            stored = keys.read_first_line(os.path.join(auth_dir, "passphrase.hash"), "")
            if passwords.verify(stored, request.form.get("passphrase", "")):
                limiter.succeeded(key)
                master = keys.read_first_line(os.path.join(auth_dir, "master"), "")
                gen = keys.read_first_line(os.path.join(auth_dir, "generation"), "1")
                if not master:
                    return page(nxt, "The login is not set up on this server yet.", 503)
                resp = redirect(safe_next(nxt), 303)
                now = clock()
                for app_name, path in keys.read_apps(auth_dir):
                    resp.set_cookie(f"site_{app_name}", make_token(keys.derive(master, app_name, gen), now), max_age=30 * 86400,
                                    path=path, httponly=True, secure=secure, samesite="Lax")
                return resp
            limiter.failed(key)
            gate.note_failure()
            return page(nxt, "That did not work.", 401)
        finally:
            if pressure:
                gate.leave()

    @app.post("/login/logout")
    @auth.public
    def sign_out():
        resp = redirect("/login", 303)
        for app_name, path in keys.read_apps(auth_dir):
            resp.set_cookie(f"site_{app_name}", "", max_age=0, expires=0, path=path, httponly=True, secure=secure, samesite="Lax")
        return resp

    def serve_private(p):
        base = os.path.realpath(private_dir)
        target = safe_join(base, p) if p else base
        if target is None or any(part.startswith(".") for part in Path(p).parts):
            abort(404)
        if os.path.isdir(target):
            target = os.path.join(target, "index.html")
        if not os.path.isfile(target) or not os.path.realpath(target).startswith(base + os.sep):
            abort(404)
        resp = send_file(target, conditional=True, max_age=0)
        resp.headers["Cache-Control"] = "private, no-cache"
        return resp

    @app.get("/private")
    @app.get("/private/")
    @auth.owner
    def private_root():
        return serve_private("")

    @app.get("/private/<path:p>")
    @auth.owner
    def private(p):
        return serve_private(p)

    return app
