-- THE CROWN: server-persisted member themes (run once in Supabase SQL Editor)
create table if not exists public.member_theme_preferences (
 member_id uuid primary key references public.members(id) on delete cascade,
 peak_level integer not null default 0 check(peak_level between 0 and 5),
 selected_theme text not null default 'BRONZE' check(selected_theme in ('BRONZE','SILVER','GOLD','PLATINUM','DIAMOND','CROWN')),
 updated_at timestamptz not null default now()
);
alter table public.member_theme_preferences enable row level security;
revoke all on public.member_theme_preferences from anon, authenticated;

create or replace function public.crown_theme_profile(p_qr_token text,p_selected_theme text default null)
returns table(peak_level integer,selected_theme text)
language plpgsql security definer set search_path=public as $$
declare
 v_member uuid;v_rating integer;v_peak integer:=0;v_level integer:=0;
 v_row record;v_selected text;v_current text;v_names text[]:=array['BRONZE','SILVER','GOLD','PLATINUM','DIAMOND','CROWN'];
begin
 select m.id into v_member from public.members m where m.qr_token::text=btrim(p_qr_token);
 if v_member is null then raise exception '会員情報を確認できません';end if;

 select greatest(coalesce(p.peak_rating,0),coalesce(p.current_rating,0)) into v_rating
 from public.poker_rating_profiles p where p.member_id=v_member and p.enabled=true and p.games_played>=5;
 if found then v_peak:=greatest(v_peak,coalesce(v_rating,0));end if;

 -- Reconstruct ring rating using the same day-by-day rule as the customer app.
 v_rating:=1500;
 for v_row in select r.net_change from public.get_member_ring_rating_by_qr(p_qr_token::uuid) r loop
  v_rating:=v_rating+case
   when coalesce(v_row.net_change,0)=0 then 0
   when abs(v_row.net_change)>=100000 then 40*sign(v_row.net_change)
   when abs(v_row.net_change)>=50000 then 30*sign(v_row.net_change)
   when abs(v_row.net_change)>=30000 then 20*sign(v_row.net_change)
   when abs(v_row.net_change)>=10000 then 10*sign(v_row.net_change)
   else 5*sign(v_row.net_change) end;
  v_peak:=greatest(v_peak,v_rating);
 end loop;
 v_level:=case when v_peak>=1800 then 5 when v_peak>=1700 then 4 when v_peak>=1600 then 3 when v_peak>=1500 then 2 when v_peak>=1400 then 1 else 0 end;

 insert into public.member_theme_preferences(member_id,peak_level,selected_theme)
 values(v_member,v_level,v_names[v_level+1])
 on conflict(member_id) do update set
 peak_level=greatest(public.member_theme_preferences.peak_level,excluded.peak_level),
 updated_at=now();

 select p.peak_level,p.selected_theme into v_level,v_current
 from public.member_theme_preferences p where p.member_id=v_member for update;

 if p_selected_theme is not null then
  if not (p_selected_theme=any(v_names)) or array_position(v_names,p_selected_theme)>v_level+1 then
   raise exception '未獲得のテーマは選択できません';
  end if;
  update public.member_theme_preferences p set selected_theme=p_selected_theme,updated_at=now() where p.member_id=v_member;
  v_current:=p_selected_theme;
 elsif array_position(v_names,v_current)>v_level+1 then
  v_current:=v_names[v_level+1];
  update public.member_theme_preferences p set selected_theme=v_current where p.member_id=v_member;
 end if;
 return query select v_level,v_current;
end $$;
revoke all on function public.crown_theme_profile(text,text) from public;
grant execute on function public.crown_theme_profile(text,text) to anon,authenticated;
