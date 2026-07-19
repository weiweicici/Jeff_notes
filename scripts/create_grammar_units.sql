-- 在 Supabase SQL Editor 中执行此脚本创建 grammar_units 表
-- 创建后执行: dart run scripts/seed_grammar_units.dart

CREATE TABLE IF NOT EXISTS grammar_units (
  id              TEXT PRIMARY KEY,
  part_id         TEXT NOT NULL,
  part_title      TEXT NOT NULL,
  title           TEXT NOT NULL,
  outcomes        TEXT NOT NULL,
  chart           TEXT NOT NULL,
  chinese_guide   TEXT NOT NULL,
  key_rules       TEXT NOT NULL,
  common_mistakes TEXT NOT NULL,
  vocabulary      TEXT NOT NULL,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE grammar_units DISABLE ROW LEVEL SECURITY;
