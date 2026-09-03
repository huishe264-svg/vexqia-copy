begin;

do $$
declare
  demo_store_id uuid;
  administrator_user_id uuid;
  this_month date := date_trunc('month', current_date)::date;
  last_month date := (date_trunc('month', current_date) - interval '1 month')::date;
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

  -- Run application audit/permission triggers as the registered platform
  -- administrator instead of bypassing those safeguards during the seed.
  perform set_config('request.jwt.claim.sub', administrator_user_id::text, true);

  -- Fail closed if someone has already started entering real demo data.
  if not exists (
    select 1 from public.customers
    where id = 'd3c00000-0000-4000-8000-000000000001'::uuid
  ) and (
    exists (select 1 from public.customers where store_id = demo_store_id)
    or exists (select 1 from public.sales where store_id = demo_store_id)
  ) then
    raise exception 'Sales demo store is no longer empty; seed was not applied';
  end if;

  insert into public.employees (id, store_id, name, color)
  values
    ('d3e00000-0000-4000-8000-000000000001', demo_store_id, '葵', '#132238'),
    ('d3e00000-0000-4000-8000-000000000002', demo_store_id, '美咲', '#B48A45'),
    ('d3e00000-0000-4000-8000-000000000003', demo_store_id, '玲奈', '#596B82'),
    ('d3e00000-0000-4000-8000-000000000004', demo_store_id, 'ひかる', '#7A6252'),
    ('d3e00000-0000-4000-8000-000000000005', demo_store_id, '結衣', '#66755B')
  on conflict (id) do update
  set name = excluded.name, color = excluded.color, is_active = true, deleted_at = null;

  insert into public.customers (id, store_id, name, name_kana, employee_id, notes)
  values
    ('d3c00000-0000-4000-8000-000000000001', demo_store_id, '山本 由香', 'やまもと ゆか', 'd3e00000-0000-4000-8000-000000000001', '月2回ほど来店。シャンパンがお好み。'),
    ('d3c00000-0000-4000-8000-000000000002', demo_store_id, '佐藤 美里', 'さとう みさと', 'd3e00000-0000-4000-8000-000000000002', '週末中心。キープボトルあり。'),
    ('d3c00000-0000-4000-8000-000000000003', demo_store_id, '田中 遥', 'たなか はるか', 'd3e00000-0000-4000-8000-000000000003', '紹介で初回来店。'),
    ('d3c00000-0000-4000-8000-000000000004', demo_store_id, '伊藤 真紀', 'いとう まき', 'd3e00000-0000-4000-8000-000000000004', '平日のご予約が中心。'),
    ('d3c00000-0000-4000-8000-000000000005', demo_store_id, '高橋 麻衣', 'たかはし まい', 'd3e00000-0000-4000-8000-000000000002', 'イベント時にご来店。'),
    ('d3c00000-0000-4000-8000-000000000006', demo_store_id, '中村 彩', 'なかむら あや', 'd3e00000-0000-4000-8000-000000000001', 'カード利用が中心。'),
    ('d3c00000-0000-4000-8000-000000000007', demo_store_id, '小林 奈々', 'こばやし なな', 'd3e00000-0000-4000-8000-000000000005', '同伴での来店が多い。'),
    ('d3c00000-0000-4000-8000-000000000008', demo_store_id, '加藤 里奈', 'かとう りな', 'd3e00000-0000-4000-8000-000000000003', '新規顧客。'),
    ('d3c00000-0000-4000-8000-000000000009', demo_store_id, '吉田 美月', 'よしだ みづき', 'd3e00000-0000-4000-8000-000000000004', '次回来店時に未収確認。'),
    ('d3c00000-0000-4000-8000-000000000010', demo_store_id, '渡辺 杏', 'わたなべ あん', 'd3e00000-0000-4000-8000-000000000005', '山本様のご友人。')
  on conflict (id) do update
  set name = excluded.name, name_kana = excluded.name_kana,
      employee_id = excluded.employee_id, notes = excluded.notes,
      is_active = true, deleted_at = null;

  insert into public.bottle_brands (id, store_id, name, is_active)
  values
    ('d3b00000-0000-4000-8000-000000000001', demo_store_id, '吉四六', true),
    ('d3b00000-0000-4000-8000-000000000002', demo_store_id, '黒霧島', true),
    ('d3b00000-0000-4000-8000-000000000003', demo_store_id, 'ヘネシー VSOP', true),
    ('d3b00000-0000-4000-8000-000000000004', demo_store_id, 'ヴーヴ・クリコ イエロー', true),
    ('d3b00000-0000-4000-8000-000000000005', demo_store_id, 'モエ・エ・シャンドン', true)
  on conflict (id) do update
  set name = excluded.name, is_active = true, updated_at = now();

  insert into public.bottles (id, store_id, customer_id, brand_id, name, bottle_number, status)
  values
    ('d3a00000-0000-4000-8000-000000000001', demo_store_id, 'd3c00000-0000-4000-8000-000000000001', 'd3b00000-0000-4000-8000-000000000004', 'ヴーヴ・クリコ イエロー', 'A-12', '保有中'),
    ('d3a00000-0000-4000-8000-000000000002', demo_store_id, 'd3c00000-0000-4000-8000-000000000002', 'd3b00000-0000-4000-8000-000000000001', '吉四六', 'B-07', '保有中'),
    ('d3a00000-0000-4000-8000-000000000003', demo_store_id, 'd3c00000-0000-4000-8000-000000000004', 'd3b00000-0000-4000-8000-000000000003', 'ヘネシー VSOP', 'C-03', '保有中'),
    ('d3a00000-0000-4000-8000-000000000004', demo_store_id, 'd3c00000-0000-4000-8000-000000000006', 'd3b00000-0000-4000-8000-000000000005', 'モエ・エ・シャンドン', 'A-18', '保有中'),
    ('d3a00000-0000-4000-8000-000000000005', demo_store_id, 'd3c00000-0000-4000-8000-000000000007', 'd3b00000-0000-4000-8000-000000000002', '黒霧島', 'B-14', '保有中'),
    ('d3a00000-0000-4000-8000-000000000006', demo_store_id, 'd3c00000-0000-4000-8000-000000000005', 'd3b00000-0000-4000-8000-000000000005', 'モエ・エ・シャンドン', 'A-09', '飲み切り')
  on conflict (id) do update
  set customer_id = excluded.customer_id, brand_id = excluded.brand_id,
      name = excluded.name, bottle_number = excluded.bottle_number,
      status = excluded.status;

  insert into public.sales_goal_settings (
    store_id, weekday_goal, weekend_goal, closed_weekdays, exclude_holidays, updated_at
  ) values (
    demo_store_id, 220000, 320000, array[0,6], false, now()
  )
  on conflict (store_id) do update
  set weekday_goal = excluded.weekday_goal,
      weekend_goal = excluded.weekend_goal,
      closed_weekdays = excluded.closed_weekdays,
      updated_at = now();

  insert into public.monthly_sales_goals (
    id, store_id, goal_month, target_amount, weekday_goal, weekend_goal,
    open_weekdays, created_by, updated_by
  )
  values
    ('d3f00000-0000-4000-8000-000000000001', demo_store_id, this_month, 6130000, 220000, 320000, array[1,2,3,4,5], administrator_user_id, administrator_user_id),
    ('d3f00000-0000-4000-8000-000000000002', demo_store_id, last_month, 5420000, 220000, 320000, array[1,2,3,4,5], administrator_user_id, administrator_user_id)
  on conflict (store_id, goal_month) do update
  set target_amount = excluded.target_amount,
      weekday_goal = excluded.weekday_goal,
      weekend_goal = excluded.weekend_goal,
      open_weekdays = excluded.open_weekdays,
      updated_by = administrator_user_id,
      updated_at = now();

  insert into public.event_sales_goals (
    id, store_id, name, start_date, end_date, target_amount,
    daily_target_amount, note, created_by, updated_by
  ) values (
    'd3900000-0000-4000-8000-000000000001', demo_store_id, null,
    this_month + 16, this_month + 18, 1350000, 450000, null,
    administrator_user_id, administrator_user_id
  )
  on conflict (id) do update
  set start_date = excluded.start_date, end_date = excluded.end_date,
      target_amount = excluded.target_amount,
      daily_target_amount = excluded.daily_target_amount,
      updated_at = now();

  insert into public.schedules (
    id, store_id, customer_id, employee_id, schedule_date, schedule_time,
    schedule_type, title, party_size, status, notes, created_by, updated_by
  )
  values
    ('d3700000-0000-4000-8000-000000000001', demo_store_id, 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', current_date, '20:30', '予約', '山本様 ご来店', 3, '予定', 'シャンパンを準備', administrator_user_id, administrator_user_id),
    ('d3700000-0000-4000-8000-000000000002', demo_store_id, 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', current_date, '22:00', '予約', '佐藤様 ボトル予定', 2, '予定', null, administrator_user_id, administrator_user_id),
    ('d3700000-0000-4000-8000-000000000003', demo_store_id, 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', current_date + 1, '21:00', 'バースデー', '高橋様 バースデー', 5, '予定', 'ケーキ持ち込み予定', administrator_user_id, administrator_user_id),
    ('d3700000-0000-4000-8000-000000000004', demo_store_id, null, null, this_month + 16, '20:00', 'イベント', '3日間イベント 初日', null, '予定', null, administrator_user_id, administrator_user_id)
  on conflict (id) do update
  set schedule_date = excluded.schedule_date, schedule_time = excluded.schedule_time,
      status = excluded.status, updated_at = now();

  -- Current month: two settled days, today's live sales, and visible unpaid accounts.
  insert into public.sales (
    id, store_id, business_date, customer_id, employee_id, payment_status,
    payment_method, party_size, total_amount, delivery_tobacco_amount,
    consumables_amount, bottle_id, notes, is_settled, created_by, updated_by
  )
  values
    ('d3500000-0000-4000-8000-000000000001', demo_store_id, this_month, 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 3, 180000, 0, 0, 'd3a00000-0000-4000-8000-000000000001', '常連のお客様', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000002', demo_store_id, this_month, 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 2, 260000, 10000, 0, 'd3a00000-0000-4000-8000-000000000002', null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000003', demo_store_id, this_month, 'd3c00000-0000-4000-8000-000000000003', 'd3e00000-0000-4000-8000-000000000003', '未収', 'カード', 2, 90000, 0, 0, null, '次回来店時に回収予定', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000004', demo_store_id, this_month + 1, 'd3c00000-0000-4000-8000-000000000004', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 2, 220000, 0, 0, 'd3a00000-0000-4000-8000-000000000003', null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000005', demo_store_id, this_month + 1, 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 4, 340000, 20000, 0, null, 'イベント相談あり', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000006', demo_store_id, this_month + 1, 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 2, 160000, 0, 0, 'd3a00000-0000-4000-8000-000000000004', null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000007', demo_store_id, this_month + 1, 'd3c00000-0000-4000-8000-000000000007', 'd3e00000-0000-4000-8000-000000000005', '未収', '現金', 3, 120000, 0, 0, 'd3a00000-0000-4000-8000-000000000005', '9月10日回収予定', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000008', demo_store_id, current_date, 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 3, 280000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000009', demo_store_id, current_date, 'd3c00000-0000-4000-8000-000000000008', 'd3e00000-0000-4000-8000-000000000003', '回収済み', '現金', 2, 120000, 5000, 0, null, '初回来店', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000010', demo_store_id, current_date, 'd3c00000-0000-4000-8000-000000000009', 'd3e00000-0000-4000-8000-000000000004', '未収', '現金', 1, 75000, 0, 0, null, '未収確認デモ', false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000011', demo_store_id, last_month + 5, 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 3, 320000, 15000, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000012', demo_store_id, last_month + 5, 'd3c00000-0000-4000-8000-000000000004', 'd3e00000-0000-4000-8000-000000000004', '回収済み', '現金', 2, 180000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000013', demo_store_id, last_month + 12, 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 4, 450000, 20000, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000014', demo_store_id, last_month + 12, 'd3c00000-0000-4000-8000-000000000006', 'd3e00000-0000-4000-8000-000000000001', '回収済み', '現金', 2, 220000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000015', demo_store_id, last_month + 12, 'd3c00000-0000-4000-8000-000000000007', 'd3e00000-0000-4000-8000-000000000005', '回収済み', 'カード', 2, 160000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000016', demo_store_id, last_month + 19, 'd3c00000-0000-4000-8000-000000000005', 'd3e00000-0000-4000-8000-000000000002', '回収済み', 'カード', 5, 560000, 25000, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000017', demo_store_id, last_month + 19, 'd3c00000-0000-4000-8000-000000000003', 'd3e00000-0000-4000-8000-000000000003', '回収済み', '現金', 3, 280000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000018', demo_store_id, last_month + 19, 'd3c00000-0000-4000-8000-000000000008', 'd3e00000-0000-4000-8000-000000000003', '回収済み', 'カード', 2, 190000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000019', demo_store_id, last_month + 26, 'd3c00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000001', '回収済み', 'カード', 6, 680000, 30000, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000020', demo_store_id, last_month + 26, 'd3c00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000002', '回収済み', '現金', 3, 340000, 0, 0, null, null, false, administrator_user_id, administrator_user_id),
    ('d3500000-0000-4000-8000-000000000021', demo_store_id, last_month + 26, 'd3c00000-0000-4000-8000-000000000010', 'd3e00000-0000-4000-8000-000000000005', '回収済み', 'カード', 2, 240000, 0, 0, null, null, false, administrator_user_id, administrator_user_id)
  on conflict (id) do update
  set business_date = excluded.business_date, customer_id = excluded.customer_id,
      employee_id = excluded.employee_id, payment_status = excluded.payment_status,
      payment_method = excluded.payment_method, party_size = excluded.party_size,
      total_amount = excluded.total_amount,
      delivery_tobacco_amount = excluded.delivery_tobacco_amount,
      bottle_id = excluded.bottle_id, notes = excluded.notes, updated_at = now();

  insert into public.daily_settlements (
    id, store_id, business_date, consumables_amount, settled_sale_ids,
    settled_total_amount, settled_delivery_tobacco_amount, settled_net_amount,
    settled_cash_amount, settled_card_amount, settled_cash_net_amount,
    register_shortage_amount, register_balance_after
  )
  values
    ('d3600000-0000-4000-8000-000000000001', demo_store_id, this_month, 5000, array['d3500000-0000-4000-8000-000000000001'::uuid,'d3500000-0000-4000-8000-000000000002'::uuid], 440000, 10000, 430000, 180000, 260000, 165000, 0, 1152000),
    ('d3600000-0000-4000-8000-000000000002', demo_store_id, this_month + 1, 8000, array['d3500000-0000-4000-8000-000000000004'::uuid,'d3500000-0000-4000-8000-000000000005'::uuid,'d3500000-0000-4000-8000-000000000006'::uuid], 720000, 20000, 700000, 220000, 500000, 192000, 0, 1344000),
    ('d3600000-0000-4000-8000-000000000003', demo_store_id, last_month + 5, 6000, array['d3500000-0000-4000-8000-000000000011'::uuid,'d3500000-0000-4000-8000-000000000012'::uuid], 500000, 15000, 485000, 180000, 320000, 159000, 0, 259000),
    ('d3600000-0000-4000-8000-000000000004', demo_store_id, last_month + 12, 10000, array['d3500000-0000-4000-8000-000000000013'::uuid,'d3500000-0000-4000-8000-000000000014'::uuid,'d3500000-0000-4000-8000-000000000015'::uuid], 830000, 20000, 810000, 220000, 610000, 190000, 0, 449000),
    ('d3600000-0000-4000-8000-000000000005', demo_store_id, last_month + 19, 12000, array['d3500000-0000-4000-8000-000000000016'::uuid,'d3500000-0000-4000-8000-000000000017'::uuid,'d3500000-0000-4000-8000-000000000018'::uuid], 1030000, 25000, 1005000, 280000, 750000, 243000, 0, 692000),
    ('d3600000-0000-4000-8000-000000000006', demo_store_id, last_month + 26, 15000, array['d3500000-0000-4000-8000-000000000019'::uuid,'d3500000-0000-4000-8000-000000000020'::uuid,'d3500000-0000-4000-8000-000000000021'::uuid], 1260000, 30000, 1230000, 340000, 920000, 295000, 0, 987000)
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
      register_balance_after = excluded.register_balance_after;

  update public.sales
  set is_settled = true,
      settled_at = now() - interval '12 hours',
      settlement_id = case
        when id = any(array['d3500000-0000-4000-8000-000000000001'::uuid,'d3500000-0000-4000-8000-000000000002'::uuid]) then 'd3600000-0000-4000-8000-000000000001'::uuid
        when id = any(array['d3500000-0000-4000-8000-000000000004'::uuid,'d3500000-0000-4000-8000-000000000005'::uuid,'d3500000-0000-4000-8000-000000000006'::uuid]) then 'd3600000-0000-4000-8000-000000000002'::uuid
        when id = any(array['d3500000-0000-4000-8000-000000000011'::uuid,'d3500000-0000-4000-8000-000000000012'::uuid]) then 'd3600000-0000-4000-8000-000000000003'::uuid
        when id = any(array['d3500000-0000-4000-8000-000000000013'::uuid,'d3500000-0000-4000-8000-000000000014'::uuid,'d3500000-0000-4000-8000-000000000015'::uuid]) then 'd3600000-0000-4000-8000-000000000004'::uuid
        when id = any(array['d3500000-0000-4000-8000-000000000016'::uuid,'d3500000-0000-4000-8000-000000000017'::uuid,'d3500000-0000-4000-8000-000000000018'::uuid]) then 'd3600000-0000-4000-8000-000000000005'::uuid
        else 'd3600000-0000-4000-8000-000000000006'::uuid
      end,
      updated_at = now()
  where id between 'd3500000-0000-4000-8000-000000000001'::uuid
               and 'd3500000-0000-4000-8000-000000000021'::uuid
    and payment_status = '回収済み'
    and business_date < current_date;

  insert into public.sale_companions (id, store_id, sale_id, customer_id)
  values
    ('d3d00000-0000-4000-8000-000000000001', demo_store_id, 'd3500000-0000-4000-8000-000000000008', 'd3c00000-0000-4000-8000-000000000010'),
    ('d3d00000-0000-4000-8000-000000000002', demo_store_id, 'd3500000-0000-4000-8000-000000000005', 'd3c00000-0000-4000-8000-000000000007')
  on conflict (sale_id, customer_id) do nothing;

  insert into public.cash_registers (
    store_id, base_amount, current_amount, updated_by
  ) values (
    demo_store_id, 100000, 1344000, administrator_user_id
  )
  on conflict (store_id) do update
  set base_amount = excluded.base_amount,
      current_amount = excluded.current_amount,
      updated_by = administrator_user_id,
      updated_at = now();

  insert into public.cash_register_history (
    id, store_id, action, amount_delta, balance_before, balance_after,
    base_amount, business_date, settlement_id, created_by, created_at
  )
  values
    ('d3800000-0000-4000-8000-000000000001', demo_store_id, 'set_amount', 100000, 0, 100000, 100000, null, null, administrator_user_id, last_month),
    ('d3800000-0000-4000-8000-000000000002', demo_store_id, 'settlement', 159000, 100000, 259000, 100000, last_month + 5, 'd3600000-0000-4000-8000-000000000003', administrator_user_id, last_month + 5 + time '23:30'),
    ('d3800000-0000-4000-8000-000000000003', demo_store_id, 'settlement', 190000, 259000, 449000, 100000, last_month + 12, 'd3600000-0000-4000-8000-000000000004', administrator_user_id, last_month + 12 + time '23:30'),
    ('d3800000-0000-4000-8000-000000000004', demo_store_id, 'settlement', 243000, 449000, 692000, 100000, last_month + 19, 'd3600000-0000-4000-8000-000000000005', administrator_user_id, last_month + 19 + time '23:30'),
    ('d3800000-0000-4000-8000-000000000005', demo_store_id, 'settlement', 295000, 692000, 987000, 100000, last_month + 26, 'd3600000-0000-4000-8000-000000000006', administrator_user_id, last_month + 26 + time '23:30'),
    ('d3800000-0000-4000-8000-000000000006', demo_store_id, 'settlement', 165000, 987000, 1152000, 100000, this_month, 'd3600000-0000-4000-8000-000000000001', administrator_user_id, this_month + time '23:30'),
    ('d3800000-0000-4000-8000-000000000007', demo_store_id, 'settlement', 192000, 1152000, 1344000, 100000, this_month + 1, 'd3600000-0000-4000-8000-000000000002', administrator_user_id, this_month + 1 + time '23:30')
  on conflict (id) do update
  set amount_delta = excluded.amount_delta,
      balance_before = excluded.balance_before,
      balance_after = excluded.balance_after,
      created_at = excluded.created_at;
end;
$$;

commit;
