#!/usr/bin/env bash
# Runs 006_roles_as_nodes.sql for real against a throwaway Postgres container
# and asserts what it did.
#
# Pushing to main applies pending migrations to production data, so this one
# has to be right the first time. The container is created here, never
# published to a port, and removed on exit — nothing outside Docker is touched.
#
#   supabase/scripts/verify_006.sh
#
# What it checks, after seeding two users in the old shape (one of them with
# two `critical` top-level nodes) and one user with no nodes at all:
#   * exactly one top-level node per seeded user, titled 'Root', priority 1
#   * every former top-level node re-parented under that Root, with its title,
#     priority (bar the demoted reds) and position intact
#   * at most one `critical` per parent, the survivor being the first by
#     (position, created_at)
#   * the deeper levels untouched, and the node-less user still node-less
#   * a second run of the file changing nothing at all
#
# It stubs `auth.users` and `auth.uid()` rather than running the whole Supabase
# stack: the migration runs as `postgres` and so bypasses RLS anyway, what it
# needs from the schema is the `nodes` table and its guard trigger.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly image="postgres:16"
readonly container="priority-lists-verify-006-$$"

cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> starting $container ($image)"
docker run --rm -d --name "$container" \
  -e POSTGRES_PASSWORD=verify-006 "$image" >/dev/null

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

echo "==> stubbing the Supabase bits 001-005 lean on"
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
  volumes/db/init/005_current_role.sql; do
  run_file "$file"
done

echo "==> seeding two users in the old shape and one with nothing"
psql <<'SQL'
SET client_min_messages TO warning;

