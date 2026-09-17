begin;

alter table public.store_operating_settings
  add column if not exists manager_settled_sale_edit boolean not null default false;

create or replace function public.protect_simple_expense_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and (
      old.expense_management_mode is distinct from new.expense_management_mode
      or old.manager_simple_expense_permission is distinct from new.manager_simple_expense_permission
      or old.staff_simple_expense_permission is distinct from new.staff_simple_expense_permission
      or old.manager_settled_sale_edit is distinct from new.manager_settled_sale_edit
    )
    and coalesce((select auth.role()), '') <> 'service_role'
    and not public.is_store_owner(new.store_id) then
    raise exception 'Only store owners can configure operation permissions' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
    and (
      new.expense_management_mode <> 'simple'
      or new.manager_simple_expense_permission <> 'create'
      or new.staff_simple_expense_permission <> 'none'
      or new.manager_settled_sale_edit
    )
    and coalesce((select auth.role()), '') <> 'service_role'
    and not public.is_store_owner(new.store_id) then
    raise exception 'Only store owners can configure operation permissions' using errcode = '42501';
  end if;
  return new;
end;
$$;

alter table public.cash_register_history
  drop constraint if exists cash_register_history_action_check;
alter table public.cash_register_history
  add constraint cash_register_history_action_check
  check (action in (
    'set_amount', 'settlement', 'settlement_reopen', 'reset', 'expense',
    'supplies_expense', 'supplies_expense_adjustment', 'supplies_expense_delete'
  ));

create or replace function public.guard_settled_sale()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('vexqia.allow_settlement_reopen', true) = 'on' then
    return case when tg_op='DELETE' then old else new end;
  end if;
  if tg_op='DELETE' and coalesce(old.is_settled,false) then
    raise exception '精算済みの売上は削除できません。訂正処理が必要です' using errcode='55000';
  end if;
  if tg_op='UPDATE' and coalesce(old.is_settled,false) and (
    new.store_id is distinct from old.store_id or new.business_date is distinct from old.business_date
    or new.customer_id is distinct from old.customer_id or new.employee_id is distinct from old.employee_id
    or new.payment_status is distinct from old.payment_status or new.payment_method is distinct from old.payment_method
    or new.party_size is distinct from old.party_size or new.total_amount is distinct from old.total_amount
    or new.delivery_tobacco_amount is distinct from old.delivery_tobacco_amount
    or new.consumables_amount is distinct from old.consumables_amount or new.bottle_id is distinct from old.bottle_id
    or new.notes is distinct from old.notes or new.record_type is distinct from old.record_type
    or new.recognized_via_sale_id is distinct from old.recognized_via_sale_id
  ) then
    raise exception '精算済みの売上は直接変更できません。訂正処理が必要です' using errcode='55000';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create or replace function public.set_settled_sale_edit_permission(
  target_store_id uuid,
  target_manager_allowed boolean
)
returns public.store_operating_settings
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  saved public.store_operating_settings;
begin
  if caller is null or not (public.is_store_owner(target_store_id) or public.is_platform_admin()) then
    raise exception 'Only store owners can configure settlement edit permissions' using errcode='42501';
  end if;
  insert into public.store_operating_settings(store_id,manager_settled_sale_edit,updated_by,updated_at)
  values(target_store_id,coalesce(target_manager_allowed,false),caller,now())
  on conflict(store_id) do update set
    manager_settled_sale_edit=excluded.manager_settled_sale_edit,
    updated_by=excluded.updated_by,
    updated_at=excluded.updated_at
  returning * into saved;
  return saved;
end;
$$;

create or replace function public.reopen_settlement_for_sale(
  target_store_id uuid,
  target_sale_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  caller_role text;
  manager_allowed boolean := false;
  target_sale public.sales;
  target_settlement public.daily_settlements;
  register_before bigint;
  register_after bigint;
  register_base bigint;
  affected_count integer;
begin
  select membership.role into caller_role
  from public.store_users membership
  where membership.store_id=target_store_id and membership.user_id=caller;
  select coalesce(settings.manager_settled_sale_edit,false) into manager_allowed
  from public.store_operating_settings settings where settings.store_id=target_store_id;

  if caller is null or not (
    public.is_platform_admin()
    or caller_role='owner'
    or (caller_role='manager' and manager_allowed)
  ) then
    raise exception 'Settlement edit permission required' using errcode='42501';
  end if;

  select * into target_sale from public.sales
  where id=target_sale_id and store_id=target_store_id for update;
  if not found or not coalesce(target_sale.is_settled,false) or target_sale.settlement_id is null then
    raise exception 'Settled sale not found' using errcode='P0002';
  end if;

  select * into target_settlement from public.daily_settlements
  where id=target_sale.settlement_id and store_id=target_store_id for update;
  if not found then raise exception 'Settlement not found' using errcode='P0002'; end if;

  select current_amount,base_amount into register_before,register_base
  from public.cash_registers where store_id=target_store_id for update;
  if not found then raise exception 'Cash register not found' using errcode='P0002'; end if;
  register_after := register_before - coalesce(target_settlement.settled_cash_net_amount,0);

  perform set_config('vexqia.allow_settlement_reopen','on',true);
  update public.sales set
    is_settled=false, settled_at=null, settlement_id=null, updated_by=caller
  where store_id=target_store_id and settlement_id=target_settlement.id;
  get diagnostics affected_count = row_count;

  update public.cash_registers set
    current_amount=register_after, updated_by=caller, updated_at=now()
  where store_id=target_store_id;

  insert into public.cash_register_history(
    store_id,action,amount_delta,balance_before,balance_after,base_amount,
    business_date,settlement_id,created_by
  ) values (
    target_store_id,'settlement_reopen',-coalesce(target_settlement.settled_cash_net_amount,0),
    register_before,register_after,register_base,target_settlement.business_date,
    target_settlement.id,caller
  );

  delete from public.business_day_closures
  where store_id=target_store_id and business_date=target_settlement.business_date;
  delete from public.daily_settlements where id=target_settlement.id;

  return jsonb_build_object(
    'business_date',target_settlement.business_date,
    'affected_sales',affected_count,
    'reversed_cash_amount',coalesce(target_settlement.settled_cash_net_amount,0),
    'register_balance',register_after
  );
end;
$$;

revoke all on function public.set_settled_sale_edit_permission(uuid,boolean) from public,anon;
revoke all on function public.reopen_settlement_for_sale(uuid,uuid) from public,anon;
grant execute on function public.set_settled_sale_edit_permission(uuid,boolean) to authenticated;
grant execute on function public.reopen_settlement_for_sale(uuid,uuid) to authenticated;

commit;
