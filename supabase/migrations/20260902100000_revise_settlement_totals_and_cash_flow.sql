begin;

-- 売上実績は「回収済み売上 - 出前・タバコ等」。消耗品は売上実績から引かない。
update public.daily_settlements
set settled_net_amount = settled_total_amount - settled_delivery_tobacco_amount
where settled_net_amount is distinct from settled_total_amount - settled_delivery_tobacco_amount;

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
    raise exception 'Only store managers can settle sales' using errcode = '42501';
  end if;

  if target_consumables_amount is null or target_consumables_amount < 0 then
    raise exception 'Consumables amount must be zero or greater' using errcode = '22023';
  end if;

  unique_sale_ids := array(
    select distinct selected.sale_id
    from unnest(coalesce(target_sale_ids, array[]::uuid[])) as selected(sale_id)
  );
  if cardinality(unique_sale_ids) = 0 then
    raise exception 'No unsettled sales were selected' using errcode = '22023';
  end if;

  perform 1 from public.sales sale where sale.id = any(unique_sale_ids) for update;

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
    raise exception 'Some sales are invalid or already settled' using errcode = '22023';
  end if;

  cash_net_amount := cash_amount - extras_amount - target_consumables_amount;
  shortage_amount := greatest(-cash_net_amount, 0);

  insert into public.cash_registers (store_id, base_amount, current_amount, updated_by)
  values (target_store_id, 0, 0, caller_id)
  on conflict (store_id) do nothing;

  select register.current_amount into before_register
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;
  after_register := before_register + cash_net_amount;

  insert into public.daily_settlements (
    store_id, business_date, consumables_amount, settled_sale_ids,
    settled_total_amount, settled_delivery_tobacco_amount, settled_net_amount,
    settled_cash_amount, settled_card_amount, settled_cash_net_amount,
    register_shortage_amount, register_balance_after
  ) values (
    target_store_id, target_business_date, target_consumables_amount, unique_sale_ids,
    gross_amount, extras_amount, gross_amount - extras_amount,
    cash_amount, card_amount, cash_net_amount,
    shortage_amount, after_register
  ) returning * into saved_settlement;

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
    target_store_id, 'settlement', cash_net_amount, before_register, after_register,
    saved_register.base_amount, target_business_date, saved_settlement.id, caller_id
  );

  return jsonb_build_object(
    'settlement', to_jsonb(saved_settlement),
    'cash_register', to_jsonb(saved_register)
  );
end;
$$;

create or replace function public.close_empty_business_day(
  target_store_id uuid,
  target_business_date date,
  target_consumables_amount bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
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
    raise exception 'Only store managers can close a business day' using errcode = '42501';
  end if;

  if target_business_date is null or target_business_date > current_date then
    raise exception 'Business date must be today or earlier' using errcode = '22023';
  end if;
  if target_consumables_amount is null or target_consumables_amount < 0 then
    raise exception 'Consumables amount must be zero or greater' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.sales sale
    where sale.store_id = target_store_id
      and sale.business_date = target_business_date
      and sale.payment_status = '回収済み'
      and not coalesce(sale.is_settled, false)
  ) then
    raise exception 'Unsettled recovered sales must be settled first' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.business_day_closures closure
    where closure.store_id = target_store_id
      and closure.business_date = target_business_date
  ) then
    raise exception 'This business day is already closed' using errcode = '22023';
  end if;

  insert into public.cash_registers (store_id, base_amount, current_amount, updated_by)
  values (target_store_id, 0, 0, caller_id)
  on conflict (store_id) do nothing;

  select register.current_amount into before_register
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;
  after_register := before_register - target_consumables_amount;

  insert into public.daily_settlements (
    store_id, business_date, consumables_amount, settled_sale_ids,
    settled_total_amount, settled_delivery_tobacco_amount, settled_net_amount,
    settled_cash_amount, settled_card_amount, settled_cash_net_amount,
    register_shortage_amount, register_balance_after
  ) values (
    target_store_id, target_business_date, target_consumables_amount, array[]::uuid[],
    0, 0, 0,
    0, 0, -target_consumables_amount,
    target_consumables_amount, after_register
  ) returning * into saved_settlement;

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
    target_store_id, 'settlement', -target_consumables_amount,
    before_register, after_register, saved_register.base_amount,
    target_business_date, saved_settlement.id, caller_id
  );

  return jsonb_build_object(
    'settlement', to_jsonb(saved_settlement),
    'cash_register', to_jsonb(saved_register)
  );
end;
$$;

revoke all on function public.settle_store_sales(uuid, date, uuid[], bigint) from public;
revoke all on function public.settle_store_sales(uuid, date, uuid[], bigint) from anon;
grant execute on function public.settle_store_sales(uuid, date, uuid[], bigint) to authenticated;
revoke all on function public.close_empty_business_day(uuid, date, bigint) from public;
revoke all on function public.close_empty_business_day(uuid, date, bigint) from anon;
grant execute on function public.close_empty_business_day(uuid, date, bigint) to authenticated;

commit;
