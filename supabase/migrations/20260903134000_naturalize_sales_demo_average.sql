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

  update public.sales
  set total_amount = 92500,
      updated_at = now()
  where id = 'd3500000-0000-4000-8000-000000000006'::uuid
    and store_id = demo_store_id;

  update public.daily_settlements
  set settled_total_amount = 262500,
      settled_net_amount = 252500,
      settled_card_amount = 192500
  where id = 'd3600000-0000-4000-8000-000000000002'::uuid
    and store_id = demo_store_id;
end;
$$;

commit;