INSERT INTO auth.users (id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333');

-- User 1: four top-level nodes, two of them critical (which the app treats as
-- impossible for one parent, but older data can hold), each with children.
INSERT INTO nodes (id, user_id, parent_id, title, priority, position, created_at)
VALUES
  ('aaaa0001-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', NULL, 'Work',    1, 0, '2026-01-01'),
  ('aaaa0002-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', NULL, 'Home',    1, 1, '2026-01-02'),
  ('aaaa0003-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', NULL, 'Someday', 4, 2, '2026-01-03'),
  ('aaaa0004-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', NULL, 'Health',  3, 3, '2026-01-04'),
  ('aaaa0101-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0001-0000-0000-0000-000000000000', 'Fix the build', 1, 0, '2026-01-05'),
  ('aaaa0102-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0001-0000-0000-0000-000000000000', 'Review a PR',   2, 1, '2026-01-06'),
  ('aaaa0103-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0101-0000-0000-0000-000000000000', 'A grandchild',  3, 0, '2026-01-07'),
  ('aaaa0201-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'aaaa0002-0000-0000-0000-000000000000', 'Buy milk',      4, 0, '2026-01-08');

-- User 2: a single top-level node, not named 'Root', with one child.
INSERT INTO nodes (id, user_id, parent_id, title, priority, position, created_at)
VALUES
  ('bbbb0001-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', NULL, 'Inbox', 2, 0, '2026-02-01'),
  ('bbbb0101-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'bbbb0001-0000-0000-0000-000000000000', 'Something', 3, 0, '2026-02-02');

-- What the top level looked like, to compare against afterwards.
CREATE TABLE verify_before AS
SELECT id, user_id, title, priority, position FROM nodes WHERE parent_id IS NULL;
SQL

run_file volumes/db/init/006_roles_as_nodes.sql

echo "==> checking what it did"
psql <<'SQL'
SET client_min_messages TO warning;
DO $$
DECLARE
  offenders TEXT;
BEGIN
  -- One Root per seeded user, and nothing else at the top level.
  SELECT string_agg(format('%s has %s top-level nodes', user_id, n), ', ')
  INTO offenders
  FROM (
    SELECT user_id, count(*) AS n FROM nodes WHERE parent_id IS NULL
    GROUP BY user_id
  ) counts
  WHERE n <> 1;
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'not exactly one top-level node per user: %', offenders;
  END IF;

  SELECT string_agg(format('%s: %s', id, title), ', ') INTO offenders
  FROM nodes
  WHERE parent_id IS NULL AND (title <> 'Root' OR priority <> 1 OR position <> 0);
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'a top-level node that is not a red Root at 0: %', offenders;
  END IF;

  -- The user with no nodes gained none.
  IF EXISTS (
    SELECT 1 FROM nodes WHERE user_id = '33333333-3333-3333-3333-333333333333'
  ) THEN
    RAISE EXCEPTION 'the node-less user was given a Root it never needed';
  END IF;

  -- Every former top-level node now hangs off its owner's Root.
  SELECT string_agg(b.id::TEXT, ', ') INTO offenders
  FROM verify_before b
  JOIN nodes n ON n.id = b.id
  LEFT JOIN nodes root ON root.id = n.parent_id
  WHERE root.parent_id IS NOT NULL
     OR root.user_id <> b.user_id
     OR root.title <> 'Root';
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'former roots not re-parented under their Root: %', offenders;
  END IF;

  -- Titles and positions survived untouched.
  SELECT string_agg(b.id::TEXT, ', ') INTO offenders
  FROM verify_before b
  JOIN nodes n ON n.id = b.id
  WHERE n.title <> b.title OR n.position <> b.position;
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'title or position changed on: %', offenders;
  END IF;

  -- So did the priorities, bar the reds that had to give way.
  SELECT string_agg(format('%s: %s -> %s', b.id, b.priority, n.priority), ', ')
  INTO offenders
  FROM verify_before b
  JOIN nodes n ON n.id = b.id
  WHERE n.priority <> b.priority AND NOT (b.priority = 1 AND n.priority = 2);
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'priority changed where it should not have: %', offenders;
  END IF;

  -- At most one red child per parent, anywhere in the tree. Per user too:
  -- a client only ever sees its own rows, so the top level of one user's tree
  -- is not a level it shares with anybody.
  SELECT string_agg(
           format('%s / %s has %s red children', user_id, parent_id, n), ', '
         )
  INTO offenders
  FROM (
    SELECT user_id, parent_id, count(*) AS n FROM nodes WHERE priority = 1
    GROUP BY user_id, parent_id
  ) reds
  WHERE n > 1;
  IF offenders IS NOT NULL THEN
    RAISE EXCEPTION 'two red siblings: %', offenders;
  END IF;

  -- The red that survived is the first by (position, created_at): 'Work' came
  -- before 'Home', so 'Home' is the one that was demoted.
  IF (SELECT priority FROM nodes WHERE id = 'aaaa0001-0000-0000-0000-000000000000') <> 1 THEN
    RAISE EXCEPTION 'the first red by (position, created_at) was not the one kept';
  END IF;
  IF (SELECT priority FROM nodes WHERE id = 'aaaa0002-0000-0000-0000-000000000000') <> 2 THEN
    RAISE EXCEPTION 'the second red was not demoted to high';
  END IF;

  -- Deeper levels are none of this migration's business.
  IF (SELECT count(*) FROM nodes WHERE parent_id = 'aaaa0001-0000-0000-0000-000000000000') <> 2
     OR (SELECT priority FROM nodes WHERE id = 'aaaa0101-0000-0000-0000-000000000000') <> 1
     OR (SELECT parent_id FROM nodes WHERE id = 'aaaa0103-0000-0000-0000-000000000000')
        <> 'aaaa0101-0000-0000-0000-000000000000' THEN
    RAISE EXCEPTION 'a level below the old top level was disturbed';
  END IF;

  -- Two users had nodes, so exactly two Roots were created.
  IF (SELECT count(*) FROM nodes WHERE title = 'Root') <> 2 THEN
    RAISE EXCEPTION 'expected one Root per seeded user';
  END IF;
END $$;

-- The whole tree as it stands, to compare the second run against.
CREATE TABLE verify_after AS
SELECT id, user_id, parent_id, title, priority, position FROM nodes;
SQL

run_file volumes/db/init/006_roles_as_nodes.sql

echo "==> checking the second run was a no-op"
psql <<'SQL'
SET client_min_messages TO warning;
DO $$
DECLARE
  drifted BIGINT;
BEGIN
  SELECT count(*) INTO drifted FROM (
    SELECT id, user_id, parent_id, title, priority, position FROM nodes
    EXCEPT
    SELECT id, user_id, parent_id, title, priority, position FROM verify_after
    UNION ALL
    SELECT id, user_id, parent_id, title, priority, position FROM verify_after
    EXCEPT
    SELECT id, user_id, parent_id, title, priority, position FROM nodes
  ) diff;
  IF drifted <> 0 THEN
    RAISE EXCEPTION 'the second run changed % row(s)', drifted;
  END IF;
END $$;
SQL

echo "==> 006_roles_as_nodes.sql verified"
