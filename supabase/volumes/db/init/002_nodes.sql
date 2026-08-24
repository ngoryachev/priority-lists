-- Unlimited nesting: priority_lists + priority_items collapse into a single
-- self-referencing `nodes` table. A root node (parent_id IS NULL) is what used
-- to be a list; everything below is what used to be an item. There is no type
-- distinction any more, so every node can hold children at any depth.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS nodes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Self-reference is the whole point: deleting a node takes its subtree with it.
  parent_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL CHECK (char_length(title) > 0),
  description TEXT NOT NULL DEFAULT '',
  priority INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 4),
  -- Optional accent colour; NULL means "inherit from the ancestor chain".
  color_value BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT nodes_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE INDEX IF NOT EXISTS idx_nodes_user_id ON nodes(user_id);
CREATE INDEX IF NOT EXISTS idx_nodes_parent_id ON nodes(parent_id);
CREATE INDEX IF NOT EXISTS idx_nodes_user_parent ON nodes(user_id, parent_id);

-- A cycle would make every tree walk (breadcrumbs, subtree counts, cascade
-- delete) hang, and no CHECK can see beyond one row — hence a trigger.
-- It also pins the parent to the same owner, so a node can never be reparented
-- into somebody else's tree.
CREATE OR REPLACE FUNCTION nodes_guard_parent() RETURNS trigger AS $$
DECLARE
  parent_owner UUID;
  cycle_found BOOLEAN;
BEGIN
  IF NEW.parent_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT user_id INTO parent_owner FROM nodes WHERE id = NEW.parent_id;
  IF parent_owner IS NULL THEN
    RAISE EXCEPTION 'parent node % does not exist', NEW.parent_id;
  END IF;
  IF parent_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'parent node % belongs to a different user', NEW.parent_id;
  END IF;

  -- Walk up from the prospective parent: hitting NEW.id means we would close a loop.
  WITH RECURSIVE ancestors AS (
    SELECT id, parent_id FROM nodes WHERE id = NEW.parent_id
    UNION ALL
    SELECT n.id, n.parent_id FROM nodes n JOIN ancestors a ON n.id = a.parent_id
  )
  SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = NEW.id) INTO cycle_found;

  IF cycle_found THEN
    RAISE EXCEPTION 'moving node % under % would create a cycle', NEW.id, NEW.parent_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS nodes_guard_parent_trigger ON nodes;
CREATE TRIGGER nodes_guard_parent_trigger
  BEFORE INSERT OR UPDATE OF parent_id, user_id ON nodes
  FOR EACH ROW EXECUTE FUNCTION nodes_guard_parent();

ALTER TABLE nodes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own nodes" ON nodes;
CREATE POLICY "Users can view own nodes"
  ON nodes FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own nodes" ON nodes;
CREATE POLICY "Users can insert own nodes"
  ON nodes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own nodes" ON nodes;
CREATE POLICY "Users can update own nodes"
  ON nodes FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own nodes" ON nodes;
CREATE POLICY "Users can delete own nodes"
  ON nodes FOR DELETE
  USING (auth.uid() = user_id);

-- Backfill from the two-level tables. Ids are preserved, so re-running this is
-- a no-op. The old tables are left in place as a safety net; nothing reads them.
INSERT INTO nodes (id, user_id, parent_id, title, description, priority, color_value, created_at, updated_at)
SELECT id, user_id, NULL, name, '', priority, color_value, created_at, updated_at
FROM priority_lists
ON CONFLICT (id) DO NOTHING;

INSERT INTO nodes (id, user_id, parent_id, title, description, priority, color_value, created_at, updated_at)
SELECT id, user_id, list_id, title, description, priority, NULL, created_at, updated_at
FROM priority_items
ON CONFLICT (id) DO NOTHING;
