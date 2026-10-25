-- Apply after UPDATE_GACHA_CURRENT_RATING.sql.
-- Returns CURRENT rating and effective gacha tier (independent of unlocked theme).
create or replace function public.gacha_current_bonus(p_qr_token text)
returns table(rating integer,rank_level integer,rank_name text)
language plpgsql security definer set search_path=public as $$
declare v_member uuid;v_tournament int;v_ring int:=1500;v_rating int;v_rank int;v_row record;
begin
 select m.id into v_member from public.members m where m.qr_token::text=btrim(p_qr_token);
 if v_member is null then raise exception '会員情報を確認できません';end if;
 select p.current_rating into v_tournament from public.poker_rating_profiles p
 where p.member_id=v_member and p.enabled=true and p.games_played>=5;
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
 v_rating:=greatest(coalesce(v_tournament,1500),v_ring);
 v_rank:=case when v_rating>=1800 then 5 when v_rating>=1700 then 4 when v_rating>=1600 then 3 when v_rating>=1500 then 2 when v_rating>=1400 then 1 else 0 end;
 return query select v_rating,v_rank,(array['BRONZE','SILVER','GOLD','PLATINUM','DIAMOND','CROWN'])[v_rank+1];
end $$;
revoke all on function public.gacha_current_bonus(text) from public;
grant execute on function public.gacha_current_bonus(text) to anon,authenticated;
