-- Run this after SETUP_RANK_GACHA.sql.
-- Gacha uses CURRENT ratings, never highest achieved rank.
-- Tournament rating requires at least 5 completed games; ring starts at 1500.
create or replace function public.daily_gacha(p_qr_token text,p_draw boolean default false)
returns table(prize_name text,business_date date,expires_at timestamptz,used_at timestamptz,drawn_at timestamptz)
language plpgsql security definer set search_path=public as $$
declare
 v_member uuid;
 v_date date:=((now() at time zone 'Asia/Tokyo')-interval '5 hours')::date;
 v_exp timestamptz:=((v_date+1)::timestamp+interval '5 hours') at time zone 'Asia/Tokyo';
 v_rating int:=1500;v_ring int:=1500;v_tournament int;v_rank int;
 v_total int;v_pick int;v_prize record;v_row record;
begin
 if nullif(btrim(p_qr_token),'') is null then raise exception '会員情報がありません';end if;
 select m.id into v_member from public.members m where m.qr_token::text=btrim(p_qr_token);
 if v_member is null then raise exception '会員情報を確認できません';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_member::text,918273));
 if p_draw and not exists(select 1 from public.daily_gacha_draws d where d.member_id=v_member and d.business_date=v_date) then
  select p.current_rating into v_tournament from public.poker_rating_profiles p
  where p.member_id=v_member and p.enabled=true and p.games_played>=5;
  -- Ring rating uses the same change brackets as the customer MY RING display.
  for v_row in select r.net_change from public.ring_rating_results r
   where r.member_id=v_member order by r.play_date,r.created_at loop
   v_ring:=v_ring+case
    when coalesce(v_row.net_change,0)=0 then 0
    when abs(v_row.net_change)>=100000 then 40*sign(v_row.net_change)
    when abs(v_row.net_change)>=50000 then 30*sign(v_row.net_change)
    when abs(v_row.net_change)>=30000 then 20*sign(v_row.net_change)
    when abs(v_row.net_change)>=10000 then 10*sign(v_row.net_change)
    else 5*sign(v_row.net_change) end;
  end loop;
  -- Use the higher CURRENT rating of the two game formats.
  v_rating:=greatest(coalesce(v_tournament,1500),v_ring);
  v_rank:=case when v_rating>=1800 then 5 when v_rating>=1700 then 4
   when v_rating>=1600 then 3 when v_rating>=1500 then 2
   when v_rating>=1400 then 1 else 0 end;
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
