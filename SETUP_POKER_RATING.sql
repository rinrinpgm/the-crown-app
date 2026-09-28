-- THE CROWN Poker Rating V2.1
-- 6 ranks / 5-game provisional / field-size adjustment / 20pt demotion protection / correction + recalculation
alter table public.members add column if not exists poker_rating_enabled boolean not null default false;
create table if not exists public.poker_rating_profiles (
 member_id uuid primary key references public.members(id) on delete cascade,
 enabled boolean not null default true,current_rating integer not null default 1500,peak_rating integer not null default 1500,
 games_played integer not null default 0,wins integer not null default 0,itm_count integer not null default 0,updated_at timestamptz not null default now()
);
alter table public.poker_rating_profiles add column if not exists current_rank text;
alter table public.poker_rating_profiles add column if not exists peak_rank text;
create table if not exists public.poker_rating_results (
 id uuid primary key default gen_random_uuid(),tournament_id uuid not null references public.tournaments(id) on delete cascade,
 member_id uuid not null references public.members(id) on delete cascade,field_size integer not null check(field_size>=2),
 finish_rank integer not null check(finish_rank>=1),rating_before integer not null,rating_change integer not null,rating_after integer not null,
 formula_version integer not null default 3,created_at timestamptz not null default now(),unique(tournament_id,member_id)
);
alter table public.poker_rating_results add column if not exists itm_count integer not null default 0;
alter table public.poker_rating_profiles enable row level security;
alter table public.poker_rating_results enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='poker_rating_profiles' and policyname='staff manage rating profiles') then
  create policy "staff manage rating profiles" on public.poker_rating_profiles for all to authenticated using (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true)) with check (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true));
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='poker_rating_results' and policyname='staff manage rating results') then
  create policy "staff manage rating results" on public.poker_rating_results for all to authenticated using (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true)) with check (exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active=true));
 end if;
end $$;
grant select,insert,update,delete on public.poker_rating_profiles,public.poker_rating_results to authenticated;

create or replace function public.poker_rating_rank(p_rating integer) returns text language sql immutable as $$
 select case when p_rating>=1800 then 'CROWN' when p_rating>=1700 then 'DIAMOND' when p_rating>=1600 then 'PLATINUM' when p_rating>=1500 then 'GOLD' when p_rating>=1400 then 'SILVER' else 'BRONZE' end
$$;
create or replace function public.poker_rating_next_rank(p_current text,p_rating integer) returns text language plpgsql immutable as $$
begin
 if p_current is null then return public.poker_rating_rank(p_rating); end if;
 case p_current
  when 'BRONZE' then if p_rating>=1400 then return 'SILVER'; else return 'BRONZE'; end if;
  when 'SILVER' then if p_rating>=1500 then return 'GOLD'; elsif p_rating<1380 then return 'BRONZE'; else return 'SILVER'; end if;
  when 'GOLD' then if p_rating>=1600 then return 'PLATINUM'; elsif p_rating<1480 then return 'SILVER'; else return 'GOLD'; end if;
  when 'PLATINUM' then if p_rating>=1700 then return 'DIAMOND'; elsif p_rating<1580 then return 'GOLD'; else return 'PLATINUM'; end if;
  when 'DIAMOND' then if p_rating>=1800 then return 'CROWN'; elsif p_rating<1680 then return 'PLATINUM'; else return 'DIAMOND'; end if;
  when 'CROWN' then if p_rating<1780 then return 'DIAMOND'; else return 'CROWN'; end if;
  else return public.poker_rating_rank(p_rating);
 end case;
end $$;

create or replace function public.recalculate_poker_ratings() returns void language plpgsql security definer set search_path=public as $$
declare r record;v_before integer;v_games integer;v_actual numeric;v_expected numeric;v_k numeric;v_size numeric;v_change integer;v_after integer;v_rank text;v_peak_rank text;
begin
 if not exists(select 1 from public.staff where auth_user_id=auth.uid() and active=true) then raise exception 'staff only'; end if;
 update public.poker_rating_profiles set current_rating=1500,peak_rating=1500,games_played=0,wins=0,itm_count=0,current_rank=null,peak_rank=null,updated_at=now();
 for r in select pr.*,t.event_date,t.start_time from public.poker_rating_results pr join public.tournaments t on t.id=pr.tournament_id order by t.event_date asc,t.start_time asc,pr.created_at asc,pr.id asc loop
  insert into public.poker_rating_profiles(member_id,enabled) values(r.member_id,true) on conflict(member_id) do nothing;
  select current_rating,games_played,current_rank,peak_rank into v_before,v_games,v_rank,v_peak_rank from public.poker_rating_profiles where member_id=r.member_id for update;
  v_actual:=(r.field_size-r.finish_rank+0.5)/r.field_size::numeric;
  v_expected:=1/(1+power(10::numeric,(1500-v_before)/400::numeric));
  v_k:=case when v_games<5 then 96 else 64 end;
  v_size:=greatest(0.90::numeric,least(1.20::numeric,1+0.12*ln(r.field_size::numeric/10)));
  v_change:=round(v_k*v_size*(v_actual-v_expected));v_after:=v_before+v_change;
  update public.poker_rating_results set rating_before=v_before,rating_change=v_change,rating_after=v_after,formula_version=3 where id=r.id;
  if v_games+1>=5 then
   if v_games+1=5 or v_rank is null then v_rank:=public.poker_rating_rank(v_after); else v_rank:=public.poker_rating_next_rank(v_rank,v_after); end if;
   if v_peak_rank is null or array_position(array['BRONZE','SILVER','GOLD','PLATINUM','DIAMOND','CROWN'],v_rank)>array_position(array['BRONZE','SILVER','GOLD','PLATINUM','DIAMOND','CROWN'],v_peak_rank) then v_peak_rank:=v_rank; end if;
  end if;
  update public.poker_rating_profiles set current_rating=v_after,peak_rating=greatest(peak_rating,v_after),games_played=games_played+1,wins=wins+case when r.finish_rank=1 then 1 else 0 end,itm_count=itm_count+case when r.itm_count>0 and r.finish_rank<=r.itm_count then 1 else 0 end,current_rank=v_rank,peak_rank=v_peak_rank,updated_at=now() where member_id=r.member_id;
 end loop;
