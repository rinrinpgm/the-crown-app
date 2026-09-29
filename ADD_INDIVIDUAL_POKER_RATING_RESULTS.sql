-- Run once in Supabase SQL Editor after SETUP_POKER_RATING.sql.
-- Each result is written atomically and all later ratings are recalculated.
create or replace function public.staff_save_poker_rating_result(
 p_tournament_id uuid,p_member_id uuid,p_field_size integer,p_itm_count integer,p_finish_rank integer
) returns void language plpgsql security definer set search_path=public as $$
declare v_existing public.poker_rating_results%rowtype;
begin
 if not exists(select 1 from public.staff where auth_user_id=auth.uid() and active=true) then raise exception 'staff only'; end if;
 if not exists(select 1 from public.tournaments where id=p_tournament_id) then raise exception '大会が見つかりません'; end if;
 if not exists(select 1 from public.poker_rating_profiles where member_id=p_member_id and enabled=true) then raise exception 'Rating対象者ではありません'; end if;
 if p_field_size is null or p_field_size<2 then raise exception '実プレイヤー数が不正です'; end if;
 if p_itm_count is null or p_itm_count<0 or p_itm_count>p_field_size then raise exception 'ITM人数が不正です'; end if;
 if p_finish_rank is null or p_finish_rank<1 or p_finish_rank>p_field_size then raise exception '順位が不正です'; end if;
 -- Serialize saves to prevent two simultaneous confirmations assigning the same rank.
 perform pg_advisory_xact_lock(hashtextextended(p_tournament_id::text,0));
 select * into v_existing from public.poker_rating_results where tournament_id=p_tournament_id and member_id=p_member_id;
 if exists(select 1 from public.poker_rating_results where tournament_id=p_tournament_id and (field_size<>p_field_size or itm_count<>p_itm_count)) then
  raise exception '確定済みの大会です。実プレイヤー数・ITM人数を変更する場合は履歴の「この結果を修正」を使用してください';
 end if;
 if exists(select 1 from public.poker_rating_results where tournament_id=p_tournament_id and member_id<>p_member_id and finish_rank=p_finish_rank) then
  raise exception 'その順位は別のRating対象者で確定済みです';
 end if;
 if v_existing.id is null then
  insert into public.poker_rating_results(tournament_id,member_id,field_size,itm_count,finish_rank,rating_before,rating_change,rating_after,formula_version)
  values(p_tournament_id,p_member_id,p_field_size,p_itm_count,p_finish_rank,1500,0,1500,3);
 else
  update public.poker_rating_results set finish_rank=p_finish_rank where id=v_existing.id;
 end if;
 perform public.recalculate_poker_ratings();
end $$;
revoke all on function public.staff_save_poker_rating_result(uuid,uuid,integer,integer,integer) from public;
grant execute on function public.staff_save_poker_rating_result(uuid,uuid,integer,integer,integer) to authenticated;
