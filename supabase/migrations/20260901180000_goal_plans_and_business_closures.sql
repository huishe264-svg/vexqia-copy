begin;

alter table public.monthly_sales_goals
  add column if not exists weekday_goal bigint not null default 0,
  add column if not exists weekend_goal bigint not null default 0,
  add column if not exists open_weekdays integer[] not null default array[1,2,3,4,5];

update public.monthly_sales_goals monthly
set weekday_goal = settings.weekday_goal::bigint,
    weekend_goal = settings.weekend_goal::bigint,
    open_weekdays = array(
      select weekday
      from generate_series(0, 6) as weekdays(weekday)
      where not (weekday = any(settings.closed_weekdays))
      order by weekday
    )
from public.sales_goal_settings settings
where monthly.store_id = settings.store_id
  and monthly.goal_month = date_trunc('month', current_date)::date
  and monthly.weekday_goal = 0
  and monthly.weekend_goal = 0;

alter table public.event_sales_goals
  alter column name drop not null,
  add column if not exists daily_target_amount bigint not null default 0;

update public.event_sales_goals
set daily_target_amount = round(
  target_amount::numeric / greatest((end_date - start_date) + 1, 1)
)::bigint
where daily_target_amount = 0 and target_amount > 0;

create table if not exists public.business_day_closures (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  business_date date not null,
  closed_by uuid references auth.users(id) on delete set null,
  closed_at timestamptz not null default now(),
  unique (store_id, business_date)
);

create index if not exists business_day_closures_store_date_idx
  on public.business_day_closures (store_id, business_date desc);

alter table public.business_day_closures enable row level security;
create policy "store members read business closures" on public.business_day_closures
  for select to authenticated using (public.is_store_member(store_id));
revoke insert, update, delete on public.business_day_closures from anon, authenticated;
grant select on public.business_day_closures to authenticated;

insert into public.business_day_closures (store_id, business_date, closed_at)
select settlement.store_id,
       settlement.business_date,
       max(settlement.settled_at)
from public.daily_settlements settlement
group by settlement.store_id, settlement.business_date
on conflict (store_id, business_date) do nothing;

create or replace function public.mark_settlement_day_closed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.business_day_closures (store_id, business_date, closed_by, closed_at)
  values (new.store_id, new.business_date, auth.uid(), now())
  on conflict (store_id, business_date) do update
  set closed_by = excluded.closed_by,
      closed_at = excluded.closed_at;
  return new;
end;
$$;

drop trigger if exists mark_settlement_day_closed on public.daily_settlements;
create trigger mark_settlement_day_closed
after insert on public.daily_settlements
for each row execute function public.mark_settlement_day_closed();

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
    0, 0, -target_consumables_amount,
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

revoke all on function public.close_empty_business_day(uuid, date, bigint) from public;
revoke all on function public.close_empty_business_day(uuid, date, bigint) from anon;
grant execute on function public.close_empty_business_day(uuid, date, bigint) to authenticated;

commit;

