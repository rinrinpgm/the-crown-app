-- THE CROWN Poker Rating v1
alter table public.members add column if not exists poker_rating_enabled boolean not null default false;
create table if not exists public.poker_rating_profiles (
 member_id uuid primary key references public.members(id) on delete cascade,
 enabled boolean not null default true,
 current_rating integer not null default 1500,
 peak_rating integer not null default 1500,
 games_played integer not null default 0,
 wins integer not null default 0,
 itm_count integer not null default 0,
 updated_at timestamptz not null default now()
);
create table if not exists public.poker_rating_results (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.tournaments(id) on delete cascade,
 member_id uuid not null references public.members(id) on delete cascade,
 field_size integer not null check(field_size>=2),
 finish_rank integer not null check(finish_rank>=1),
 rating_before integer not null,
 rating_change integer not null,
 rating_after integer not null,
 formula_version integer not null default 1,
 created_at timestamptz not null default now(),
 unique(tournament_id,member_id)
);
alter table public.poker_rating_profiles enable row level security;
alter table public.poker_rating_results enable row level security;
create policy "staff manage rating profiles" on public.poker_rating_profiles for all to authenticated using (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true)) with check (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true));
create policy "staff manage rating results" on public.poker_rating_results for all to authenticated using (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true)) with check (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true));
grant select,insert,update,delete on public.poker_rating_profiles,public.poker_rating_results to authenticated;
create or replace function public.finalize_poker_rating_results(p_tournament_id uuid,p_field_size integer,p_results jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb;
begin
 if not exists(select 1 from public.staff where auth_user_id=auth.uid() and active=true) then raise exception 'staff only'; end if;
 if exists(select 1 from public.poker_rating_results where tournament_id=p_tournament_id) then raise exception 'この大会はRating確定済みです'; end if;
 for x in select * from jsonb_array_elements(p_results) loop
  insert into public.poker_rating_results(tournament_id,member_id,field_size,finish_rank,rating_before,rating_change,rating_after,formula_version)
  values(p_tournament_id,(x->>'member_id')::uuid,p_field_size,(x->>'finish_rank')::int,(x->>'rating_before')::int,(x->>'rating_change')::int,(x->>'rating_after')::int,coalesce((x->>'formula_version')::int,1));
  insert into public.poker_rating_profiles(member_id,enabled,current_rating,peak_rating,games_played,wins,itm_count,updated_at)
  values((x->>'member_id')::uuid,true,(x->>'rating_after')::int,greatest(1500,(x->>'rating_after')::int),1,case when (x->>'finish_rank')::int=1 then 1 else 0 end,case when (x->>'finish_rank')::int<=greatest(1,ceil(p_field_size*.15)) then 1 else 0 end,now())
  on conflict(member_id) do update set current_rating=excluded.current_rating,peak_rating=greatest(poker_rating_profiles.peak_rating,excluded.current_rating),games_played=poker_rating_profiles.games_played+1,wins=poker_rating_profiles.wins+excluded.wins,itm_count=poker_rating_profiles.itm_count+excluded.itm_count,updated_at=now();
 end loop;
end $$;
revoke all on function public.finalize_poker_rating_results(uuid,integer,jsonb) from public;
grant execute on function public.finalize_poker_rating_results(uuid,integer,jsonb) to authenticated;
