begin;

create table if not exists public.monthly_sales_goals (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  goal_month date not null check (goal_month = date_trunc('month', goal_month)::date),
  target_amount bigint not null check (target_amount >= 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, goal_month)
);

create table if not exists public.event_sales_goals (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  target_amount bigint not null check (target_amount >= 0),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists monthly_sales_goals_store_month_idx
  on public.monthly_sales_goals (store_id, goal_month desc);
create index if not exists event_sales_goals_store_dates_idx
  on public.event_sales_goals (store_id, start_date desc, end_date desc);

alter table public.monthly_sales_goals enable row level security;
alter table public.event_sales_goals enable row level security;

create policy "store members read monthly goals" on public.monthly_sales_goals
  for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create monthly goals" on public.monthly_sales_goals
  for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update monthly goals" on public.monthly_sales_goals
  for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete monthly goals" on public.monthly_sales_goals
  for delete to authenticated using (public.is_store_owner_or_manager(store_id));

create policy "store members read event goals" on public.event_sales_goals
  for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create event goals" on public.event_sales_goals
  for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update event goals" on public.event_sales_goals
  for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete event goals" on public.event_sales_goals
  for delete to authenticated using (public.is_store_owner_or_manager(store_id));

-- Preserve the current month's goal from the legacy weekday-based setting.
insert into public.monthly_sales_goals (store_id, goal_month, target_amount)
select settings.store_id,
       date_trunc('month', current_date)::date,
       coalesce(sum(
         case
           when coalesce(day_override.is_open, not (extract(dow from generated.day_value)::integer = any(settings.closed_weekdays))) = false then 0
           when extract(dow from generated.day_value)::integer between 1 and 3 then settings.weekday_goal
           else settings.weekend_goal
         end
       ), 0)::bigint
from public.sales_goal_settings settings
cross join lateral generate_series(
  date_trunc('month', current_date)::date,
  (date_trunc('month', current_date) + interval '1 month - 1 day')::date,
  interval '1 day'
) as generated(day_value)
left join public.business_day_overrides day_override
  on day_override.store_id = settings.store_id
 and day_override.business_date = generated.day_value::date
group by settings.store_id
on conflict (store_id, goal_month) do nothing;

commit;

