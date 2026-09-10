begin;

create or replace function public.get_owner_sales_export_rows(
  target_store_id uuid,
  target_start_date date,
  target_end_date date
) returns table (
  business_date date,
  sale_id uuid,
  customer_name text,
  employee_name text,
  entered_by text,
  party_size integer,
  total_amount bigint,
  delivery_tobacco_amount bigint,
  payment_status text,
  payment_method text,
  settlement_status text,
  recovered_on date,
  record_type text,
  notes text
) language plpgsql stable security definer set search_path='' as $$
begin
  if not public.store_uses_full_expense_management(target_store_id) then
    raise exception 'Only store owners using full expense management can export sales' using errcode='42501';
  end if;
  if target_start_date is null or target_end_date is null or target_end_date < target_start_date
     or target_end_date - target_start_date > 730 then
    raise exception 'Export date range is invalid' using errcode='22023';
  end if;
  return query
  select
    sale.business_date,
    sale.id,
    coalesce(customer.name,'顧客名未登録')::text,
    coalesce(account.name,'口座未設定')::text,
    coalesce(input_account.name,creator.email,sale.created_by::text,'不明')::text,
    sale.party_size,
    sale.total_amount::bigint,
    coalesce(sale.delivery_tobacco_amount,0)::bigint,
    sale.payment_status::text,
    coalesce(sale.payment_method,'')::text,
    case when sale.is_settled then '精算済み' else '未精算' end::text,
    case when sale.payment_status='回収済み' then coalesce(collection.collected_on,sale.business_date) end,
    coalesce(sale.record_type,'sale')::text,
    sale.notes::text
  from public.sales sale
  left join public.customers customer on customer.id=sale.customer_id and customer.store_id=sale.store_id
  left join public.employees account on account.id=sale.employee_id and account.store_id=sale.store_id
  left join public.store_users input_member on input_member.store_id=sale.store_id and input_member.user_id=sale.created_by
  left join public.employees input_account on input_account.id=input_member.employee_id and input_account.store_id=sale.store_id
  left join auth.users creator on creator.id=sale.created_by
  left join lateral (
    select max(event.occurred_at)::date collected_on
    from public.sale_payment_events event
    where event.store_id=sale.store_id and event.event_type='collected'
      and (event.sale_id=sale.id or event.sale_id in (
        select link.receivable_sale_id from public.sale_receivable_links link
        where link.store_id=sale.store_id and link.payment_sale_id=sale.id
      ))
  ) collection on true
  where sale.store_id=target_store_id
    and sale.business_date between target_start_date and target_end_date
    and sale.recognized_via_sale_id is null
  order by sale.business_date,sale.created_at,sale.id;
end; $$;

create or replace function public.get_owner_expense_export_rows(
  target_store_id uuid,
  target_start_date date,
  target_end_date date
) returns table (
  reference_no text,
  source_type text,
  expense_date date,
  vendor text,
  amount bigint,
  category text,
  payment_method text,
  memo text,
  accounting_category text,
  receipt_path text,
  receipt_filename text,
  receipt_file_size bigint,
  source_sale_id uuid
) language plpgsql stable security definer set search_path='' as $$
begin
  if not public.store_uses_full_expense_management(target_store_id) then
    raise exception 'Only store owners using full expense management can export expenses' using errcode='42501';
  end if;
  if target_start_date is null or target_end_date is null or target_end_date < target_start_date
     or target_end_date - target_start_date > 730 then
    raise exception 'Export date range is invalid' using errcode='22023';
  end if;
  return query
  with sale_sources as (
    select sale.id,sale.business_date,sale.customer_id,sale.delivery_tobacco_amount,
      coalesce(sum(allocation.amount),0)::bigint allocation_total,
      count(allocation.id)::integer allocation_count
    from public.sales sale
    left join public.sale_expense_allocations allocation
      on allocation.sale_id=sale.id and allocation.store_id=sale.store_id
    where sale.store_id=target_store_id
      and sale.business_date between target_start_date and target_end_date
      and sale.recognized_via_sale_id is null
      and sale.delivery_tobacco_amount>0
    group by sale.id,sale.business_date,sale.customer_id,sale.delivery_tobacco_amount
  ), export_rows as (
    select
      ('EXP-'||upper(substr(replace(expense.id::text,'-',''),1,10)))::text reference_no,
      '通常経費'::text source_type,
      expense.expense_date,
      coalesce(expense.vendor,'支払先未入力')::text vendor,
      expense.amount::bigint amount,
      expense.category::text category,
      expense.payment_method::text payment_method,
      expense.memo::text memo,
      expense.accounting_category::text accounting_category,
      receipt.storage_path::text receipt_path,
      receipt.original_filename::text receipt_filename,
      receipt.file_size::bigint receipt_file_size,
      null::uuid source_sale_id
    from public.expenses expense
    left join lateral (
      select stored.storage_path,stored.original_filename,stored.file_size
      from public.expense_receipts stored
      where stored.store_id=expense.store_id and stored.expense_id=expense.id
      order by stored.created_at desc limit 1
    ) receipt on true
    where expense.store_id=target_store_id and expense.deleted_at is null
      and expense.expense_date between target_start_date and target_end_date

    union all

    select
      ('SALEEXP-'||upper(substr(replace(allocation.id::text,'-',''),1,10)))::text,
      '売上連動'::text,
      source.business_date,
      coalesce(customer.name,'顧客名未登録')::text,
      allocation.amount::bigint,
      allocation.category::text,
      ''::text,
      allocation.memo::text,
      null::text,
      receipt.storage_path::text,
      receipt.original_filename::text,
      receipt.file_size::bigint,
      source.id
    from sale_sources source
    join public.sale_expense_allocations allocation
      on allocation.sale_id=source.id and allocation.store_id=target_store_id
    left join public.customers customer on customer.id=source.customer_id and customer.store_id=target_store_id
    left join public.sale_expense_receipts receipt
      on receipt.allocation_id=allocation.id and receipt.store_id=target_store_id
    where source.allocation_count>0 and source.allocation_total=source.delivery_tobacco_amount

    union all

    select
      ('SALE-'||upper(substr(replace(source.id::text,'-',''),1,10)))::text,
      '売上連動'::text,
      source.business_date,
      coalesce(customer.name,'顧客名未登録')::text,
      source.delivery_tobacco_amount::bigint,
      '未整理（出前・タバコ等）'::text,
      ''::text,
      '売上入力から自動反映'::text,
      null::text,
      null::text,
      null::text,
      null::bigint,
      source.id
    from sale_sources source
    left join public.customers customer on customer.id=source.customer_id and customer.store_id=target_store_id
    where source.allocation_count=0 or source.allocation_total<>source.delivery_tobacco_amount
  )
  select row.reference_no,row.source_type,row.expense_date,row.vendor,row.amount,row.category,
    row.payment_method,row.memo,row.accounting_category,row.receipt_path,row.receipt_filename,
    row.receipt_file_size,row.source_sale_id
  from export_rows row
  order by row.expense_date,row.reference_no;
end; $$;

revoke all on function public.get_owner_sales_export_rows(uuid,date,date) from public,anon;
revoke all on function public.get_owner_expense_export_rows(uuid,date,date) from public,anon;
grant execute on function public.get_owner_sales_export_rows(uuid,date,date),
  public.get_owner_expense_export_rows(uuid,date,date) to authenticated;

commit;
