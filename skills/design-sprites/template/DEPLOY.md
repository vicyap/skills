# Deploying the decision-sprite template to a Fly Sprite

One Phoenix app, deployed unchanged to any number of sprites. The only
per-sprite inputs are a seed file, an optional admin token, a display
title, and a `data/.env` config file. Template version: see `/health`
(`template_version`).

## Submit delivery (R2) — per-sprite setup

So a "Submit to Muse" click actually reaches Muse:

1. Label the sprite for the Resend gateway connection (labels are
   REPLACED by one call — pass the sprite's complete label set):
   `sprite config update -s <sprite> --label conn:resend`
2. Write `data/.env` (0600) with:
   ```
   PHX_HOST=<sprite>-<suffix>.sprites.app
   SPRITE_NAME=<sprite>
   SUBMIT_NOTIFIER=mail_gateway
   ```
   The MailGateway adapter discovers the Resend connection's gateway
   URL from inside the sprite at first send (spike-proven path:
   ~2–3 s to Muse's Muse Mail inbox). Without `SUBMIT_NOTIFIER` the
   sprite still records submissions but reports them UNDELIVERED on the
   page — that is deliberate, not a bug.
3. Muse acks a read submission with `POST /admin/ack {"round": N}`
   (Bearer) — only then may the page say "Muse picked this up".

## Artifact

`release.tar.gz` (built with `MIX_ENV=prod mix release`, ERTS bundled)
contains the release at its root plus `run.sh`:

```
bin/decision_sprite   the release executable
lib/  releases/  erts-*/   release contents
run.sh                the service command (see below)
```

## Per-sprite deploy steps (validated locally end to end)

1. Create / choose the sprite (in your Sprites org). Do not reuse another
   project's sprite.
2. Copy the artifact onto the sprite and extract it as the app dir, e.g.
   `/home/sprite/app`:
   - `sprite exec` / sftp the tarball up, then `tar xzf release.tar.gz -C /home/sprite/app`
3. Seed the sprite's data dir (all state lives in `<app dir>/data`):
   - Place the project's `state.json`-shaped seed at
     `/home/sprite/app/data/seed.json`. On first boot (empty DB) the app
     loads it through `DecisionSprite.SeedLoader`, the same loader used
     by `POST /api/reset`.
   - To pin the admin token, pre-place it at
     `/home/sprite/app/data/.admin_token` (mode 0600). `run.sh` and the
     app never overwrite an existing token. If absent, the app generates
     one on first boot; read it back from that file after first boot and
     store it somewhere safe (mode 0600).
   - Display title: set the `APP_TITLE` env var for the service (e.g.
     "Sensor Alert Routing"), or give the seed's `design` object a
     `"title"` field. Default when neither is set: "Decisions with Muse".
4. Register the service (services `--cmd` takes ONE executable; that is
   `run.sh`, which performs migrate + secret generation + start):
   ```
   sprite-env services create app --cmd /home/sprite/app/run.sh --dir /home/sprite/app --http-port 8080
   ```
   `run.sh` guarantees:
   - `data/` exists; `data/.secret_key_base` generated once (0600,
     python3 `secrets`, no shell pipelines) and reused after;
   - exports `PORT=8080`, `DATABASE_PATH=$APP_DIR/data/app.db`,
     `ADMIN_TOKEN_FILE=$APP_DIR/data/.admin_token`, `PHX_SERVER=true`;
   - runs `bin/decision_sprite eval "DecisionSprite.Release.migrate()"`
     (idempotent DDL) before `exec bin/decision_sprite start`.
5. Verify:
   - `GET https://<sprite>.sprites.app/health` →
     `{"ok":true,"rounds":N,"design_version":V,"template_version":"0.2.0"}`
     (the health check performs a real DB write+read probe)
   - `GET /admin/answers` with `Authorization: Bearer <token>` returns
     the seeded rounds/answers verbatim.
   - `GET /` shows the design sections; `GET /questions` shows the
     latest round with one "Submit to Muse" button.

## Runtime contracts migrations rely on

- Data dir: `<app dir>/data` (SQLite `app.db`, `seed.json`,
  `.admin_token`, `.secret_key_base` — the latter three 0600 where the
  app creates them).
- Env: `DATABASE_PATH`, `ADMIN_TOKEN_FILE`, `SECRET_KEY_BASE`, `PORT`
  (8080 on sprites), `PHX_SERVER=true`, optional `APP_TITLE`, optional
  `PHX_HOST`.
- HTTP: `GET /health` (no auth), `GET /admin/answers` (Bearer),
  `GET /api/state` (Bearer), `POST /api/rounds` (Bearer, 409 while a
  round is open unless `replace_open:true`; a snapshotted round is
  never destroyed), `POST /api/design` (Bearer, bumps design version),
  `POST /api/reset` and `POST /api/seed` (Bearer, body
  `{"state": {...}}` replaces all content — REFUSED with 409
  `would_drop_snapshot` if the document would drop a submitted round's
  snapshot, unless `"force": true`), `POST /admin/ack` (Bearer,
  body `{"round": N}` — Muse's explicit "I read it" signal),
  `POST /api/draft` (session+CSRF — the pagehide sendBeacon flush).
- Replacing content on a live sprite = `POST /api/reset` with the full
  state document; no redeploy needed. Changing the seed file only
  affects a fresh (empty) database.
