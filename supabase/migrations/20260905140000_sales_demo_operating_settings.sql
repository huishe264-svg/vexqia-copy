create table if not exists public.store_operating_settings (
  store_id uuid primary key references public.stores(id) on delete cascade,
  demo_configuration_enabled boolean not null default false,
  goal_mode text not null default 'daily_calculation' check(goal_mode in ('daily_calculation','monthly_direct')),
  account_label text not null default '口座' check(char_length(account_label) between 1 and 12),
  deduction_label text not null default '出前・タバコ等' check(char_length(deduction_label) between 1 and 30),
  payment_methods text[] not null default array['現金','カード']::text[],
  bottle_management_enabled boolean not null default true,
  cash_register_enabled boolean not null default true,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  check(payment_methods <@ array['現金','カード']::text[]),
  check(cardinality(payment_methods) between 1 and 2)
);

alter table public.store_operating_settings enable row level security;
drop policy if exists "store members read operating settings" on public.store_operating_settings;
drop policy if exists "store managers update operating settings" on public.store_operating_settings;
create policy "store members read operating settings" on public.store_operating_settings
  for select to authenticated using(public.is_store_member(store_id));
create policy "store managers update operating settings" on public.store_operating_settings
  for all to authenticated using(public.is_store_owner_or_manager(store_id)) with check(public.is_store_owner_or_manager(store_id));
grant select,insert,update on public.store_operating_settings to authenticated;

do $$
declare demo_store_id uuid; administrator_user_id uuid;
begin
  select id into demo_store_id from public.stores where name='営業デモ店舗' order by created_at desc limit 1;
  select id into administrator_user_id from auth.users where lower(email)=lower('huishe264@gmail.com') order by created_at limit 1;
  if demo_store_id is not null then
    insert into public.store_operating_settings(store_id,demo_configuration_enabled,goal_mode,account_label,deduction_label,payment_methods,bottle_management_enabled,cash_register_enabled,updated_by)
    values(demo_store_id,true,'daily_calculation','口座','出前・タバコ等',array['現金','カード']::text[],true,true,administrator_user_id)
    on conflict(store_id) do update set demo_configuration_enabled=true,updated_by=administrator_user_id,updated_at=now();
  end if;
end $$;
