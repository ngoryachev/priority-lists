#!/usr/bin/env bash
# Applies the not-yet-applied migrations from volumes/db/init/ to the running db.
#
# Postgres runs init scripts only on an empty data directory, and docker-compose
# mounts just 000 and 001 — so 002+ never reach a live database on their own.
# Some of them are not safe to re-run (002 re-copies legacy rows into `nodes`,
# 003 renumbers positions), so applied files are recorded in
# deploy.applied_migrations and each one runs exactly once, in its own
# transaction together with its ledger row.
#
# Runs on the VPS from the supabase/ directory; called by the Deploy workflow.
set -euo pipefail

cd "$(dirname "$0")/.."

psql() {
  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

# Separate schema: PostgREST exposes `public`, the ledger must not be.
psql -q <<'SQL'
SET client_min_messages TO warning;
CREATE SCHEMA IF NOT EXISTS deploy;
CREATE TABLE IF NOT EXISTS deploy.applied_migrations (
  name TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

applied=0
for file in volumes/db/init/[0-9][0-9][0-9]_*.sql; do
  name="$(basename "$file")"
  # 000 and 001 are mounted into docker-entrypoint-initdb.d.
  case "$name" in 000_* | 001_*) continue ;; esac

  if [[ -n "$(psql -tAc "SELECT 1 FROM deploy.applied_migrations WHERE name = '$name'")" ]]; then
    continue
  fi

  echo "==> $name"
  { cat "$file"; echo; echo "INSERT INTO deploy.applied_migrations (name) VALUES ('$name');"; } \
    | psql --single-transaction
  applied=$((applied + 1))
done

if ((applied > 0)); then
  # Otherwise PostgREST keeps serving the old schema and new tables 404.
  psql -c "NOTIFY pgrst, 'reload schema';"
fi
echo "Migrations applied: $applied"
