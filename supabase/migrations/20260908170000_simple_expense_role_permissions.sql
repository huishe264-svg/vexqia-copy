begin;

alter table public.store_operating_settings
  add column if not exists manager_simple_expense_permission text not null default 'create',
  add column if not exists staff_simple_expense_permission text not null default 'none';

alter table public.store_operating_settings
  drop constraint if exists store_operating_settings_manager_simple_expense_permission_check,
  drop constraint if exists store_operating_settings_staff_simple_expense_permission_check;

alter table public.store_operating_settings
  add constraint store_operating_settings_manager_simple_expense_permission_check
    check (manager_simple_expense_permission in ('none', 'create', 'manage')),
  add constraint store_operating_settings_staff_simple_expense_permission_check
    check (staff_simple_expense_permission in ('none', 'create', 'manage'));

create or replace function public.simple_expense_access_level(target_store_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  member_role text;
  configured_mode text;
  manager_permission text;
  staff_permission text;
begin
  if caller is null then return 'none'; end if;

  select
    coalesce(settings.expense_management_mode, 'simple'),
    coalesce(settings.manager_simple_expense_permission, 'create'),
    coalesce(settings.staff_simple_expense_permission, 'none')
  into configured_mode, manager_permission, staff_permission
  from public.store_operating_settings settings
  where settings.store_id = target_store_id;

  configured_mode := coalesce(configured_mode, 'simple');
  if configured_mode <> 'simple' then return 'none'; end if;
  if public.is_store_owner(target_store_id) then return 'manage'; end if;

  select member.role into member_role
  from public.store_users member
  where member.store_id = target_store_id and member.user_id = caller;

  if member_role = 'manager' then return coalesce(manager_permission, 'create'); end if;
  if member_role = 'staff' then return coalesce(staff_permission, 'none'); end if;
  return 'none';
end;
$$;

drop policy if exists "permitted members read simple expenses" on public.expenses;
create policy "permitted members read simple expenses" on public.expenses
for select to authenticated using (
  category in ('簡易出金', '備品・消耗品')
  and public.simple_expense_access_level(store_id) in ('create', 'manage')
);

create or replace function public.set_simple_expense_configuration(
  target_store_id uuid,
  target_expense_management_mode text,
  target_manager_permission text,
  target_staff_permission text
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
  if caller is null or not public.is_store_owner(target_store_id) then
    raise exception 'Only store owners can configure simple expense permissions' using errcode = '42501';
  end if;
  if target_expense_management_mode not in ('simple', 'full', 'disabled')
    or target_manager_permission not in ('none', 'create', 'manage')
    or target_staff_permission not in ('none', 'create', 'manage') then
    raise exception 'Invalid simple expense configuration' using errcode = '22023';
  end if;

  insert into public.store_operating_settings(
    store_id, expense_management_mode, manager_simple_expense_permission,
    staff_simple_expense_permission, updated_by, updated_at
  ) values (
    target_store_id, target_expense_management_mode, target_manager_permission,
    target_staff_permission, caller, now()
  )
  on conflict (store_id) do update set
    expense_management_mode = excluded.expense_management_mode,
    manager_simple_expense_permission = excluded.manager_simple_expense_permission,
    staff_simple_expense_permission = excluded.staff_simple_expense_permission,
    updated_by = caller,
    updated_at = now()
  returning * into saved;
  return saved;
end;
$$;

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
    )
    and coalesce((select auth.role()), '') <> 'service_role'
    and not public.is_store_owner(new.store_id) then
    raise exception 'Only store owners can configure expense permissions' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
    and (
      new.expense_management_mode <> 'simple'
      or new.manager_simple_expense_permission <> 'create'
      or new.staff_simple_expense_permission <> 'none'
    )
    and coalesce((select auth.role()), '') <> 'service_role'
    and not public.is_store_owner(new.store_id) then
    raise exception 'Only store owners can configure expense permissions' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_simple_expense_configuration on public.store_operating_settings;
create trigger protect_simple_expense_configuration
before insert or update on public.store_operating_settings
for each row execute function public.protect_simple_expense_configuration();

create or replace function public.create_simple_store_expenses(
  target_store_id uuid,
  target_expense_date date,
  target_amounts jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  item jsonb;
  amount_value bigint;
  before_amount bigint;
  running_amount bigint;
  saved public.expenses;
  saved_rows jsonb := '[]'::jsonb;
  item_count integer := 0;
begin
  if public.simple_expense_access_level(target_store_id) not in ('create', 'manage') then
    raise exception 'Simple expense create access required' using errcode = '42501';
  end if;
  if target_expense_date is null
    or target_amounts is null
    or jsonb_typeof(target_amounts) <> 'array'
    or jsonb_array_length(target_amounts) = 0
    or jsonb_array_length(target_amounts) > 50 then
    raise exception 'Invalid simple expense data' using errcode = '22023';
  end if;

  insert into public.cash_registers(store_id, base_amount, current_amount, updated_by)
  values(target_store_id, 0, 0, caller) on conflict(store_id) do nothing;
  select current_amount into running_amount
  from public.cash_registers where store_id = target_store_id for update;

  for item in select value from jsonb_array_elements(target_amounts)
  loop
    if jsonb_typeof(item) <> 'number' or (item #>> '{}') !~ '^[0-9]+$' then
      raise exception 'Expense amount must be a positive integer' using errcode = '22023';
    end if;
    amount_value := (item #>> '{}')::bigint;
    if amount_value <= 0 then
      raise exception 'Expense amount must be greater than zero' using errcode = '22023';
    end if;

    insert into public.expenses(
      store_id, expense_date, amount, category, payment_method, created_by, updated_by
    ) values (
      target_store_id, target_expense_date, amount_value, '備品・消耗品', '現金', caller, caller
    ) returning * into saved;

    before_amount := running_amount;
    running_amount := running_amount - amount_value;
    insert into public.cash_register_history(
      store_id, action, amount_delta, balance_before, balance_after,
      base_amount, business_date, expense_id, created_by
    ) select
      target_store_id, 'supplies_expense', -amount_value, before_amount, running_amount,
      register.base_amount, target_expense_date, saved.id, caller
    from public.cash_registers register where register.store_id = target_store_id;
    saved_rows := saved_rows || jsonb_build_array(to_jsonb(saved));
    item_count := item_count + 1;
  end loop;

  update public.cash_registers set current_amount = running_amount, updated_by = caller, updated_at = now()
  where store_id = target_store_id;
  return jsonb_build_object('expenses', saved_rows, 'count', item_count,
    'total_amount', (select coalesce(sum((value #>> '{}')::bigint), 0) from jsonb_array_elements(target_amounts)));
end;
$$;

create or replace function public.update_simple_store_expense(
  target_store_id uuid,
  target_expense_id uuid,
  target_amount bigint
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  old public.expenses;
  saved public.expenses;
  before_amount bigint;
  cash_delta bigint;
begin
  if public.simple_expense_access_level(target_store_id) <> 'manage' then
    raise exception 'Simple expense manage access required' using errcode = '42501';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception 'Invalid expense amount' using errcode = '22023';
  end if;
  select * into old from public.expenses
  where id = target_expense_id and store_id = target_store_id and deleted_at is null
    and category in ('簡易出金', '備品・消耗品') and payment_method = '現金'
  for update;
  if not found then raise exception 'Simple expense not found' using errcode = 'P0002'; end if;

  cash_delta := old.amount - target_amount;
  update public.expenses set amount = target_amount, category = '備品・消耗品',
    updated_by = caller, updated_at = now()
  where id = target_expense_id returning * into saved;
  if cash_delta <> 0 then
    select current_amount into before_amount from public.cash_registers
    where store_id = target_store_id for update;
    update public.cash_registers set current_amount = before_amount + cash_delta,
      updated_by = caller, updated_at = now() where store_id = target_store_id;
    insert into public.cash_register_history(
      store_id, action, amount_delta, balance_before, balance_after,
      base_amount, business_date, expense_id, created_by
    ) select target_store_id, 'supplies_expense_adjustment', cash_delta, before_amount,
      before_amount + cash_delta, register.base_amount, old.expense_date, old.id, caller
    from public.cash_registers register where register.store_id = target_store_id;
  end if;
  return saved;
end;
$$;

create or replace function public.delete_simple_store_expense(
  target_store_id uuid,
  target_expense_id uuid
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  old public.expenses;
  saved public.expenses;
  before_amount bigint;
begin
  if public.simple_expense_access_level(target_store_id) <> 'manage' then
    raise exception 'Simple expense manage access required' using errcode = '42501';
  end if;
  select * into old from public.expenses
  where id = target_expense_id and store_id = target_store_id and deleted_at is null
    and category in ('簡易出金', '備品・消耗品') and payment_method = '現金'
  for update;
  if not found then raise exception 'Simple expense not found' using errcode = 'P0002'; end if;

  update public.expenses set deleted_at = now(), deleted_by = caller,
    updated_by = caller, updated_at = now()
  where id = target_expense_id returning * into saved;
  select current_amount into before_amount from public.cash_registers
  where store_id = target_store_id for update;
  update public.cash_registers set current_amount = before_amount + old.amount,
    updated_by = caller, updated_at = now() where store_id = target_store_id;
  insert into public.cash_register_history(
    store_id, action, amount_delta, balance_before, balance_after,
    base_amount, business_date, expense_id, created_by
  ) select target_store_id, 'supplies_expense_delete', old.amount, before_amount,
    before_amount + old.amount, register.base_amount, old.expense_date, old.id, caller
  from public.cash_registers register where register.store_id = target_store_id;
  return saved;
end;
$$;

revoke all on function public.simple_expense_access_level(uuid) from public, anon;
revoke all on function public.set_simple_expense_configuration(uuid, text, text, text) from public, anon;
revoke all on function public.update_simple_store_expense(uuid, uuid, bigint) from public, anon;
revoke all on function public.delete_simple_store_expense(uuid, uuid) from public, anon;
grant execute on function public.simple_expense_access_level(uuid) to authenticated;
grant execute on function public.set_simple_expense_configuration(uuid, text, text, text) to authenticated;
grant execute on function public.update_simple_store_expense(uuid, uuid, bigint) to authenticated;
grant execute on function public.delete_simple_store_expense(uuid, uuid) to authenticated;

commit;
