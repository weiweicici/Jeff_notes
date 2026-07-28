-- Run this in Supabase SQL Editor (https://supabase.com/dashboard/project/cplqrewuoltiechxxtjk/sql/new)
-- 1. Add user_id column for per-user data isolation
ALTER TABLE archives ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();

-- 2. Enable Row-Level Security
ALTER TABLE archives ENABLE ROW LEVEL SECURITY;

-- 3. Drop any existing policies (safe to re-run)
DROP POLICY IF EXISTS "Users can view their own archives" ON archives;
DROP POLICY IF EXISTS "Users can insert their own archives" ON archives;
DROP POLICY IF EXISTS "Users can update their own archives" ON archives;
DROP POLICY IF EXISTS "Users can delete their own archives" ON archives;

-- 4. Create per-user policies
-- SELECT: only rows belonging to the authenticated user
CREATE POLICY "Users can view their own archives"
  ON archives FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT: only if the inserted row belongs to the authenticated user
CREATE POLICY "Users can insert their own archives"
  ON archives FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: only rows belonging to the authenticated user
CREATE POLICY "Users can update their own archives"
  ON archives FOR UPDATE
  USING (auth.uid() = user_id);

-- DELETE: only rows belonging to the authenticated user
CREATE POLICY "Users can delete their own archives"
  ON archives FOR DELETE
  USING (auth.uid() = user_id);

-- 5. Backfill user_id for existing rows (sets to NULL since no user owns them yet)
-- These rows will be inaccessible after RLS is enabled.
-- If you want to keep existing data, you'll need to assign them to your new anonymous user.
-- Run: UPDATE archives SET user_id = 'YOUR_NEW_USER_UUID' WHERE user_id IS NULL;
