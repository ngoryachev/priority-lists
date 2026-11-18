-- Where the user is looking, one row per user, so it follows them across
-- devices: the level that was last on screen and the page every card was
-- swiped to.
--
-- A pure marker, like 005's `user_role`: nothing references it and the tree
-- never reads it. Overwritten in place; the previous position is not history.
--
-- * last_node_id — the node whose children were on screen; NULL is the main
--   screen. Deliberately no foreign key to `nodes`: a node deleted elsewhere
--   just makes the app open at the main screen, and the pointer is dropped
--   by the app itself.
-- * card_pages — `{ "<node id>": "<child id>" }` for every card that is not
--   on its own face (page 0).
--
-- Applied by supabase/scripts/apply_migrations.sh, which the Deploy workflow
-- runs; safe to re-run.

CREATE TABLE IF NOT EXISTS user_view_state (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  last_node_id TEXT,
  card_pages JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_view_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own view state" ON user_view_state;
CREATE POLICY "Users can view own view state"
  ON user_view_state FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own view state" ON user_view_state;
CREATE POLICY "Users can insert own view state"
  ON user_view_state FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own view state" ON user_view_state;
CREATE POLICY "Users can update own view state"
  ON user_view_state FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: one row per user, always overwritten.
