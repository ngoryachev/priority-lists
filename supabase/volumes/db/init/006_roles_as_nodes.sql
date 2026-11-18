-- Roles become the tree's top-level nodes.
--
-- The app used to keep "the hat the user is wearing" in `user_role` — a fixed
-- list of six hard-coded roles. Now a role is simply a top-level node of the
-- tree: the chip bar is one chip per top-level node, the red one is the active
-- role, and the main screen lists that role's children. So every account needs
-- a top-level node to hang its existing tree off.
--
-- For each user that has rows in `nodes`: insert one top-level node titled
-- 'Root' (priority 1, position 0), re-parent all of that user's previous
-- top-level nodes under it, keeping their titles, priorities and positions,
-- and then keep exactly one `critical` among them — the app treats two red
-- children of one parent as impossible, and demotes the losers to 2 (high).
--
-- Accounts with no rows in `nodes` at all are left alone: the app creates the
-- default 'Root' role itself on the first load of an empty tree, through
-- whichever repository is active (which also covers the local, file-backed
-- ones, that no migration can reach).
--
-- `user_role` is left in place and 005 stays as it is: nothing reads that
-- table any more, and dropping it would make this migration destructive for no
-- gain.
--
-- Must run inside a single transaction and exactly once, which is what
-- supabase/scripts/apply_migrations.sh does (`psql --single-transaction`
-- together with the `deploy.applied_migrations` ledger row). It is written to
-- be safe to re-run anyway: the guard below skips every user whose only
-- top-level node is already a 'Root', which is the end state this produces.
--
-- Checked against a throwaway database by supabase/scripts/verify_006.sh.

-- Which Root belongs to which user, for the two statements after the insert.
CREATE TEMP TABLE roots_added (
  root_id UUID PRIMARY KEY,
  user_id UUID NOT NULL
);

WITH targets AS (
  -- Users still in the old shape. After this migration a user's only
  -- top-level node is the Root it creates, so a user who already has exactly
  -- one top-level node titled 'Root' is skipped — which makes a second run a
  -- no-op, and is also the right end state for anyone who happened to have
  -- named their single root 'Root' themselves.
  SELECT user_id
  FROM nodes
  WHERE parent_id IS NULL
  GROUP BY user_id
  HAVING count(*) <> 1 OR min(title) <> 'Root'
), inserted AS (
  -- The Root goes in first, so the UPDATE below finds it: nodes_guard_parent
  -- rejects a parent that does not exist or belongs to another user, hence
  -- user_id carried over from the owner's own rows.
  INSERT INTO nodes (user_id, parent_id, title, priority, position)
  SELECT user_id, NULL, 'Root', 1, 0 FROM targets
  RETURNING id, user_id
)
INSERT INTO roots_added (root_id, user_id)
SELECT id, user_id FROM inserted;

-- The old top level becomes the Root's children, keeping title, priority and
-- position — the order the user arranged is the order they keep.
UPDATE nodes n
SET parent_id = r.root_id, updated_at = now()
FROM roots_added r
WHERE n.user_id = r.user_id
  AND n.parent_id IS NULL
  AND n.id <> r.root_id;

-- `critical` is exclusive among siblings, and the moved nodes are siblings
-- now. Keep the first one (by position, then age — the same order the app
-- sorts a level by) and demote the rest, which is what the app's own eviction
-- does when a node claims the red slot.
WITH reds AS (
  SELECT n.id,
         row_number() OVER (
           PARTITION BY n.parent_id
           ORDER BY n.position, n.created_at
         ) AS seq
  FROM nodes n
  JOIN roots_added r ON n.parent_id = r.root_id
  WHERE n.priority = 1
)
UPDATE nodes n
SET priority = 2, updated_at = now()
FROM reds
WHERE n.id = reds.id AND reds.seq > 1;

DROP TABLE roots_added;
