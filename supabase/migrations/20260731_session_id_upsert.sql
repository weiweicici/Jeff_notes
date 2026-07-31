-- Idempotent Supabase Migration: Add session_id & UNIQUE(user_id, session_id) constraint
-- Schema: public | Table: archives
-- Migration Date: 2026-07-31

-- 1. Add session_id column if it doesn't exist in public.archives
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'archives' 
      AND column_name = 'session_id'
  ) THEN
    ALTER TABLE public.archives ADD COLUMN session_id text NULL;
  END IF;
END $$;

-- 2. Add Unique Constraint for public.archives (user_id, session_id) with strict OID & schema verification
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public' 
      AND t.relname = 'archives' 
      AND c.conname = 'archives_user_id_session_id_key'
  ) THEN
    ALTER TABLE public.archives ADD CONSTRAINT archives_user_id_session_id_key UNIQUE (user_id, session_id);
  END IF;
EXCEPTION
  WHEN duplicate_table THEN NULL;
END $$;

-- 3. Ensure Row Level Security (RLS) policies exist for public.archives
ALTER TABLE public.archives ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own archives" ON public.archives;
CREATE POLICY "Users can read own archives" ON public.archives
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own archives" ON public.archives;
CREATE POLICY "Users can insert own archives" ON public.archives
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own archives" ON public.archives;
CREATE POLICY "Users can update own archives" ON public.archives
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own archives" ON public.archives;
CREATE POLICY "Users can delete own archives" ON public.archives
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_archives_session_id
  ON public.archives (session_id);

-- 4. Legacy Record Compatibility Note:
-- Legacy archives created prior to this migration have session_id IS NULL.
-- Existing records remain fully accessible under their user_id via standard RLS policies.
