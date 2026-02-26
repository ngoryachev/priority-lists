-- Priority Lists schema with Row Level Security

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Priority Lists table
CREATE TABLE IF NOT EXISTS priority_lists (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL CHECK (char_length(name) > 0),
  color_value INTEGER NOT NULL,
  priority INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 4),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Priority Items table
CREATE TABLE IF NOT EXISTS priority_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  list_id UUID NOT NULL REFERENCES priority_lists(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL CHECK (char_length(title) > 0),
  description TEXT NOT NULL DEFAULT '',
  priority INTEGER NOT NULL CHECK (priority BETWEEN 1 AND 4),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_priority_lists_user_id ON priority_lists(user_id);
CREATE INDEX idx_priority_items_list_id ON priority_items(list_id);
CREATE INDEX idx_priority_items_user_id ON priority_items(user_id);

-- Row Level Security
ALTER TABLE priority_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE priority_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies for priority_lists
CREATE POLICY "Users can view own lists"
  ON priority_lists FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own lists"
  ON priority_lists FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own lists"
  ON priority_lists FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own lists"
  ON priority_lists FOR DELETE
  USING (auth.uid() = user_id);

-- RLS Policies for priority_items
CREATE POLICY "Users can view own items"
  ON priority_items FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own items"
  ON priority_items FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own items"
  ON priority_items FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own items"
  ON priority_items FOR DELETE
  USING (auth.uid() = user_id);
