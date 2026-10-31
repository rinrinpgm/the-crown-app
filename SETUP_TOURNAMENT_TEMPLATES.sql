-- Run once in Supabase SQL Editor. Staff-only reusable tournament templates.
create table if not exists public.tournament_templates(
 id uuid primary key default gen_random_uuid(),
 name text not null,
 start_time time not null,
 late_reg_time time,
 entry_fee integer,
 reentry_fee integer,
 starting_stack integer,
 reentry_stack integer,
 prize text,
 description text,
 image_url text,
 created_at timestamptz not null default now()
);
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

alter table public.tournament_templates enable row level security;
revoke all on public.tournament_templates from anon,authenticated;
create or replace function public.staff_tournament_templates()
returns setof public.tournament_templates language plpgsql security definer set search_path=public as $$
begin
 perform public.gacha_staff_check();
 return query select * from public.tournament_templates order by name,created_at;
end $$;
create or replace function public.staff_save_tournament_template(p_data jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_name text;v_start time;
begin
 perform public.gacha_staff_check();
 v_id=nullif(p_data->>'id','')::uuid;
 v_name=trim(p_data->>'name');v_start=(p_data->>'start_time')::time;
 if length(v_name)<1 or length(v_name)>150 or v_start is null then raise exception '名前と開始時間を入力してください';end if;
 if v_id is null then
  insert into public.tournament_templates(name,start_time,late_reg_time,entry_fee,reentry_fee,starting_stack,reentry_stack,prize,description,image_url)
  values(v_name,v_start,nullif(p_data->>'late_reg_time','')::time,nullif(p_data->>'entry_fee','')::integer,nullif(p_data->>'reentry_fee','')::integer,nullif(p_data->>'starting_stack','')::integer,nullif(p_data->>'reentry_stack','')::integer,p_data->>'prize',p_data->>'description',p_data->>'image_url')
  returning id into v_id;
 else
  update public.tournament_templates set name=v_name,start_time=v_start,late_reg_time=nullif(p_data->>'late_reg_time','')::time,entry_fee=nullif(p_data->>'entry_fee','')::integer,reentry_fee=nullif(p_data->>'reentry_fee','')::integer,starting_stack=nullif(p_data->>'starting_stack','')::integer,reentry_stack=nullif(p_data->>'reentry_stack','')::integer,prize=p_data->>'prize',description=p_data->>'description',image_url=p_data->>'image_url'
  where id=v_id;
  if not found then raise exception 'テンプレートが見つかりません';end if;
 end if;
 return v_id;
end $$;
create or replace function public.staff_delete_tournament_template(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.gacha_staff_check();
 delete from public.tournament_templates where id=p_id;
end $$;
revoke all on function public.staff_tournament_templates() from public;
revoke all on function public.staff_save_tournament_template(jsonb) from public;
revoke all on function public.staff_delete_tournament_template(uuid) from public;
grant execute on function public.staff_tournament_templates() to authenticated;
grant execute on function public.staff_save_tournament_template(jsonb) to authenticated;
grant execute on function public.staff_delete_tournament_template(uuid) to authenticated;
