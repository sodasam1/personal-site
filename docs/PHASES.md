# Build phases and owner gates

Do not start a stage until the previous gate is ticked. Nothing OpenBSD-specific can be run on the build machine,
so every deploy gate is run by the owner. Say what is unverified; never assume it.

- [ ] **Stage 0: recon.** Done: `ti.sh`, package list, service list, htdocs listing. `ti.tar` now valid. Still needed: the live
      `httpd.conf`, `relayd.conf`, `pf.conf`, root crontab, riffbox rc script (see `PLAN.md` A3).
- [ ] **Stage 1: spike (throwaway).** relayd block reaches waitress; httpd `authenticate` on `/private/*`; Basic prompt on iPhone
      Safari and Chrome; Werkzeug hash parameters; cost per request.
- [ ] **Stage 2: kit installer (server level only) and Riffbox's own installer** (branches `kit`; riffbox `install`). Gate: offline checks against the real TI files, then a `--check` dry run on the live server (see `PLAN.md` B1).
- [ ] **Stage 3: Riffbox data restore in the app** (riffbox branch `restore-in-app`). Gate: restore the real backup in the drill.
- [ ] **Stage 4: the gate** (branch `gate`). Gate: `tools/gate-test.sh` from outside, iPhone Shortcut test, password change.

Full reasoning, definitions of "the kit", "server rebuild" and "Riffbox data restore", and the unverified list: `PLAN.md`.

## Status log
- **14 Nov 2026, owner-verified on the live server:** `install.sh --check` showed the expected diff; apply succeeded (OpenBSD's own
  `httpd -n` accepted `authenticate "private" with "/htpasswd"`); from outside: public page 200, `/private/index.html` without a
  password 401, plain-http 301 to https; the browser prompted and accepted the passphrase. This settles, on the real server:
  the `authenticate` syntax, the 8080-block placement, `htpasswd` creation, and the `reload`.
- **Still unverified:** wrong password refused (browser, one try); iPhone Safari and Chrome prompt and sign-in; per-request cost of the
  password check; behaviour after `sysupgrade`. Stage 2 (Riffbox's own installer), Stage 3 and Stage 4 not started.

## Full rebuild runbook (branch `rebuild-runbook`)
`RESTORE.html` is now the complete, offline, ordered rebuild page: what must be on your computer, Tech Independence, the site's password rule, Riffbox (installer
prompts explained, the upload token), restoring your recordings, five final checks, and what to do when things go wrong. `tools/gate-test.ps1` is the Windows
version of the password check.
- [x] Local gate: the page is well-formed HTML; the commands match the riffbox installer's real behaviour as tested there.
- [ ] Owner: read `RESTORE.html` once, start to finish, and say what is unclear or missing. Run `tools\gate-test.ps1` (not verified: I cannot run PowerShell here).

