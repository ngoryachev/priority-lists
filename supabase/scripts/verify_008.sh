#!/usr/bin/env bash
# Runs 008_node_mark.sql for real against a throwaway Postgres container and
# asserts what it did.
#
# Pushing to main applies pending migrations to production data, so this one
# has to be right the first time. The container is created here, never
# published to a port, and removed on exit — nothing outside Docker is touched.
#
#   supabase/scripts/verify_008.sh
#
# What it checks, after running 001-007 and seeding a handful of nodes:
#   * `mark` is TEXT, nullable, with no default, and NULL on every seeded row
#   * the CHECK accepts 'flame', 'ice' and NULL and rejects anything else
#   * a PostgREST-shaped conflict update that omits `mark` leaves an existing
#     mark intact — which is what keeps an old build from clearing a mark set
#     by a new one
#   * priority, position and created_at are untouched by the whole thing
#   * a second run of the file changes no rows and adds no second constraint
#
# It stubs `auth.users` and `auth.uid()` rather than running the whole Supabase
# stack, exactly like verify_006.sh: the migration runs as `postgres` and so
# bypasses RLS anyway, and what it needs from the schema is the `nodes` table.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly image="postgres:16"
readonly container="priority-lists-verify-008-$$"

cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> starting $container ($image)"
docker run --rm -d --name "$container" \
  -e POSTGRES_PASSWORD=verify-008 "$image" >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$container" pg_isready -U postgres -q; then break; fi
  sleep 1
done
docker exec "$container" pg_isready -U postgres -q

psql() {
  docker exec -i "$container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"
}

run_file() {
  echo "==> applying $1"
  psql --single-transaction <"$1"
}

echo "==> stubbing the Supabase bits 001-007 lean on"
psql <<'SQL'
SET client_min_messages TO warning;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY);
-- Enough for the RLS policies to be creatable; nothing here runs as a user.
CREATE FUNCTION auth.uid() RETURNS UUID AS $$ SELECT NULL::UUID $$ LANGUAGE sql;
SQL

for file in \
  volumes/db/init/001_initial_schema.sql \
  volumes/db/init/002_nodes.sql \
  volumes/db/init/003_node_position.sql \
  volumes/db/init/004_activity_log.sql \
  volumes/db/init/005_current_role.sql \
  volumes/db/init/006_roles_as_nodes.sql \
  volumes/db/init/007_view_state.sql; do
  run_file "$file"
done

echo "==> seeding a role with three children"
psql <<'SQL'
SET client_min_messages TO warning;

INSERT INTO auth.users (id) VALUES ('11111111-1111-1111-1111-111111111111');

INSERT INTO nodes (id, user_id, parent_id, title, priority, position, created_at)
VALUES
  ('aaaa0001-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', NULL, 'Root', 1, 0, '2026-01-01'),
  ('aaaa0101-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0001-0000-0000-0000-000000000000', 'Fix the build', 1, 0, '2026-01-02'),
  ('aaaa0102-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0001-0000-0000-0000-000000000000', 'Review a PR',   2, 1, '2026-01-03'),
  ('aaaa0103-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0001-0000-0000-0000-000000000000', 'Buy milk',      4, 2, '2026-01-04');

-- What the tree looked like before the column existed, to compare against.
CREATE TABLE verify_before AS
SELECT id, parent_id, title, priority, position, created_at FROM nodes;
SQL

run_file volumes/db/init/008_node_mark.sql

echo "==> checking what it did"
psql <<'SQL'
SET client_min_messages TO warning;
DO $$
DECLARE
  offenders TEXT;
  col RECORD;
  marked TEXT;
