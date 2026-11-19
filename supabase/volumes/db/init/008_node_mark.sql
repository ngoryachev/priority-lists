-- A node's working state, orthogonal to its 1-4 priority.
--
-- Priority says how much something matters; the mark says what is happening to
-- it right now: 'flame' (in progress) or 'ice' (blocked / waiting). The app
-- lifts a marked node out of its level's card list and pins it above it.
--
-- Nullable with no default and no backfill: every existing row is unmarked,
-- which is exactly what NULL already means. The CHECK is what keeps the column
-- an enum rather than free text — the two values are spelt out in
-- lib/domain/models/node_mark.dart.
--
-- Nothing else is touched: priority, position and created_at are none of this
-- migration's business, and a build that does not know the column omits it
-- from its upsert payload, which PostgREST turns into an ON CONFLICT update
-- that assigns no `mark` — so an old client cannot clear a mark set elsewhere.
--
-- Applied by supabase/scripts/apply_migrations.sh, which the Deploy workflow
-- runs; safe to re-run. Verified by supabase/scripts/verify_008.sh.

ALTER TABLE nodes ADD COLUMN IF NOT EXISTS mark TEXT;

-- ADD CONSTRAINT has no IF NOT EXISTS, so the guard is explicit; without it a
-- second run of the file would fail instead of being the no-op it has to be.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'nodes_mark_check'
      AND conrelid = 'nodes'::regclass
  ) THEN
    ALTER TABLE nodes
      ADD CONSTRAINT nodes_mark_check
      CHECK (mark IS NULL OR mark IN ('flame', 'ice'));
  END IF;
END $$;