end $$;

create or replace function public.finalize_poker_rating_results(p_tournament_id uuid,p_field_size integer,p_itm_count integer,p_results jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb;v_member uuid;v_rank integer;
begin
 if not exists(select 1 from public.staff where auth_user_id=auth.uid() and active=true) then raise exception 'staff only'; end if;
 if p_field_size<2 then raise exception '実プレイヤー数が不正です'; end if;if p_itm_count<0 or p_itm_count>p_field_size then raise exception 'ITM人数が不正です'; end if;
 if exists(select 1 from public.poker_rating_results where tournament_id=p_tournament_id) then raise exception 'この大会はRating確定済みです。修正機能を使用してください'; end if;
 for x in select * from jsonb_array_elements(p_results) loop
  v_member:=(x->>'member_id')::uuid;v_rank:=(x->>'finish_rank')::int;if v_rank<1 or v_rank>p_field_size then raise exception '順位が不正です'; end if;
  insert into public.poker_rating_results(tournament_id,member_id,field_size,itm_count,finish_rank,rating_before,rating_change,rating_after,formula_version) values(p_tournament_id,v_member,p_field_size,p_itm_count,v_rank,1500,0,1500,3);
 end loop;
 perform public.recalculate_poker_ratings();
end $$;

create or replace function public.correct_poker_rating_results(p_tournament_id uuid,p_field_size integer,p_itm_count integer,p_results jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb;v_member uuid;v_rank integer;
begin
 if not exists(select 1 from public.staff where auth_user_id=auth.uid() and active=true) then raise exception 'staff only'; end if;
 if p_field_size<2 then raise exception '実プレイヤー数が不正です'; end if;if p_itm_count<0 or p_itm_count>p_field_size then raise exception 'ITM人数が不正です'; end if;
 delete from public.poker_rating_results where tournament_id=p_tournament_id;
 for x in select * from jsonb_array_elements(p_results) loop
  v_member:=(x->>'member_id')::uuid;v_rank:=(x->>'finish_rank')::int;if v_rank<1 or v_rank>p_field_size then raise exception '順位が不正です'; end if;
  insert into public.poker_rating_results(tournament_id,member_id,field_size,itm_count,finish_rank,rating_before,rating_change,rating_after,formula_version) values(p_tournament_id,v_member,p_field_size,p_itm_count,v_rank,1500,0,1500,3);
 end loop;
 perform public.recalculate_poker_ratings();
end $$;
revoke all on function public.finalize_poker_rating_results(uuid,integer,integer,jsonb) from public;
revoke all on function public.correct_poker_rating_results(uuid,integer,integer,jsonb) from public;
revoke all on function public.recalculate_poker_ratings() from public;
grant execute on function public.finalize_poker_rating_results(uuid,integer,integer,jsonb) to authenticated;
grant execute on function public.correct_poker_rating_results(uuid,integer,integer,jsonb) to authenticated;
grant execute on function public.recalculate_poker_ratings() to authenticated;


-- MY CROWN用：QR本人のRating情報だけ返す
create or replace function public.get_member_rating_by_qr(p_qr_token uuid)
returns table(member_id uuid,enabled boolean,current_rating integer,peak_rating integer,games_played integer,wins integer,itm_count integer,current_rank text,peak_rank text)
language sql security definer set search_path=public as $$
 select p.member_id,p.enabled,p.current_rating,p.peak_rating,p.games_played,p.wins,p.itm_count,p.current_rank,p.peak_rank
 from public.members m join public.poker_rating_profiles p on p.member_id=m.id
 where m.qr_token=p_qr_token and p.enabled=true
 limit 1
$$;
revoke all on function public.get_member_rating_by_qr(uuid) from public;
grant execute on function public.get_member_rating_by_qr(uuid) to anon,authenticated;


-- Rating分析用：QR本人の履歴だけ返す
create or replace function public.get_member_rating_history_by_qr(p_qr_token uuid)
returns table(event_date date,tournament_name text,field_size integer,finish_rank integer,itm_count integer,rating_before integer,rating_change integer,rating_after integer)
language sql security definer set search_path=public as $$
 select t.event_date,t.name::text,r.field_size,r.finish_rank,r.itm_count,r.rating_before,r.rating_change,r.rating_after
 from public.members m
 join public.poker_rating_results r on r.member_id=m.id
 join public.tournaments t on t.id=r.tournament_id
 where m.qr_token=p_qr_token
 order by t.event_date asc,t.start_time asc,r.created_at asc
$$;
revoke all on function public.get_member_rating_history_by_qr(uuid) from public;
grant execute on function public.get_member_rating_history_by_qr(uuid) to anon,authenticated;
