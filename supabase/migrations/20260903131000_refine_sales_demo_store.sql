begin;

do $$
declare
  demo_store_id uuid;
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

  -- The user explicitly allowed the demo register to be replaced. Remove only
  -- non-seed register history from this one store so its balance remains
  -- consistent with the curated settlement story.
  delete from public.cash_register_history history
  where history.store_id = demo_store_id
    and history.id not in (
      'd3800000-0000-4000-8000-000000000001'::uuid,
      'd3800000-0000-4000-8000-000000000002'::uuid,
      'd3800000-0000-4000-8000-000000000003'::uuid,
      'd3800000-0000-4000-8000-000000000004'::uuid,
      'd3800000-0000-4000-8000-000000000005'::uuid,
      'd3800000-0000-4000-8000-000000000006'::uuid,
      'd3800000-0000-4000-8000-000000000007'::uuid
    );

  -- Make the settled current-month average exactly 90,000 yen per guest.
  update public.sales
  set total_amount = 200000,
      updated_at = now()
  where id = 'd3500000-0000-4000-8000-000000000006'::uuid
    and store_id = demo_store_id;

  update public.daily_settlements
  set settled_total_amount = 760000,
      settled_net_amount = 740000,
      settled_card_amount = 540000
  where id = 'd3600000-0000-4000-8000-000000000002'::uuid
    and store_id = demo_store_id;
end;
$$;

commit;
