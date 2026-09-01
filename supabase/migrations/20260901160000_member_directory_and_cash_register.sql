begin;

create or replace function public.get_store_member_directory(target_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  members_json jsonb;
  invitations_json jsonb;
begin
  if caller_id is null or not exists (
    select 1
    from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role = 'owner'
  ) then
    raise exception 'Only store owners can view member email addresses'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(member_row) order by member_row.created_at), '[]'::jsonb)
  into members_json
  from (
    select membership.store_id,
           membership.user_id,
           membership.role,
           membership.employee_id,
           membership.created_at,
           membership.updated_at,
           coalesce(auth_user.email, '') as email
    from public.store_users membership
    left join auth.users auth_user on auth_user.id = membership.user_id
    where membership.store_id = target_store_id
  ) member_row;

  select coalesce(jsonb_agg(to_jsonb(invitation_row) order by invitation_row.created_at), '[]'::jsonb)
  into invitations_json
  from (
    select invitation.store_id,
           invitation.email,
           invitation.role,
           invitation.employee_id,
           invitation.status,
           invitation.created_at,
           invitation.updated_at
    from public.store_invitations invitation
    where invitation.store_id = target_store_id
      and invitation.status = 'pending'
  ) invitation_row;

  return jsonb_build_object(
    'members', members_json,
    'invitations', invitations_json
  );
end;
$$;

revoke all on function public.get_store_member_directory(uuid) from public;
revoke all on function public.get_store_member_directory(uuid) from anon;
grant execute on function public.get_store_member_directory(uuid) to authenticated;

