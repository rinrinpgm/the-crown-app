-- Run once in Supabase SQL Editor
create table if not exists public.customer_tabs(id uuid primary key default gen_random_uuid(),member_id uuid not null references public.members(id) on delete cascade,status text not null default 'open' check(status in('open','paid','cancelled')),opened_at timestamptz not null default now(),closed_at timestamptz,opened_by uuid);
create unique index if not exists one_open_tab_per_member on public.customer_tabs(member_id) where status='open';
create table if not exists public.tab_items(id uuid primary key default gen_random_uuid(),tab_id uuid not null references public.customer_tabs(id) on delete cascade,item_name text not null,quantity integer not null default 1,unit_price numeric not null default 0,amount numeric not null default 0,source text not null default 'staff',order_id uuid,created_at timestamptz not null default now(),voided boolean not null default false,voided_at timestamptz);
create table if not exists public.order_menu(id uuid primary key default gen_random_uuid(),name text not null,price numeric not null default 0,category text default 'ドリンク',active boolean not null default true,display_order integer not null default 0,created_at timestamptz not null default now());
create table if not exists public.customer_orders(id uuid primary key default gen_random_uuid(),tab_id uuid not null references public.customer_tabs(id) on delete cascade,member_id uuid not null references public.members(id) on delete cascade,menu_id uuid references public.order_menu(id),item_name text not null,quantity integer not null default 1,unit_price numeric not null default 0,status text not null default 'new' check(status in('new','accepted','served','cancelled')),created_at timestamptz not null default now(),served_at timestamptz);
create table if not exists public.ring_sessions(id uuid primary key default gen_random_uuid(),tab_id uuid not null references public.customer_tabs(id) on delete cascade,member_id uuid not null references public.members(id) on delete cascade,status text not null default 'open',opened_at timestamptz not null default now(),closed_at timestamptz,net_result numeric);
create table if not exists public.ring_movements(id uuid primary key default gen_random_uuid(),session_id uuid not null references public.ring_sessions(id) on delete cascade,kind text not null check(kind in('withdraw','deposit')),chips numeric not null check(chips>0),created_at timestamptz not null default now());
alter table public.customer_tabs enable row level security;alter table public.tab_items enable row level security;alter table public.order_menu enable row level security;alter table public.customer_orders enable row level security;alter table public.ring_sessions enable row level security;alter table public.ring_movements enable row level security;
do $$ begin create policy "staff tabs" on public.customer_tabs for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "member tabs" on public.customer_tabs for select to authenticated using(exists(select 1 from public.members m where m.id=member_id and m.auth_user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy "staff items" on public.tab_items for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "member items" on public.tab_items for select to authenticated using(exists(select 1 from public.customer_tabs t join public.members m on m.id=t.member_id where t.id=tab_id and m.auth_user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy "menu read" on public.order_menu for select to authenticated using(active=true); exception when duplicate_object then null; end $$;
do $$ begin create policy "staff menu" on public.order_menu for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "staff orders" on public.customer_orders for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "member order insert" on public.customer_orders for insert to authenticated with check(exists(select 1 from public.members m where m.id=member_id and m.auth_user_id=auth.uid()) and exists(select 1 from public.customer_tabs t where t.id=tab_id and t.member_id=member_id and t.status='open')); exception when duplicate_object then null; end $$;
do $$ begin create policy "member orders" on public.customer_orders for select to authenticated using(exists(select 1 from public.members m where m.id=member_id and m.auth_user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy "staff ring sessions" on public.ring_sessions for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "member ring sessions" on public.ring_sessions for select to authenticated using(exists(select 1 from public.members m where m.id=member_id and m.auth_user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy "staff ring moves" on public.ring_movements for all to authenticated using(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)) with check(exists(select 1 from public.staff s where s.auth_user_id=auth.uid() and s.active)); exception when duplicate_object then null; end $$;
do $$ begin create policy "member ring moves" on public.ring_movements for select to authenticated using(exists(select 1 from public.ring_sessions r join public.members m on m.id=r.member_id where r.id=session_id and m.auth_user_id=auth.uid())); exception when duplicate_object then null; end $$;
insert into public.order_menu(name,price,category,display_order) select * from(values('コーラ',500,'ドリンク',10),('ジンジャーエール',500,'ドリンク',20),('ウーロン茶',500,'ドリンク',30))v(name,price,category,display_order) where not exists(select 1 from public.order_menu);
do $$ begin alter publication supabase_realtime add table public.customer_orders; exception when duplicate_object then null; end $$;

-- Staff-only hard delete for an unpaid bill. Child rows are removed by ON DELETE CASCADE.
create or replace function public.staff_delete_customer_tab(p_tab_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.staff s
    where s.auth_user_id = auth.uid() and s.active
  ) then
    raise exception 'staff only';
  end if;

  if not exists (
    select 1 from public.customer_tabs t
    where t.id = p_tab_id and t.status = 'open'
  ) then
    raise exception 'open tab not found';
  end if;

  delete from public.customer_tabs
  where id = p_tab_id and status = 'open';

  return found;
end;
$$;

revoke all on function public.staff_delete_customer_tab(uuid) from public;
grant execute on function public.staff_delete_customer_tab(uuid) to authenticated;
