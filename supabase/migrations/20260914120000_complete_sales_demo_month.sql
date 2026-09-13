begin;

-- Complete one closed month of realistic, deterministic demo data.
-- The migration is deliberately limited to the newest store named 営業デモ店舗.
do $$
declare
  demo_store_id uuid;
  administrator_user_id uuid;
begin
  select store.id
  into demo_store_id
  from public.stores store
  where store.name = '営業デモ店舗'
  order by store.created_at desc
  limit 1;

  if demo_store_id is null then
    raise exception 'Sales demo store was not found';
  end if;

  select auth_user.id
  into administrator_user_id
  from auth.users auth_user
  where lower(auth_user.email) = lower('huishe264@gmail.com')
  order by auth_user.created_at
  limit 1;

  if administrator_user_id is null then
    raise exception 'Platform administrator account was not found';
  end if;

  perform set_config('request.jwt.claim.sub', administrator_user_id::text, true);

  -- The sales demo presents the complete owner workflow, including finance exports.
  update public.store_operating_settings
  set expense_management_mode = 'full',
      updated_by = administrator_user_id,
      updated_at = now()
  where store_id = demo_store_id;

  update public.monthly_sales_goals
  set target_amount = 3710000,
      weekday_goal = 150000,
      weekend_goal = 220000,
      updated_by = administrator_user_id,
      updated_at = now()
  where store_id = demo_store_id
    and goal_month = date '2026-08-01';

  -- Add the 17 missing Monday-Friday business days. The four Thursdays already
  -- seeded (6, 13, 20, 27 August) are left unchanged.
  insert into public.sales (
    id, store_id, business_date, customer_id, employee_id, payment_status,
    payment_method, party_size, total_amount, delivery_tobacco_amount,
    consumables_amount, bottle_id, notes, is_settled, created_by, updated_by,
    created_at, updated_at
  )
  values
    ('d4500000-0000-4000-8000-000000000001', demo_store_id, date '2026-08-03', 'd3c00000-0000-4000-8000-000000000003', 'd3e00000-0000-4000-8000-000000000003', '回収済み', '現金', 1, 48000, 0, 0, null, '紹介でご来店', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-04 18:11:00+09', timestamptz '2026-08-04 18:11:00+09'),
    ('d4500000-0000-4000-8000-000000000002', demo_store_id, date '2026-08-03', 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 2, 68500, 3500, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-04 18:17:00+09', timestamptz '2026-08-04 18:17:00+09'),
    ('d4500000-0000-4000-8000-000000000003', demo_store_id, date '2026-08-04', 'd3c00000-0000-4000-8000-000000000004', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 2, 55500, 0, 0, 'd3a00000-0000-4000-8000-000000000003', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-05 17:54:00+09', timestamptz '2026-08-05 17:54:00+09'),
    ('d4500000-0000-4000-8000-000000000004', demo_store_id, date '2026-08-04', 'd3c00000-0000-4000-8000-000000000009', 'd3e00000-0000-4000-8000-000000000004', '回収済み', 'カード', 3, 83500, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-05 18:03:00+09', timestamptz '2026-08-05 18:03:00+09'),
    ('d4500000-0000-4000-8000-000000000005', demo_store_id, date '2026-08-05', 'd3c00000-0000-4000-8000-000000000008', 'd3e00000-0000-4000-8000-000000000003', '回収済み', '現金', 1, 42500, 2000, 0, null, '2回目のご来店', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-06 18:26:00+09', timestamptz '2026-08-06 18:26:00+09'),
    ('d4500000-0000-4000-8000-000000000006', demo_store_id, date '2026-08-05', 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 2, 59000, 0, 0, 'd3a00000-0000-4000-8000-000000000002', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-06 18:31:00+09', timestamptz '2026-08-06 18:31:00+09'),
    ('d4500000-0000-4000-8000-000000000007', demo_store_id, date '2026-08-07', 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 3, 75000, 0, 0, 'd3a00000-0000-4000-8000-000000000001', '週末のご予約', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-08 18:08:00+09', timestamptz '2026-08-08 18:08:00+09'),
    ('d4500000-0000-4000-8000-000000000008', demo_store_id, date '2026-08-07', 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 4, 143000, 5000, 0, null, 'イベントの相談あり', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-08 18:14:00+09', timestamptz '2026-08-08 18:14:00+09'),
    ('d4500000-0000-4000-8000-000000000009', demo_store_id, date '2026-08-10', 'd3c00000-0000-4000-8000-000000000010', 'd3e00000-0000-4000-8000-000000000005', '回収済み', '現金', 2, 49500, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-11 17:48:00+09', timestamptz '2026-08-11 17:48:00+09'),
    ('d4500000-0000-4000-8000-000000000010', demo_store_id, date '2026-08-10', 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 2, 78500, 0, 0, 'd3a00000-0000-4000-8000-000000000004', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-11 17:56:00+09', timestamptz '2026-08-11 17:56:00+09'),
    ('d4500000-0000-4000-8000-000000000011', demo_store_id, date '2026-08-11', 'd3c00000-0000-4000-8000-000000000007', 'd3e00000-0000-4000-8000-000000000005', '回収済み', '現金', 2, 64500, 3500, 0, 'd3a00000-0000-4000-8000-000000000005', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-12 18:22:00+09', timestamptz '2026-08-12 18:22:00+09'),
    ('d4500000-0000-4000-8000-000000000012', demo_store_id, date '2026-08-11', 'd3c00000-0000-4000-8000-000000000003', 'd3e00000-0000-4000-8000-000000000003', '回収済み', 'カード', 3, 88000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-12 18:29:00+09', timestamptz '2026-08-12 18:29:00+09'),
    ('d4500000-0000-4000-8000-000000000013', demo_store_id, date '2026-08-12', 'd3c00000-0000-4000-8000-000000000004', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 1, 39000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-13 18:06:00+09', timestamptz '2026-08-13 18:06:00+09'),
    ('d4500000-0000-4000-8000-000000000014', demo_store_id, date '2026-08-12', 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 2, 55000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-13 18:12:00+09', timestamptz '2026-08-13 18:12:00+09'),
    ('d4500000-0000-4000-8000-000000000015', demo_store_id, date '2026-08-14', 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 3, 83500, 0, 0, 'd3a00000-0000-4000-8000-000000000001', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-15 18:38:00+09', timestamptz '2026-08-15 18:38:00+09'),
    ('d4500000-0000-4000-8000-000000000016', demo_store_id, date '2026-08-14', 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 4, 128000, 4500, 0, null, '週末の団体利用', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-15 18:45:00+09', timestamptz '2026-08-15 18:45:00+09'),
    ('d4500000-0000-4000-8000-000000000017', demo_store_id, date '2026-08-17', 'd3c00000-0000-4000-8000-000000000008', 'd3e00000-0000-4000-8000-000000000003', '回収済み', '現金', 2, 47000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-18 17:59:00+09', timestamptz '2026-08-18 17:59:00+09'),
    ('d4500000-0000-4000-8000-000000000018', demo_store_id, date '2026-08-17', 'd3c00000-0000-4000-8000-000000000009', 'd3e00000-0000-4000-8000-000000000004', '回収済み', 'カード', 2, 72000, 2500, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-18 18:07:00+09', timestamptz '2026-08-18 18:07:00+09'),
    ('d4500000-0000-4000-8000-000000000019', demo_store_id, date '2026-08-18', 'd3c00000-0000-4000-8000-000000000007', 'd3e00000-0000-4000-8000-000000000005', '回収済み', '現金', 2, 69500, 0, 0, 'd3a00000-0000-4000-8000-000000000005', '同伴でご来店', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-19 18:33:00+09', timestamptz '2026-08-19 18:33:00+09'),
    ('d4500000-0000-4000-8000-000000000020', demo_store_id, date '2026-08-18', 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 3, 98000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-19 18:41:00+09', timestamptz '2026-08-19 18:41:00+09'),
    ('d4500000-0000-4000-8000-000000000021', demo_store_id, date '2026-08-19', 'd3c00000-0000-4000-8000-000000000010', 'd3e00000-0000-4000-8000-000000000005', '回収済み', '現金', 1, 44000, 2000, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-20 18:19:00+09', timestamptz '2026-08-20 18:19:00+09'),
    ('d4500000-0000-4000-8000-000000000022', demo_store_id, date '2026-08-19', 'd3c00000-0000-4000-8000-000000000003', 'd3e00000-0000-4000-8000-000000000003', '回収済み', 'カード', 2, 64000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-20 18:24:00+09', timestamptz '2026-08-20 18:24:00+09'),
    ('d4500000-0000-4000-8000-000000000023', demo_store_id, date '2026-08-21', 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', '現金', 3, 96000, 0, 0, 'd3a00000-0000-4000-8000-000000000002', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-22 18:03:00+09', timestamptz '2026-08-22 18:03:00+09'),
    ('d4500000-0000-4000-8000-000000000024', demo_store_id, date '2026-08-21', 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 4, 140000, 5500, 0, null, 'シャンパン注文あり', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-22 18:12:00+09', timestamptz '2026-08-22 18:12:00+09'),
    ('d4500000-0000-4000-8000-000000000025', demo_store_id, date '2026-08-24', 'd3c00000-0000-4000-8000-000000000004', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 2, 54500, 0, 0, 'd3a00000-0000-4000-8000-000000000003', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-25 17:43:00+09', timestamptz '2026-08-25 17:43:00+09'),
    ('d4500000-0000-4000-8000-000000000026', demo_store_id, date '2026-08-24', 'd3c00000-0000-4000-8000-000000000008', 'd3e00000-0000-4000-8000-000000000003', '回収済み', 'カード', 2, 78000, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-25 17:51:00+09', timestamptz '2026-08-25 17:51:00+09'),
    ('d4500000-0000-4000-8000-000000000027', demo_store_id, date '2026-08-25', 'd3c00000-0000-4000-8000-000000000007', 'd3e00000-0000-4000-8000-000000000005', '回収済み', '現金', 2, 74000, 0, 0, 'd3a00000-0000-4000-8000-000000000005', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-26 18:16:00+09', timestamptz '2026-08-26 18:16:00+09'),
    ('d4500000-0000-4000-8000-000000000028', demo_store_id, date '2026-08-25', 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 3, 110000, 4000, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-26 18:23:00+09', timestamptz '2026-08-26 18:23:00+09'),
    ('d4500000-0000-4000-8000-000000000029', demo_store_id, date '2026-08-26', 'd3c00000-0000-4000-8000-000000000009', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 1, 40500, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-27 18:37:00+09', timestamptz '2026-08-27 18:37:00+09'),
    ('d4500000-0000-4000-8000-000000000030', demo_store_id, date '2026-08-26', 'd3c00000-0000-4000-8000-000000000010', 'd3e00000-0000-4000-8000-000000000005', '回収済み', 'カード', 2, 56500, 0, 0, null, null, true, administrator_user_id, administrator_user_id, timestamptz '2026-08-27 18:44:00+09', timestamptz '2026-08-27 18:44:00+09'),
    ('d4500000-0000-4000-8000-000000000031', demo_store_id, date '2026-08-28', 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 3, 99500, 0, 0, 'd3a00000-0000-4000-8000-000000000001', '月末前のご予約', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-29 18:27:00+09', timestamptz '2026-08-29 18:27:00+09'),
    ('d4500000-0000-4000-8000-000000000032', demo_store_id, date '2026-08-28', 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 4, 146000, 6000, 0, null, '週末の団体利用', true, administrator_user_id, administrator_user_id, timestamptz '2026-08-29 18:35:00+09', timestamptz '2026-08-29 18:35:00+09'),
    ('d4500000-0000-4000-8000-000000000033', demo_store_id, date '2026-08-31', 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 2, 59000, 2500, 0, 'd3a00000-0000-4000-8000-000000000004', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-09-01 18:02:00+09', timestamptz '2026-09-01 18:02:00+09'),
    ('d4500000-0000-4000-8000-000000000034', demo_store_id, date '2026-08-31', 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 3, 87000, 0, 0, 'd3a00000-0000-4000-8000-000000000002', null, true, administrator_user_id, administrator_user_id, timestamptz '2026-09-01 18:09:00+09', timestamptz '2026-09-01 18:09:00+09'),
    ('d4500000-0000-4000-8000-000000000035', demo_store_id, date '2026-08-14', 'd3c00000-0000-4000-8000-000000000009', 'd3e00000-0000-4000-8000-000000000004', '未収', null, 2, 38000, 0, 0, null, '次回来店時に回収予定', false, administrator_user_id, administrator_user_id, timestamptz '2026-08-15 18:48:00+09', timestamptz '2026-08-15 18:48:00+09'),
    ('d4500000-0000-4000-8000-000000000036', demo_store_id, date '2026-08-28', 'd3c00000-0000-4000-8000-000000000010', 'd3e00000-0000-4000-8000-000000000005', '未収', null, 2, 52000, 0, 0, null, '9月中旬に回収予定', false, administrator_user_id, administrator_user_id, timestamptz '2026-08-29 18:39:00+09', timestamptz '2026-08-29 18:39:00+09')
  on conflict (id) do update
  set business_date = excluded.business_date,
      customer_id = excluded.customer_id,
      employee_id = excluded.employee_id,
      payment_status = excluded.payment_status,
      payment_method = excluded.payment_method,
      party_size = excluded.party_size,
      total_amount = excluded.total_amount,
      delivery_tobacco_amount = excluded.delivery_tobacco_amount,
      bottle_id = excluded.bottle_id,
      notes = excluded.notes,
      is_settled = excluded.is_settled,
      updated_by = administrator_user_id,
      updated_at = excluded.updated_at;

  with demo_days(settlement_id, business_date, register_balance_after) as (
    values
      ('d4600000-0000-4000-8000-000000000001'::uuid, date '2026-08-03', 74500::bigint),
      ('d4600000-0000-4000-8000-000000000002'::uuid, date '2026-08-04', 85500::bigint),
      ('d4600000-0000-4000-8000-000000000003'::uuid, date '2026-08-05', 70500::bigint),
      ('d4600000-0000-4000-8000-000000000004'::uuid, date '2026-08-07', 100000::bigint),
      ('d4600000-0000-4000-8000-000000000005'::uuid, date '2026-08-10', 79500::bigint),
      ('d4600000-0000-4000-8000-000000000006'::uuid, date '2026-08-11', 91000::bigint),
      ('d4600000-0000-4000-8000-000000000007'::uuid, date '2026-08-12', 69000::bigint),
      ('d4600000-0000-4000-8000-000000000008'::uuid, date '2026-08-14', 109000::bigint),
      ('d4600000-0000-4000-8000-000000000009'::uuid, date '2026-08-17', 74500::bigint),
      ('d4600000-0000-4000-8000-000000000010'::uuid, date '2026-08-18', 99500::bigint),
      ('d4600000-0000-4000-8000-000000000011'::uuid, date '2026-08-19', 72000::bigint),
      ('d4600000-0000-4000-8000-000000000012'::uuid, date '2026-08-21', 120500::bigint),
      ('d4600000-0000-4000-8000-000000000013'::uuid, date '2026-08-24', 84500::bigint),
      ('d4600000-0000-4000-8000-000000000014'::uuid, date '2026-08-25', 100000::bigint),
      ('d4600000-0000-4000-8000-000000000015'::uuid, date '2026-08-26', 70500::bigint),
      ('d4600000-0000-4000-8000-000000000016'::uuid, date '2026-08-28', 123500::bigint),
      ('d4600000-0000-4000-8000-000000000017'::uuid, date '2026-08-31', 86500::bigint)
  ), totals as (
    select day.settlement_id,
           day.business_date,
           day.register_balance_after,
           array_agg(sale.id order by sale.id) as sale_ids,
           sum(sale.total_amount)::bigint as gross_amount,
           sum(sale.delivery_tobacco_amount)::bigint as extra_amount,
           sum(sale.total_amount) filter (where sale.payment_method = '現金')::bigint as cash_amount,
           sum(sale.total_amount) filter (where sale.payment_method = 'カード')::bigint as card_amount
    from demo_days day
    join public.sales sale
      on sale.store_id = demo_store_id
     and sale.business_date = day.business_date
     and sale.payment_status = '回収済み'
     and sale.id::text like 'd4500000-%'
    group by day.settlement_id, day.business_date, day.register_balance_after
  )
  insert into public.daily_settlements (
    id, store_id, business_date, consumables_amount, settled_sale_ids,
    settled_total_amount, settled_delivery_tobacco_amount, settled_net_amount,
    settled_cash_amount, settled_card_amount, settled_cash_net_amount,
    register_shortage_amount, register_balance_after
  )
  select settlement_id, demo_store_id, business_date, 0, sale_ids,
         gross_amount, extra_amount, gross_amount - extra_amount,
         cash_amount, card_amount, cash_amount - extra_amount,
         0, register_balance_after
  from totals
  on conflict (id) do update
  set business_date = excluded.business_date,
      consumables_amount = excluded.consumables_amount,
      settled_sale_ids = excluded.settled_sale_ids,
      settled_total_amount = excluded.settled_total_amount,
      settled_delivery_tobacco_amount = excluded.settled_delivery_tobacco_amount,
      settled_net_amount = excluded.settled_net_amount,
      settled_cash_amount = excluded.settled_cash_amount,
      settled_card_amount = excluded.settled_card_amount,
      settled_cash_net_amount = excluded.settled_cash_net_amount,
      register_shortage_amount = excluded.register_shortage_amount,
      register_balance_after = excluded.register_balance_after;

  with demo_days(settlement_id, business_date) as (
    values
      ('d4600000-0000-4000-8000-000000000001'::uuid, date '2026-08-03'),
      ('d4600000-0000-4000-8000-000000000002'::uuid, date '2026-08-04'),
      ('d4600000-0000-4000-8000-000000000003'::uuid, date '2026-08-05'),
      ('d4600000-0000-4000-8000-000000000004'::uuid, date '2026-08-07'),
      ('d4600000-0000-4000-8000-000000000005'::uuid, date '2026-08-10'),
      ('d4600000-0000-4000-8000-000000000006'::uuid, date '2026-08-11'),
      ('d4600000-0000-4000-8000-000000000007'::uuid, date '2026-08-12'),
      ('d4600000-0000-4000-8000-000000000008'::uuid, date '2026-08-14'),
      ('d4600000-0000-4000-8000-000000000009'::uuid, date '2026-08-17'),
      ('d4600000-0000-4000-8000-000000000010'::uuid, date '2026-08-18'),
      ('d4600000-0000-4000-8000-000000000011'::uuid, date '2026-08-19'),
      ('d4600000-0000-4000-8000-000000000012'::uuid, date '2026-08-21'),
      ('d4600000-0000-4000-8000-000000000013'::uuid, date '2026-08-24'),
      ('d4600000-0000-4000-8000-000000000014'::uuid, date '2026-08-25'),
      ('d4600000-0000-4000-8000-000000000015'::uuid, date '2026-08-26'),
      ('d4600000-0000-4000-8000-000000000016'::uuid, date '2026-08-28'),
      ('d4600000-0000-4000-8000-000000000017'::uuid, date '2026-08-31')
  )
  update public.sales sale
  set is_settled = true,
      settlement_id = day.settlement_id,
      settled_at = (day.business_date + interval '1 day 18 hours')::timestamptz,
      updated_by = administrator_user_id
  from demo_days day
  where sale.store_id = demo_store_id
    and sale.business_date = day.business_date
    and sale.payment_status = '回収済み'
    and sale.id::text like 'd4500000-%';

  update public.daily_settlements settlement
  set settled_at = (settlement.business_date + interval '1 day 18 hours')::timestamptz
  where settlement.store_id = demo_store_id
    and settlement.id::text like 'd4600000-%';

  -- A representative month of owner-entered expenses. Cash-register-only
  -- purchases remain in the simple-expense workflow and are not duplicated here.
  insert into public.expenses (
    id, store_id, expense_date, amount, description, vendor, category,
    payment_method, memo, accounting_category, created_by, updated_by,
    created_at, updated_at
  )
  values
    ('d4e00000-0000-4000-8000-000000000001', demo_store_id, date '2026-08-01', 350000, '8月分家賃', 'サンライズビル管理', '家賃', '振込', '8月分店舗家賃', null, administrator_user_id, administrator_user_id, timestamptz '2026-08-01 12:18:00+09', timestamptz '2026-08-01 12:18:00+09'),
    ('d4e00000-0000-4000-8000-000000000002', demo_store_id, date '2026-08-03', 286400, '酒類仕入', '中央酒販', '酒類', '振込', '7月末締め請求分', null, administrator_user_id, administrator_user_id, timestamptz '2026-08-03 14:06:00+09', timestamptz '2026-08-03 14:06:00+09'),
    ('d4e00000-0000-4000-8000-000000000003', demo_store_id, date '2026-08-08', 68420, '電気・水道', '関西ユーティリティ', '水道光熱費', '振込', null, null, administrator_user_id, administrator_user_id, timestamptz '2026-08-08 10:42:00+09', timestamptz '2026-08-08 10:42:00+09'),
    ('d4e00000-0000-4000-8000-000000000004', demo_store_id, date '2026-08-10', 55000, 'SNS広告', 'SNS広告サービス', '広告宣伝費', 'カード', 'イベント告知', null, administrator_user_id, administrator_user_id, timestamptz '2026-08-10 15:31:00+09', timestamptz '2026-08-10 15:31:00+09'),
    ('d4e00000-0000-4000-8000-000000000005', demo_store_id, date '2026-08-15', 13200, '店舗Wi-Fi', '通信サービス', '通信費', 'カード', null, null, administrator_user_id, administrator_user_id, timestamptz '2026-08-15 11:27:00+09', timestamptz '2026-08-15 11:27:00+09'),
    ('d4e00000-0000-4000-8000-000000000006', demo_store_id, date '2026-08-18', 24850, 'グラス・清掃用品', '店舗用品店', '消耗品', 'カード', null, null, administrator_user_id, administrator_user_id, timestamptz '2026-08-18 16:12:00+09', timestamptz '2026-08-18 16:12:00+09'),
    ('d4e00000-0000-4000-8000-000000000007', demo_store_id, date '2026-08-22', 18640, 'スタッフ移動費', '交通系決済', '交通費', 'カード', 'イベント日の移動費', null, administrator_user_id, administrator_user_id, timestamptz '2026-08-22 19:04:00+09', timestamptz '2026-08-22 19:04:00+09'),
    ('d4e00000-0000-4000-8000-000000000008', demo_store_id, date '2026-08-28', 42300, '取引先会食', '割烹みなみ', '接待交際費', 'カード', null, null, administrator_user_id, administrator_user_id, timestamptz '2026-08-28 18:21:00+09', timestamptz '2026-08-28 18:21:00+09')
  on conflict (id) do update
  set expense_date = excluded.expense_date,
      amount = excluded.amount,
      description = excluded.description,
      vendor = excluded.vendor,
      category = excluded.category,
      payment_method = excluded.payment_method,
      memo = excluded.memo,
      deleted_at = null,
      deleted_by = null,
      updated_by = administrator_user_id,
      updated_at = excluded.updated_at;
end;
$$;

commit;
