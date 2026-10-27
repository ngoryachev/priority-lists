-- The role the user is currently in (father / partner / professional / creator
-- / life owner / myself), one row per user.
--
-- A pure marker: nothing else in the schema references it. It lives server-side
-- only so the pick survives a restart and follows the user across devices.
-- The previous role is not history, so the row is overwritten in place.
--
-- Like 002-004 this file is not mounted by docker-compose; it is applied by
-- supabase/scripts/apply_migrations.sh, which the Deploy workflow runs — so
-- nothing manual is needed on the VPS.

CREATE TABLE IF NOT EXISTS user_role (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_role ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own role" ON user_role;
CREATE POLICY "Users can view own role"
  ON user_role FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own role" ON user_role;
CREATE POLICY "Users can insert own role"
  ON user_role FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own role" ON user_role;
CREATE POLICY "Users can update own role"
  ON user_role FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- No DELETE policy: there is one row per user and picking another role
-- overwrites it, so nothing ever needs removing.