BEGIN
  -- The column itself: TEXT, nullable, no default.
  SELECT data_type, is_nullable, column_default INTO col
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'nodes' AND column_name = 'mark';
  IF col IS NULL THEN
    RAISE EXCEPTION 'nodes.mark was not added';
  END IF;
  IF col.data_type <> 'text' THEN
    RAISE EXCEPTION 'nodes.mark is % and not text', col.data_type;
  END IF;
  IF col.is_nullable <> 'YES' THEN
    RAISE EXCEPTION 'nodes.mark is NOT NULL';
  END IF;
  IF col.column_default IS NOT NULL THEN
    RAISE EXCEPTION 'nodes.mark has a default: %', col.column_default;
  END IF;

  -- No backfill: every seeded row is unmarked.
  IF EXISTS (SELECT 1 FROM nodes WHERE mark IS NOT NULL) THEN
    RAISE EXCEPTION 'the migration marked rows it should have left alone';
  END IF;

  -- Everything else about those rows survived untouched.
  SELECT string_agg(b.id::TEXT, ', ') INTO offenders
  FROM verify_before b
  JOIN nodes n ON n.id = b.id
  WHERE n.parent_id IS DISTINCT FROM b.parent_id
     OR n.title <> b.title
     OR n.priority <> b.priority
     OR n.position <> b.position
     OR n.created_at <> b.created_at;
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'the migration disturbed: %', offenders;
  END IF;
  IF (SELECT count(*) FROM nodes) <> (SELECT count(*) FROM verify_before) THEN
    RAISE EXCEPTION 'the migration changed the row count';
  END IF;

  -- The CHECK takes the two values the app writes, and NULL.
  FOREACH marked IN ARRAY ARRAY['flame', 'ice'] LOOP
    UPDATE nodes SET mark = marked
    WHERE id = 'aaaa0101-0000-0000-0000-000000000000';
  END LOOP;
  UPDATE nodes SET mark = NULL
  WHERE id = 'aaaa0101-0000-0000-0000-000000000000';

  -- And nothing else.
  FOREACH marked IN ARRAY ARRAY['', 'FLAME', 'fire', 'flame ', 'water'] LOOP
    BEGIN
      UPDATE nodes SET mark = marked
      WHERE id = 'aaaa0101-0000-0000-0000-000000000000';
      RAISE EXCEPTION 'the CHECK accepted the value ''%''', marked;
    EXCEPTION WHEN check_violation THEN
      -- What it is there for.
    END;
  END LOOP;

  -- Exactly one such constraint, so a re-run has not stacked a second.
  IF (SELECT count(*) FROM pg_constraint
      WHERE conrelid = 'nodes'::regclass AND conname = 'nodes_mark_check') <> 1 THEN
    RAISE EXCEPTION 'expected exactly one nodes_mark_check';
  END IF;
END $$;
SQL

echo "==> checking an upsert that omits mark cannot clear one"
psql <<'SQL'
SET client_min_messages TO warning;

-- A mark set by a build that knows the column.
UPDATE nodes SET mark = 'flame'
WHERE id = 'aaaa0102-0000-0000-0000-000000000000';

-- What PostgREST sends for `upsert` with `Prefer: resolution=merge-duplicates`
-- from a build whose row payload has no `mark` key: the conflict update
-- assigns only the columns that were in the payload.
INSERT INTO nodes (id, user_id, parent_id, title, description, priority, position, color_value, created_at, updated_at)
VALUES ('aaaa0102-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111',
        'aaaa0001-0000-0000-0000-000000000000', 'Review a PR (renamed)', '', 2, 1, NULL,
        '2026-01-03', now())
ON CONFLICT (id) DO UPDATE SET
  parent_id = EXCLUDED.parent_id,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  priority = EXCLUDED.priority,
  position = EXCLUDED.position,
  color_value = EXCLUDED.color_value,
  updated_at = EXCLUDED.updated_at;

DO $$
BEGIN
  IF (SELECT mark FROM nodes WHERE id = 'aaaa0102-0000-0000-0000-000000000000')
     IS DISTINCT FROM 'flame' THEN
    RAISE EXCEPTION 'an upsert that omits mark cleared it';
  END IF;
  IF (SELECT title FROM nodes WHERE id = 'aaaa0102-0000-0000-0000-000000000000')
     <> 'Review a PR (renamed)' THEN
    RAISE EXCEPTION 'the upsert did not apply the columns it did carry';
  END IF;
END $$;

-- The tree as it stands, to compare the second run against.
CREATE TABLE verify_after AS
SELECT id, parent_id, title, priority, position, mark FROM nodes;
SQL

run_file volumes/db/init/008_node_mark.sql

echo "==> checking the second run was a no-op"
psql <<'SQL'
SET client_min_messages TO warning;
DO $$
DECLARE
  drifted BIGINT;
BEGIN
  -- Both directions of the symmetric difference, each parenthesised: EXCEPT
  -- and UNION share a precedence, so without the brackets a row the second
  -- run *added* would slip through. See the same note in verify_006.sh.
  SELECT count(*) INTO drifted FROM (
    (SELECT id, parent_id, title, priority, position, mark FROM nodes
     EXCEPT
     SELECT id, parent_id, title, priority, position, mark FROM verify_after)
    UNION ALL
    (SELECT id, parent_id, title, priority, position, mark FROM verify_after
     EXCEPT
     SELECT id, parent_id, title, priority, position, mark FROM nodes)
  ) diff;
  IF drifted <> 0 THEN
    RAISE EXCEPTION 'the second run changed % row(s)', drifted;
  END IF;
  IF (SELECT count(*) FROM nodes) <> (SELECT count(*) FROM verify_after) THEN
    RAISE EXCEPTION 'the second run changed the row count';
  END IF;
  IF (SELECT count(*) FROM pg_constraint
      WHERE conrelid = 'nodes'::regclass AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%mark%') <> 1 THEN
    RAISE EXCEPTION 'the second run added a second CHECK on mark';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'nodes'::regclass AND conname = 'nodes_mark_check') THEN
    RAISE EXCEPTION 'the second run dropped nodes_mark_check';
  END IF;
END $$;
SQL

echo "==> 008_node_mark.sql verified"
