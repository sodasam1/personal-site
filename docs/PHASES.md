# Build phases and owner gates

Do not start a stage until the previous gate is ticked. Nothing OpenBSD-specific can be run on the build machine,
so every deploy gate is run by the owner. Say what is unverified; never assume it.

- [ ] **Stage 0: recon.** Owner provides `reference/ti.sh`, `reference/ti.tar` and the output in `STAGE0-RECON.md`.
- [ ] **Stage 1: spike (throwaway).** relayd block reaches waitress; httpd `authenticate` on `/private/*`; Basic prompt on iPhone
      Safari and Chrome; Werkzeug hash parameters; cost per request.
- [ ] **Stage 2: kit and install script** (branch `kit`). Gate: server rebuild drill on a new instance with a throwaway domain.
- [ ] **Stage 3: Riffbox data restore in the app** (riffbox branch `restore-in-app`). Gate: restore the real backup in the drill.
- [ ] **Stage 4: the gate** (branch `gate`). Gate: `tools/gate-test.sh` from outside, iPhone Shortcut test, password change.

Full reasoning, definitions of "the kit", "server rebuild" and "Riffbox data restore", and the unverified list: `PLAN.md`.