create table if not exists public.cash_registers (
  store_id uuid primary key references public.stores(id) on delete cascade,
  base_amount bigint not null default 0 check (base_amount >= 0),
  current_amount bigint not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.daily_settlements
  add column if not exists settled_cash_amount bigint not null default 0,
  add column if not exists settled_card_amount bigint not null default 0,
  add column if not exists settled_cash_net_amount bigint not null default 0,
  add column if not exists register_shortage_amount bigint not null default 0,
  add column if not exists register_balance_after bigint;

create table if not exists public.cash_register_history (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  action text not null check (action in ('set_amount', 'settlement', 'reset')),
  amount_delta bigint not null default 0,
  balance_before bigint not null,
  balance_after bigint not null,
  base_amount bigint not null,
  business_date date,
  settlement_id uuid references public.daily_settlements(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists cash_register_history_store_created_idx
  on public.cash_register_history (store_id, created_at desc);

alter table public.cash_registers enable row level security;
alter table public.cash_register_history enable row level security;

drop policy if exists "store members read cash register" on public.cash_registers;
create policy "store members read cash register" on public.cash_registers
  for select to authenticated
  using (public.is_store_member(store_id));

drop policy if exists "store members read cash register history" on public.cash_register_history;
create policy "store members read cash register history" on public.cash_register_history
  for select to authenticated
  using (public.is_store_member(store_id));

revoke insert, update, delete on public.cash_registers from anon, authenticated;
revoke insert, update, delete on public.cash_register_history from anon, authenticated;
grant select on public.cash_registers to authenticated;
grant select on public.cash_register_history to authenticated;

create or replace function public.set_cash_register_amount(
  target_store_id uuid,
  target_amount bigint
)
returns public.cash_registers
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  before_amount bigint := 0;
  saved_register public.cash_registers;
begin
  if caller_id is null or not exists (
    select 1 from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role in ('owner', 'manager')
  ) then
    raise exception 'Only store managers can set the cash register amount'
      using errcode = '42501';
  end if;

  if target_amount is null or target_amount < 0 then
    raise exception 'Cash register amount must be zero or greater'
      using errcode = '22023';
  end if;

  select register.current_amount
  into before_amount
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;
  before_amount := coalesce(before_amount, 0);

  insert into public.cash_registers (
    store_id, base_amount, current_amount, updated_at, updated_by
  )
  values (
    target_store_id, target_amount, target_amount, now(), caller_id
  )
  on conflict (store_id) do update
  set base_amount = excluded.base_amount,
      current_amount = excluded.current_amount,
      updated_at = now(),
      updated_by = caller_id
  returning * into saved_register;

  insert into public.cash_register_history (
    store_id, action, amount_delta, balance_before, balance_after,
    base_amount, created_by
  ) values (
    target_store_id, 'set_amount', target_amount - before_amount,
    before_amount, target_amount, target_amount, caller_id
  );

  return saved_register;
end;
$$;

create or replace function public.reset_cash_register(target_store_id uuid)
returns public.cash_registers
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  before_amount bigint;
  saved_register public.cash_registers;
begin
  if caller_id is null or not exists (
    select 1 from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role in ('owner', 'manager')
  ) then
    raise exception 'Only store managers can reset the cash register'
      using errcode = '42501';
  end if;

  insert into public.cash_registers (store_id, base_amount, current_amount, updated_by)
  values (target_store_id, 0, 0, caller_id)
  on conflict (store_id) do nothing;

  select register.current_amount
  into before_amount
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;

  update public.cash_registers register
  set current_amount = register.base_amount,
      updated_at = now(),
      updated_by = caller_id
  where register.store_id = target_store_id
  returning * into saved_register;

  insert into public.cash_register_history (
    store_id, action, amount_delta, balance_before, balance_after,
    base_amount, created_by
  ) values (
    target_store_id, 'reset', saved_register.current_amount - before_amount,
    before_amount, saved_register.current_amount, saved_register.base_amount, caller_id
  );

  return saved_register;
end;
$$;

create or replace function public.settle_store_sales(
  target_store_id uuid,
  target_business_date date,
  target_sale_ids uuid[],
  target_consumables_amount bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  unique_sale_ids uuid[];
  matching_count integer;
  gross_amount bigint;
  cash_amount bigint;
  card_amount bigint;
  extras_amount bigint;
  cash_net_amount bigint;
  shortage_amount bigint;
  before_register bigint;
  after_register bigint;
  saved_settlement public.daily_settlements;
  saved_register public.cash_registers;
begin
  if caller_id is null or not exists (
    select 1 from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role in ('owner', 'manager')
  ) then
    raise exception 'Only store managers can settle sales'
      using errcode = '42501';
  end if;

  if target_consumables_amount is null or target_consumables_amount < 0 then
    raise exception 'Consumables amount must be zero or greater'
      using errcode = '22023';
  end if;

  unique_sale_ids := array(
    select distinct selected.sale_id
    from unnest(coalesce(target_sale_ids, array[]::uuid[])) as selected(sale_id)
  );
  if cardinality(unique_sale_ids) = 0 then
    raise exception 'No unsettled sales were selected'
      using errcode = '22023';
  end if;

  perform 1
  from public.sales sale
  where sale.id = any(unique_sale_ids)
  for update;

  select count(*)::integer,
         coalesce(sum(sale.total_amount), 0)::bigint,
         coalesce(sum(sale.total_amount) filter (where sale.payment_method = '現金'), 0)::bigint,
         coalesce(sum(sale.total_amount) filter (where sale.payment_method = 'カード'), 0)::bigint,
         coalesce(sum(sale.delivery_tobacco_amount), 0)::bigint
  into matching_count, gross_amount, cash_amount, card_amount, extras_amount
  from public.sales sale
  where sale.id = any(unique_sale_ids)
    and sale.store_id = target_store_id
    and sale.business_date = target_business_date
    and sale.payment_status = '回収済み'
    and not coalesce(sale.is_settled, false);

  if matching_count <> cardinality(unique_sale_ids) then
    raise exception 'Some sales are invalid or already settled'
      using errcode = '22023';
  end if;

  cash_net_amount := cash_amount - extras_amount - target_consumables_amount;
  shortage_amount := greatest(-cash_net_amount, 0);

  insert into public.cash_registers (store_id, base_amount, current_amount, updated_by)
  values (target_store_id, 0, 0, caller_id)
  on conflict (store_id) do nothing;

  select register.current_amount
  into before_register
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;
  after_register := before_register - shortage_amount;

  insert into public.daily_settlements (
    store_id,
    business_date,
    consumables_amount,
    settled_sale_ids,
    settled_total_amount,
    settled_delivery_tobacco_amount,
    settled_net_amount,
    settled_cash_amount,
    settled_card_amount,
    settled_cash_net_amount,
    register_shortage_amount,
    register_balance_after
  ) values (
    target_store_id,
    target_business_date,
    target_consumables_amount,
    unique_sale_ids,
    gross_amount,
    extras_amount,
    gross_amount - extras_amount - target_consumables_amount,
    cash_amount,
    card_amount,
    cash_net_amount,
    shortage_amount,
    after_register
  )
  returning * into saved_settlement;

  update public.sales sale
  set is_settled = true,
      settled_at = saved_settlement.settled_at,
      settlement_id = saved_settlement.id
  where sale.id = any(unique_sale_ids);

  update public.cash_registers register
  set current_amount = after_register,
      updated_at = now(),
      updated_by = caller_id
  where register.store_id = target_store_id
  returning * into saved_register;

  insert into public.cash_register_history (
    store_id, action, amount_delta, balance_before, balance_after,
    base_amount, business_date, settlement_id, created_by
  ) values (
    target_store_id, 'settlement', -shortage_amount, before_register, after_register,
    saved_register.base_amount, target_business_date, saved_settlement.id, caller_id
  );

  return jsonb_build_object(
    'settlement', to_jsonb(saved_settlement),
    'cash_register', to_jsonb(saved_register)
  );
end;
$$;

revoke all on function public.set_cash_register_amount(uuid, bigint) from public;
revoke all on function public.reset_cash_register(uuid) from public;
revoke all on function public.settle_store_sales(uuid, date, uuid[], bigint) from public;
revoke all on function public.set_cash_register_amount(uuid, bigint) from anon;
revoke all on function public.reset_cash_register(uuid) from anon;
revoke all on function public.settle_store_sales(uuid, date, uuid[], bigint) from anon;
grant execute on function public.set_cash_register_amount(uuid, bigint) to authenticated;
grant execute on function public.reset_cash_register(uuid) to authenticated;
grant execute on function public.settle_store_sales(uuid, date, uuid[], bigint) to authenticated;

commit;

