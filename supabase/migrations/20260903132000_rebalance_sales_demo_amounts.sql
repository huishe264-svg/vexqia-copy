begin;

do $$
declare
  demo_store_id uuid;
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

  update public.sales sale
  set total_amount = demo_amount.amount,
      delivery_tobacco_amount = demo_amount.extra_amount,
      updated_at = now()
  from (
    values
      ('d3500000-0000-4000-8000-000000000001'::uuid,  60000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000002'::uuid,  90000::numeric,  5000::numeric),
      ('d3500000-0000-4000-8000-000000000003'::uuid,  35000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000004'::uuid,  70000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000005'::uuid, 100000::numeric, 10000::numeric),
      ('d3500000-0000-4000-8000-000000000006'::uuid,  85000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000007'::uuid,  45000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000008'::uuid,  90000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000009'::uuid,  45000::numeric,  2000::numeric),
      ('d3500000-0000-4000-8000-000000000010'::uuid,  30000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000011'::uuid, 110000::numeric,  5000::numeric),
      ('d3500000-0000-4000-8000-000000000012'::uuid,  60000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000013'::uuid, 140000::numeric,  8000::numeric),
      ('d3500000-0000-4000-8000-000000000014'::uuid,  70000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000015'::uuid,  60000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000016'::uuid, 180000::numeric, 10000::numeric),
      ('d3500000-0000-4000-8000-000000000017'::uuid,  90000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000018'::uuid,  70000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000019'::uuid, 220000::numeric, 12000::numeric),
      ('d3500000-0000-4000-8000-000000000020'::uuid, 110000::numeric,     0::numeric),
      ('d3500000-0000-4000-8000-000000000021'::uuid,  80000::numeric,     0::numeric)
  ) as demo_amount(id, amount, extra_amount)
  where sale.id = demo_amount.id
    and sale.store_id = demo_store_id;

  update public.daily_settlements settlement
  set consumables_amount = demo_totals.consumables,
      settled_total_amount = demo_totals.total_amount,
      settled_delivery_tobacco_amount = demo_totals.extra_amount,
      settled_net_amount = demo_totals.net_amount,
      settled_cash_amount = demo_totals.cash_amount,
      settled_card_amount = demo_totals.card_amount,
      settled_cash_net_amount = demo_totals.cash_net_amount,
      register_balance_after = demo_totals.balance_after
  from (
    values
      ('d3600000-0000-4000-8000-000000000001'::uuid, 2000::bigint, 150000::bigint,  5000::bigint, 145000::bigint,  60000::bigint,  90000::bigint, 53000::bigint, 361000::bigint),
      ('d3600000-0000-4000-8000-000000000002'::uuid, 5000::bigint, 255000::bigint, 10000::bigint, 245000::bigint,  70000::bigint, 185000::bigint, 55000::bigint, 416000::bigint),
      ('d3600000-0000-4000-8000-000000000003'::uuid, 2000::bigint, 170000::bigint,  5000::bigint, 165000::bigint,  60000::bigint, 110000::bigint, 53000::bigint,  83000::bigint),
      ('d3600000-0000-4000-8000-000000000004'::uuid, 4000::bigint, 270000::bigint,  8000::bigint, 262000::bigint,  70000::bigint, 200000::bigint, 58000::bigint, 141000::bigint),
      ('d3600000-0000-4000-8000-000000000005'::uuid, 5000::bigint, 340000::bigint, 10000::bigint, 330000::bigint,  90000::bigint, 250000::bigint, 75000::bigint, 216000::bigint),
      ('d3600000-0000-4000-8000-000000000006'::uuid, 6000::bigint, 410000::bigint, 12000::bigint, 398000::bigint, 110000::bigint, 300000::bigint, 92000::bigint, 308000::bigint)
  ) as demo_totals(
    id, consumables, total_amount, extra_amount, net_amount,
    cash_amount, card_amount, cash_net_amount, balance_after
  )
  where settlement.id = demo_totals.id
    and settlement.store_id = demo_store_id;

  update public.sales_goal_settings
  set weekday_goal = 150000,
      weekend_goal = 220000,
      updated_at = now()
  where store_id = demo_store_id;

  update public.monthly_sales_goals
  set target_amount = case when goal_month = this_month then 4170000 else 3710000 end,
      weekday_goal = 150000,
      weekend_goal = 220000,
      updated_at = now()
  where store_id = demo_store_id
    and goal_month in (this_month, last_month);

  update public.event_sales_goals
  set target_amount = 900000,
      daily_target_amount = 300000,
      updated_at = now()
  where id = 'd3900000-0000-4000-8000-000000000001'::uuid
    and store_id = demo_store_id;

  update public.cash_registers
  set base_amount = 30000,
      current_amount = 416000,
      updated_at = now()
  where store_id = demo_store_id;

  update public.cash_register_history
  set amount_delta = 30000,
      balance_before = 0,
      balance_after = 30000,
      base_amount = 30000
  where id = 'd3800000-0000-4000-8000-000000000001'::uuid
    and store_id = demo_store_id;

  update public.cash_register_history history
  set amount_delta = demo_history.amount_delta,
      balance_before = demo_history.balance_before,
      balance_after = demo_history.balance_after,
      base_amount = 30000
  from (
    values
      ('d3800000-0000-4000-8000-000000000002'::uuid, 53000::bigint,  30000::bigint,  83000::bigint),
      ('d3800000-0000-4000-8000-000000000003'::uuid, 58000::bigint,  83000::bigint, 141000::bigint),
      ('d3800000-0000-4000-8000-000000000004'::uuid, 75000::bigint, 141000::bigint, 216000::bigint),
      ('d3800000-0000-4000-8000-000000000005'::uuid, 92000::bigint, 216000::bigint, 308000::bigint),
      ('d3800000-0000-4000-8000-000000000006'::uuid, 53000::bigint, 308000::bigint, 361000::bigint),
      ('d3800000-0000-4000-8000-000000000007'::uuid, 55000::bigint, 361000::bigint, 416000::bigint)
  ) as demo_history(id, amount_delta, balance_before, balance_after)
  where history.id = demo_history.id
    and history.store_id = demo_store_id;
end;
$$;

commit;
