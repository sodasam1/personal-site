# kit/ : what every app on the server shares

| Part | What | Used by |
|---|---|---|
| `appkit/appkit.sh` | the generic installer (parameterized by each app's `deploy/app.manifest`) | every app, the login service |
| `siteauth/` | verifies the owner's cookie with the app's own key; fail-closed route declarations; origin check; rate limiters; password hashing; key tools | every app with an owner side |
| `minimal/` | the one look (Minimal), light/dark/auto, seven accents | every web page |
| `wave/` | canvas waveform drawing and scrubbing | music-share, Version Control |
| `audio/` | ffmpeg helpers: peaks, FLAC play copies, loudness (LUFS), loop slices, probe | music-share, Version Control |

**Vendored, never fetched.** Apps carry copies. An app lists the parts it uses in `kit.use`; `sh kit/sync-into.sh APP` copies them in,
`sh kit/check-vendored.sh APP` fails on drift. Edit the kit, then re-sync every app.

**Tests:** `VENV_PY=/path/to/python sh tools/test-kit.sh` runs everything offline (needs Flask, pytest in that python; see the script header).

See `docs/MULTI-APP.md` for the design and `appkit/README.md` for the manifest reference.
