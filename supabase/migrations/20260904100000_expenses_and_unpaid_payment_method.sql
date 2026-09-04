begin;

-- 未収は回収前なので、支払方法を持たない。
alter table public.sales
  alter column payment_method drop not null;

alter table public.sales
  drop constraint if exists sales_payment_method_check;

update public.sales
set payment_method = null
where payment_status = '未収';

alter table public.sales
  add constraint sales_payment_method_check
  check (
    (payment_status = '未収' and payment_method is null)
    or
    (payment_status = '回収済み' and payment_method in ('現金', 'カード'))
  );

-- 経費は精算から独立して記録し、登録時点でレジ金へ反映する。
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  expense_date date not null,
  amount bigint not null check (amount > 0),
  description text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (description is null or length(description) <= 200)
);

create index if not exists expenses_store_date_idx
  on public.expenses (store_id, expense_date desc, created_at desc);

alter table public.expenses enable row level security;

drop policy if exists "store members read expenses" on public.expenses;
create policy "store members read expenses" on public.expenses
  for select to authenticated
  using (public.is_store_member(store_id));

revoke insert, update, delete on public.expenses from anon, authenticated;
grant select on public.expenses to authenticated;

alter table public.cash_register_history
  drop constraint if exists cash_register_history_action_check;
alter table public.cash_register_history
  add constraint cash_register_history_action_check
  check (action in ('set_amount', 'settlement', 'reset', 'expense'));

alter table public.cash_register_history
  add column if not exists expense_id uuid references public.expenses(id) on delete set null;

create or replace function public.record_store_expense(
  target_store_id uuid,
  target_expense_date date,
  target_amount bigint,
  target_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_description text := nullif(btrim(coalesce(target_description, '')), '');
  before_register bigint;
  after_register bigint;
  saved_expense public.expenses;
  saved_register public.cash_registers;
begin
  if caller_id is null or not public.is_store_owner_or_manager(target_store_id) then
    raise exception 'Only store managers can record expenses' using errcode = '42501';
  end if;
  if target_expense_date is null then
    raise exception 'Expense date is required' using errcode = '22023';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception 'Expense amount must be greater than zero' using errcode = '22023';
  end if;
  if normalized_description is not null and length(normalized_description) > 200 then
    raise exception 'Expense description is too long' using errcode = '22023';
  end if;

  insert into public.cash_registers (store_id, base_amount, current_amount, updated_by)
  values (target_store_id, 0, 0, caller_id)
  on conflict (store_id) do nothing;

  select register.current_amount into before_register
  from public.cash_registers register
  where register.store_id = target_store_id
  for update;

  after_register := before_register - target_amount;

  insert into public.expenses (store_id, expense_date, amount, description, created_by)
  values (target_store_id, target_expense_date, target_amount, normalized_description, caller_id)
  returning * into saved_expense;

  update public.cash_registers register
  set current_amount = after_register,
      updated_at = now(),
      updated_by = caller_id
  where register.store_id = target_store_id
  returning * into saved_register;

  insert into public.cash_register_history (
    store_id, action, amount_delta, balance_before, balance_after,
    base_amount, business_date, expense_id, created_by
  ) values (
    target_store_id, 'expense', -target_amount, before_register, after_register,
    saved_register.base_amount, target_expense_date, saved_expense.id, caller_id
  );

  return jsonb_build_object(
    'expense', to_jsonb(saved_expense),
    'cash_register', to_jsonb(saved_register)
  );
end;
$$;

revoke all on function public.record_store_expense(uuid, date, bigint, text) from public, anon;
grant execute on function public.record_store_expense(uuid, date, bigint, text) to authenticated;

commit;
