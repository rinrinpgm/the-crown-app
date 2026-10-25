-- THE CROWN rank-based daily gacha. Run once in Supabase SQL Editor.
-- Rank is the member's server-side highest unlocked theme rank (0..5).
create table if not exists public.daily_gacha_rank_weights(
 prize_id bigint not null references public.daily_gacha_prizes(id) on delete cascade,
 rank_level integer not null check(rank_level between 0 and 5),
 weight integer not null check(weight between 0 and 100),
 primary key(prize_id,rank_level)
);
alter table public.daily_gacha_rank_weights enable row level security;
revoke all on public.daily_gacha_rank_weights from anon,authenticated;
-- Set suggested defaults for prizes that have no rank weights yet; preserve existing edits.
with defaults(name,weights) as (values
 ('エントリー5,000円引き',array[5,6,7,8,10,12]),
 ('エントリー2,000円引き',array[20,21,22,23,24,25]),
 ('飲み放題券',array[15,15,15,15,15,15]),
 ('ドリンクチケット',array[30,27,24,21,18,15]),
 ('CCリング3,000coinプレゼント（リング1時間プレイ）',array[5,6,7,8,9,10]),
 ('リエントリー無料券',array[5,6,7,8,9,10]),
 ('CCリング1,000coinプレゼント（リング1時間プレイ）',array[15,14,13,12,10,8]),
 ('好きなスタッフとテキーラ乾杯券',array[5,5,5,5,5,5])
)
insert into public.daily_gacha_rank_weights(prize_id,rank_level,weight)
select p.id,l.i-1,d.weights[l.i] from public.daily_gacha_prizes p
join defaults d on d.name=p.name cross join generate_series(1,6) l(i)
where p.active
on conflict(prize_id,rank_level) do nothing;

create or replace function public.gacha_rank_weights_staff()
returns table(prize_id bigint,rank_level integer,weight integer)
language plpgsql security definer set search_path=public as $$
begin
 perform public.gacha_staff_check();
 return query select w.prize_id,w.rank_level,w.weight from public.daily_gacha_rank_weights w order by w.prize_id,w.rank_level;
end $$;
revoke all on function public.gacha_rank_weights_staff() from public;
grant execute on function public.gacha_rank_weights_staff() to authenticated;

create or replace function public.gacha_rank_weights_save(p_items jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_item jsonb;v_id bigint;v_level int;v_weight int;v_rank int;v_sum int;
begin
 perform public.gacha_staff_check();
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>600 then raise exception 'Invalid rank weight data';end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_id:=(v_item->>'prize_id')::bigint;v_level:=(v_item->>'rank_level')::int;v_weight:=(v_item->>'weight')::int;
  if v_level not between 0 and 5 or v_weight not between 0 and 100
   or not exists(select 1 from public.daily_gacha_prizes p where p.id=v_id)
  then raise exception 'Invalid rank weight';end if;
  insert into public.daily_gacha_rank_weights(prize_id,rank_level,weight)
  values(v_id,v_level,v_weight)
  on conflict(prize_id,rank_level) do update set weight=excluded.weight;
 end loop;
 for v_rank in 0..5 loop
  select coalesce(sum(coalesce(w.weight,p.weight)),0)::int into v_sum
  from public.daily_gacha_prizes p
  left join public.daily_gacha_rank_weights w on w.prize_id=p.id and w.rank_level=v_rank
  where p.active;
  if v_sum<>100 then raise exception 'Rank % probabilities total %, expected 100',v_rank,v_sum;end if;
 end loop;
end $$;
revoke all on function public.gacha_rank_weights_save(jsonb) from public;
grant execute on function public.gacha_rank_weights_save(jsonb) to authenticated;

-- Existing signature and return fields preserved for the customer UI.
create or replace function public.daily_gacha(p_qr_token text,p_draw boolean default false)
returns table(prize_name text,business_date date,expires_at timestamptz,used_at timestamptz,drawn_at timestamptz)
language plpgsql security definer set search_path=public as $$
declare
 v_member uuid;
 v_date date:=((now() at time zone 'Asia/Tokyo')-interval '5 hours')::date;
 v_exp timestamptz:=((v_date+1)::timestamp+interval '5 hours') at time zone 'Asia/Tokyo';
 v_rank int:=0;v_total int;v_pick int;v_prize record;
begin
 if nullif(btrim(p_qr_token),'') is null then raise exception '会員情報がありません';end if;
 select m.id into v_member from public.members m where m.qr_token::text=btrim(p_qr_token);
 if v_member is null then raise exception '会員情報を確認できません';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_member::text,918273));
 if p_draw and not exists(select 1 from public.daily_gacha_draws d where d.member_id=v_member and d.business_date=v_date) then
  select least(5,greatest(0,coalesce(t.peak_level,0))) into v_rank
  from public.member_theme_preferences t where t.member_id=v_member;
  v_rank:=coalesce(v_rank,0);
  select coalesce(sum(coalesce(w.weight,p.weight)),0)::int into v_total
  from public.daily_gacha_prizes p
  left join public.daily_gacha_rank_weights w on w.prize_id=p.id and w.rank_level=v_rank
  where p.active;
  if v_total<>100 then raise exception 'ガチャ確率の合計が100%%ではありません（ランク%: %）',v_rank,v_total;end if;
  v_pick:=floor(random()*v_total)::int;
  select q.id,q.name into v_prize from (
   select p.id,p.name,sum(coalesce(w.weight,p.weight)) over(order by p.id) as cutoff
   from public.daily_gacha_prizes p
   left join public.daily_gacha_rank_weights w on w.prize_id=p.id and w.rank_level=v_rank
   where p.active
  ) q where q.cutoff>v_pick order by q.cutoff limit 1;
  insert into public.daily_gacha_draws(member_id,business_date,prize_id,prize_name,expires_at)
  values(v_member,v_date,v_prize.id,v_prize.name,v_exp)
  on conflict on constraint daily_gacha_draws_member_id_business_date_key do nothing;
 end if;
 return query select d.prize_name,d.business_date,d.expires_at,d.used_at,d.drawn_at
 from public.daily_gacha_draws d where d.member_id=v_member and d.business_date=v_date limit 1;
end $$;
revoke all on function public.daily_gacha(text,boolean) from public;
grant execute on function public.daily_gacha(text,boolean) to anon,authenticated;
