-- Manual ordering within a priority group.
--
-- Sorting was (priority, created_at), which gave no way to say "this one first".
-- `position` becomes the tiebreaker inside a priority, with created_at left as
-- the final fallback so ties are still deterministic.

ALTER TABLE nodes ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;

-- Seed positions from the order rows are already displayed in, so nothing
-- appears to move the first time the app writes an explicit order.
WITH ordered AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id, parent_id
           ORDER BY priority, created_at
         ) - 1 AS seq
  FROM nodes
)
UPDATE nodes n
SET position = ordered.seq
FROM ordered
WHERE n.id = ordered.id AND n.position = 0;

CREATE INDEX IF NOT EXISTS idx_nodes_parent_order
  ON nodes(user_id, parent_id, priority, position);
