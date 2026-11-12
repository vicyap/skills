#!/usr/bin/env bash
# run.sh — the decision-sprite template release as a Sprite service.
#
# Layout contract (see DEPLOY.md):
#   APP_DIR  = the directory containing this script (the extracted release)
#   DATA_DIR = $APP_DIR/data  (persistent on the sprite disk)
#     data/app.db            SQLite database (DATABASE_PATH)
#     data/seed.json         optional first-boot seed (state.json shape)
#     data/.admin_token      admin bearer token, 0600 — if a deploy
#                            pre-places it, that value wins and is never
#                            overwritten; otherwise generated on first boot
#     data/.secret_key_base  Phoenix secret, 0600, generated on first boot
#
# sprite-env services create app --cmd <abs path to run.sh> --dir <app dir> --http-port 8080
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# When run.sh sits at the release root (tarball layout), APP_DIR is its own dir.
if [ -x "$APP_DIR/bin/decision_sprite" ]; then
  :
elif [ -x "$(dirname "${BASH_SOURCE[0]}")/bin/decision_sprite" ]; then
  APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

DATA_DIR="$APP_DIR/data"
mkdir -p "$DATA_DIR"

# Optional per-sprite deploy config (KEY=VALUE lines, written by the
# deploy step — never by the template build): PHX_HOST (the sprite's
# public *.sprites.app hostname), SPRITE_NAME, SUBMIT_NOTIFIER
# (mail_gateway for real submit delivery), SUBMIT_MAIL_FROM/TO.
# This is the ONLY per-sprite configuration surface besides seed.json
# and the admin token — code is identical across the fleet.
ENV_FILE="$DATA_DIR/.env"
if [ -s "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

SECRET_FILE="$DATA_DIR/.secret_key_base"
if [ ! -s "$SECRET_FILE" ]; then
  # python3 secrets: no shell pipeline, so this cannot die by SIGPIPE.
  python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(64)).decode())" > "$SECRET_FILE.tmp"
  chmod 600 "$SECRET_FILE.tmp"
  mv "$SECRET_FILE.tmp" "$SECRET_FILE"
fi
export SECRET_KEY_BASE="$(cat "$SECRET_FILE")"

# Admin token: a pre-placed data/.admin_token wins; the app generates one
# on first boot (0600) when the file is absent. Never overwrite here.
export ADMIN_TOKEN_FILE="$DATA_DIR/.admin_token"

export PORT="${PORT:-8080}"
export DATABASE_PATH="$DATA_DIR/app.db"
export DATA_DIR
export MIX_ENV="prod"

# Migrate (idempotent DDL) before serving; first-boot seeding from
# data/seed.json happens inside the app boot when the DB is empty.
# PHX_SERVER=false for the eval boot so it never binds the port.
PHX_SERVER="false" "$APP_DIR/bin/decision_sprite" eval "DecisionSprite.Release.migrate()"

export PHX_SERVER="true"
exec "$APP_DIR/bin/decision_sprite" start
