-- THE CROWN DAILY GACHA: run once in Supabase SQL Editor.
-- Business day: Asia/Tokyo 05:00 -> next day 04:59:59.
create table if not exists public.daily_gacha_prizes (
 id bigint generated always as identity primary key,
 name text not null,
 weight integer not null check(weight>=0),
 active boolean not null default true
);
insert into public.daily_gacha_prizes(name,weight)
select v.name,v.weight from (values
 ('エントリー5,000円引き',5),('エントリー2,000円引き',20),
 ('飲み放題券',15),('ドリンクチケット',30),
 ('CCリング3,000coinプレゼント（リング1時間プレイ）',5),
 ('リエントリー無料券',5),
 ('CCリング1,000coinプレゼント（リング1時間プレイ）',15),
 ('好きなスタッフとテキーラ乾杯券',5)
) v(name,weight)
where not exists(select 1 from public.daily_gacha_prizes);
-- Synchronize the prize catalog even if the earlier setup SQL was already executed.
-- Preserve historic prize rows for existing draw references; disable old entries.
update public.daily_gacha_prizes set active=false;
insert into public.daily_gacha_prizes(name,weight,active)
values
 ('エントリー5,000円引き',5,true),('エントリー2,000円引き',20,true),
 ('飲み放題券',15,true),('ドリンクチケット',30,true),
 ('CCリング3,000coinプレゼント（リング1時間プレイ）',5,true),
 ('リエントリー無料券',5,true),
 ('CCリング1,000coinプレゼント（リング1時間プレイ）',15,true),
 ('好きなスタッフとテキーラ乾杯券',5,true)
on conflict do nothing;
-- Avoid duplicate active rows when the setup is rerun.
with ranked as (
 select id,row_number() over(partition by name order by id desc) rn
 from public.daily_gacha_prizes where name in
 ('エントリー5,000円引き','エントリー2,000円引き','飲み放題券','ドリンクチケット',
 'CCリング3,000coinプレゼント（リング1時間プレイ）','リエントリー無料券',
 'CCリング1,000coinプレゼント（リング1時間プレイ）','好きなスタッフとテキーラ乾杯券')
)
update public.daily_gacha_prizes p set active=(r.rn=1),weight=case p.name
 when 'エントリー5,000円引き' then 5 when 'エントリー2,000円引き' then 20
 when '飲み放題券' then 15 when 'ドリンクチケット' then 30
 when 'CCリング3,000coinプレゼント（リング1時間プレイ）' then 5
 when 'リエントリー無料券' then 5
 when 'CCリング1,000coinプレゼント（リング1時間プレイ）' then 15
 when '好きなスタッフとテキーラ乾杯券' then 5 else 0 end
from ranked r where p.id=r.id;
create table if not exists public.daily_gacha_draws (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.members(id) on delete cascade,
 business_date date not null,
 prize_id bigint not null references public.daily_gacha_prizes(id),
 prize_name text not null,
 drawn_at timestamptz not null default now(),
 expires_at timestamptz not null,
 used_at timestamptz,
 unique(member_id,business_date)
);
create index if not exists daily_gacha_draws_member_idx on public.daily_gacha_draws(member_id,business_date desc);
alter table public.daily_gacha_prizes enable row level security;
alter table public.daily_gacha_draws enable row level security;
revoke all on public.daily_gacha_prizes from anon,authenticated;
revoke all on public.daily_gacha_draws from anon,authenticated;
create or replace function public.daily_gacha(p_qr_token text, p_draw boolean default false)
returns table(prize_name text, business_date date, expires_at timestamptz, used_at timestamptz, drawn_at timestamptz)
language plpgsql security definer set search_path=public
as $$
declare
 v_member uuid;
 v_date date := ((now() at time zone 'Asia/Tokyo') - interval '5 hours')::date;
 v_exp timestamptz := ((v_date + 1)::timestamp + interval '5 hours') at time zone 'Asia/Tokyo';
 v_total integer;
 v_pick integer;
 v_prize record;
begin
 if p_qr_token is null or length(p_qr_token)<12 then raise exception 'Invalid member token'; end if;
 select m.id into v_member from public.members m where m.qr_token=p_qr_token;
 if v_member is null then raise exception 'Member not found'; end if;
 -- Serialize concurrent requests for the same member, including multiple devices.
 perform pg_advisory_xact_lock(hashtextextended(v_member::text, 918273));
 if p_draw and not exists(select 1 from public.daily_gacha_draws d where d.member_id=v_member and d.business_date=v_date) then
   select coalesce(sum(p.weight),0)::integer into v_total from public.daily_gacha_prizes p where p.active and p.weight>0;
   if v_total<=0 then raise exception 'No available prizes'; end if;
   v_pick := floor(random()*v_total)::integer;
   select p.id,p.name into v_prize from
     (select p.id,p.name,sum(p.weight) over(order by p.id) as cutoff
      from public.daily_gacha_prizes p where p.active and p.weight>0) p
   where p.cutoff>v_pick order by p.cutoff limit 1;
   insert into public.daily_gacha_draws(member_id,business_date,prize_id,prize_name,expires_at)
   values(v_member,v_date,v_prize.id,v_prize.name,v_exp)
   on conflict(member_id,business_date) do nothing;
 end if;
 return query select d.prize_name,d.business_date,d.expires_at,d.used_at,d.drawn_at
 from public.daily_gacha_draws d where d.member_id=v_member and d.business_date=v_date limit 1;
end $$;
revoke all on function public.daily_gacha(text,boolean) from public;
grant execute on function public.daily_gacha(text,boolean) to anon,authenticated;
-- Staff redemption (using SQL Editor until admin UI is added):
-- update public.daily_gacha_draws set used_at=now()
-- where id='DRAW_UUID' and used_at is null and expires_at>now();
