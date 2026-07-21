#!/usr/bin/env bash
# Builds the Flutter web app and deploys it to the VPS gateway (nginx on :8000).
# Static files live in /opt/priority-lists/web — outside the supabase/ dir,
# so the CI `rsync --delete` of supabase/ never touches them.
set -euo pipefail

cd "$(dirname "$0")/.."

VPS="root@65.21.0.66"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/priority-deploy}"
REMOTE_WEB_DIR=/opt/priority-lists/web

flutter build web --release --dart-define-from-file=.env.json

ssh -i "$SSH_KEY" "$VPS" "mkdir -p $REMOTE_WEB_DIR"
rsync -avz --delete -e "ssh -i $SSH_KEY" build/web/ "$VPS:$REMOTE_WEB_DIR/"

# Sync gateway config and recreate ONLY the gateway container.
# Never run `docker compose down` here — the db must keep running.
rsync -avz -e "ssh -i $SSH_KEY" \
  supabase/docker-compose.yml supabase/volumes/nginx/nginx.conf \
  --rsync-path="rsync" "$VPS:/tmp/deploy-web-staging/"
ssh -i "$SSH_KEY" "$VPS" '
  set -euo pipefail
  cp /tmp/deploy-web-staging/docker-compose.yml /opt/priority-lists/supabase/docker-compose.yml
  cp /tmp/deploy-web-staging/nginx.conf /opt/priority-lists/supabase/volumes/nginx/nginx.conf
  cd /opt/priority-lists/supabase
  docker compose up -d gateway
'

echo "Deployed: http://65.21.0.66:8000/"
