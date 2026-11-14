# Build phases and owner gates

Do not start a stage until the previous gate is ticked. Nothing OpenBSD-specific can be run on the build machine,
so every deploy gate is run by the owner. Say what is unverified; never assume it.

- [ ] **Stage 0: recon.** Done: `ti.sh`, package list, service list, htdocs listing. Still needed: live `httpd.conf`, `relayd.conf`,
      `pf.conf`, root crontab, riffbox rc script (see `PLAN.md` A3); `ti.tar` arrived empty.
- [ ] **Stage 1: spike (throwaway).** relayd block reaches waitress; httpd `authenticate` on `/private/*`; Basic prompt on iPhone
      Safari and Chrome; Werkzeug hash parameters; cost per request.
- [ ] **Stage 2: kit installer (server level only) and Riffbox's own installer** (branches `kit`; riffbox `install`). Gate: Level 2 rehearsal in a local OpenBSD VM (see `PLAN.md` A4), then Level 3 on the live server with a snapshot.
- [ ] **Stage 3: Riffbox data restore in the app** (riffbox branch `restore-in-app`). Gate: restore the real backup in the drill.
- [ ] **Stage 4: the gate** (branch `gate`). Gate: `tools/gate-test.sh` from outside, iPhone Shortcut test, password change.

Full reasoning, definitions of "the kit", "server rebuild" and "Riffbox data restore", and the unverified list: `PLAN.md`.
