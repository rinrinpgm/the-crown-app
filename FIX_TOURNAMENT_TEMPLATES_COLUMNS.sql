-- Fix existing tournament_templates tables created with an older schema.
-- Safe to run multiple times; existing template rows are preserved.
alter table public.tournament_templates
 add column if not exists late_reg_time time,
 add column if not exists entry_fee integer,
 add column if not exists reentry_fee integer,
 add column if not exists starting_stack integer,
 add column if not exists reentry_stack integer,
 add column if not exists prize text,
 add column if not exists description text,
 add column if not exists image_url text,
 add column if not exists created_at timestamptz default now();
notify pgrst, 'reload schema';
