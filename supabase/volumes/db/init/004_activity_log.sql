-- Append-only history of tree mutations.
--
-- The app writes one row per change (add / edit / re-prioritise / move /
-- reorder / delete) so the user can look back at what they did on a given day
-- and read it out at a standup. It is a side record: nothing in the tree reads
-- it, and a failed insert here never fails the mutation it describes.
--
-- Like 002 and 003 this file is not mounted by docker-compose; apply it to a
-- running stack with:
--   docker compose exec -T db psql -U postgres -d postgres < volumes/db/init/004_activity_log.sql

CREATE TABLE IF NOT EXISTS activity_log (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  happened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  action TEXT NOT NULL,
  -- No foreign key on purpose: the entry has to outlive the node it describes,
  -- otherwise every delete would erase its own record.
  node_id UUID,
  node_title TEXT NOT NULL DEFAULT '',
  -- Ancestor titles at the time of the change, root first — a snapshot, since
  -- the tree above the node can be renamed or moved later.
  path TEXT[] NOT NULL DEFAULT '{}',
  details TEXT NOT NULL DEFAULT ''
);

-- The only read pattern: my log, newest first, since some date.
CREATE INDEX IF NOT EXISTS idx_activity_log_user_time
  ON activity_log(user_id, happened_at DESC);

ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own activity" ON activity_log;
CREATE POLICY "Users can view own activity"
  ON activity_log FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own activity" ON activity_log;
CREATE POLICY "Users can insert own activity"
  ON activity_log FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Entries are never edited: no UPDATE policy. Deleting own rows stays possible
-- so the user can purge their own history.
DROP POLICY IF EXISTS "Users can delete own activity" ON activity_log;
CREATE POLICY "Users can delete own activity"
  ON activity_log FOR DELETE
  USING (auth.uid() = user_id);
