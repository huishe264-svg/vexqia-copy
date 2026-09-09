begin;

create table if not exists public.sale_expense_allocations (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  amount bigint not null check (amount > 0),
  category text not null check (category in ('出前','タバコ','その他')),
  memo text check (memo is null or length(memo) <= 300),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sale_expense_allocations_store_sale_idx
  on public.sale_expense_allocations(store_id, sale_id);

alter table public.sale_expense_allocations enable row level security;
drop policy if exists "store owners read sale expense allocations" on public.sale_expense_allocations;
create policy "store owners read sale expense allocations"
  on public.sale_expense_allocations for select to authenticated
  using (public.is_store_owner(store_id));
revoke all on public.sale_expense_allocations from anon, authenticated;
grant select on public.sale_expense_allocations to authenticated;

create table if not exists public.sale_expense_receipts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  allocation_id uuid not null unique references public.sale_expense_allocations(id) on delete cascade,
  storage_path text not null unique,
  original_filename text,
  mime_type text,
  file_size bigint check (file_size is null or file_size between 1 and 10485760),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sale_expense_receipts_store_allocation_idx
  on public.sale_expense_receipts(store_id, allocation_id);

alter table public.sale_expense_receipts enable row level security;
drop policy if exists "store owners read sale expense receipts" on public.sale_expense_receipts;
create policy "store owners read sale expense receipts"
  on public.sale_expense_receipts for select to authenticated
  using (public.is_store_owner(store_id));
revoke all on public.sale_expense_receipts from anon, authenticated;
grant select on public.sale_expense_receipts to authenticated;

create or replace function public.store_uses_full_expense_management(target_store_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.is_store_owner(target_store_id)
    and coalesce((select s.expense_management_mode
      from public.store_operating_settings s where s.store_id=target_store_id),'simple')='full'
$$;

drop policy if exists "store owners read sale expense allocations" on public.sale_expense_allocations;
create policy "store owners using full management read sale expense allocations"
  on public.sale_expense_allocations for select to authenticated
  using (public.store_uses_full_expense_management(store_id));
drop policy if exists "store owners read sale expense receipts" on public.sale_expense_receipts;
create policy "store owners using full management read sale expense receipts"
  on public.sale_expense_receipts for select to authenticated
  using (public.store_uses_full_expense_management(store_id));

create or replace function public.replace_sale_expense_allocations(
  target_store_id uuid,
  target_sale_id uuid,
  target_allocations jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  caller uuid := (select auth.uid());
  source_amount bigint;
  allocation_total bigint;
  item jsonb;
  item_id uuid;
  saved public.sale_expense_allocations;
  saved_rows jsonb := '[]'::jsonb;
begin
  if caller is null or not public.store_uses_full_expense_management(target_store_id) then
    raise exception 'Only store owners using full expense management can classify sale expenses' using errcode='42501';
  end if;
  if jsonb_typeof(target_allocations) <> 'array' or jsonb_array_length(target_allocations)=0 then
    raise exception 'At least one allocation is required' using errcode='22023';
  end if;
  select s.delivery_tobacco_amount into source_amount
    from public.sales s where s.id=target_sale_id and s.store_id=target_store_id for update;
  if not found or coalesce(source_amount,0)<=0 then
    raise exception 'Sale expense source was not found' using errcode='P0002';
  end if;
  if exists(select 1 from jsonb_array_elements(target_allocations) x
    where (x->>'category') not in ('出前','タバコ','その他')
       or coalesce((x->>'amount')::bigint,0)<=0
       or length(coalesce(x->>'memo',''))>300) then
    raise exception 'Allocation values are invalid' using errcode='22023';
  end if;
  select coalesce(sum((x->>'amount')::bigint),0) into allocation_total
    from jsonb_array_elements(target_allocations) x;
  if allocation_total <> source_amount then
    raise exception 'Allocation total must match the sale expense amount' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(target_allocations) x
    where nullif(x->>'id','') is not null
      and not exists(select 1 from public.sale_expense_allocations a
        where a.id=(x->>'id')::uuid and a.store_id=target_store_id and a.sale_id=target_sale_id)) then
    raise exception 'Allocation does not belong to this sale' using errcode='42501';
  end if;

  delete from storage.objects o where o.bucket_id='expense-receipts' and o.name in (
    select r.storage_path from public.sale_expense_receipts r
    join public.sale_expense_allocations a on a.id=r.allocation_id
    where a.store_id=target_store_id and a.sale_id=target_sale_id
      and not exists(select 1 from jsonb_array_elements(target_allocations) x where nullif(x->>'id','')::uuid=a.id)
  );
  delete from public.sale_expense_allocations a
    where a.store_id=target_store_id and a.sale_id=target_sale_id
      and not exists(select 1 from jsonb_array_elements(target_allocations) x where nullif(x->>'id','')::uuid=a.id);

  for item in select * from jsonb_array_elements(target_allocations) loop
    item_id := nullif(item->>'id','')::uuid;
    if item_id is null then
      insert into public.sale_expense_allocations(store_id,sale_id,amount,category,memo,created_by,updated_by)
      values(target_store_id,target_sale_id,(item->>'amount')::bigint,item->>'category',nullif(btrim(item->>'memo'),''),caller,caller)
      returning * into saved;
    else
      update public.sale_expense_allocations set amount=(item->>'amount')::bigint,
        category=item->>'category',memo=nullif(btrim(item->>'memo'),''),updated_by=caller,updated_at=now()
      where id=item_id and store_id=target_store_id and sale_id=target_sale_id returning * into saved;
    end if;
    saved_rows := saved_rows || jsonb_build_array(to_jsonb(saved));
  end loop;
  return jsonb_build_object('sale_id',target_sale_id,'source_amount',source_amount,'allocations',saved_rows);
end; $$;

create or replace function public.replace_sale_expense_receipt(
  target_store_id uuid,
  target_allocation_id uuid,
  target_storage_path text,
  target_original_filename text,
  target_mime_type text,
  target_file_size bigint
) returns public.sale_expense_receipts language plpgsql security definer set search_path='' as $$
declare caller uuid := (select auth.uid()); old_path text; saved public.sale_expense_receipts;
begin
  if caller is null or not public.store_uses_full_expense_management(target_store_id) then
    raise exception 'Only store owners can manage sale expense receipts' using errcode='42501';
  end if;
  if not exists(select 1 from public.sale_expense_allocations a where a.id=target_allocation_id and a.store_id=target_store_id) then
    raise exception 'Allocation not found' using errcode='P0002';
  end if;
  if target_storage_path not like target_store_id::text||'/sale-costs/'||target_allocation_id::text||'/%'
     or target_file_size not between 1 and 10485760 then
    raise exception 'Receipt metadata is invalid' using errcode='22023';
  end if;
  select r.storage_path into old_path from public.sale_expense_receipts r
    where r.store_id=target_store_id and r.allocation_id=target_allocation_id for update;
  insert into public.sale_expense_receipts(store_id,allocation_id,storage_path,original_filename,mime_type,file_size,created_by)
  values(target_store_id,target_allocation_id,target_storage_path,nullif(target_original_filename,''),target_mime_type,target_file_size,caller)
  on conflict(allocation_id) do update set storage_path=excluded.storage_path,
    original_filename=excluded.original_filename,mime_type=excluded.mime_type,file_size=excluded.file_size,
    created_by=caller,created_at=now(),updated_at=now()
  returning * into saved;
  if old_path is not null and old_path<>target_storage_path then
    delete from storage.objects where bucket_id='expense-receipts' and name=old_path;
  end if;
  return saved;
end; $$;

create or replace function public.delete_sale_expense_receipt(target_store_id uuid,target_receipt_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare path_to_delete text;
begin
  if (select auth.uid()) is null or not public.store_uses_full_expense_management(target_store_id) then
    raise exception 'Only store owners can manage sale expense receipts' using errcode='42501';
  end if;
  select r.storage_path into path_to_delete from public.sale_expense_receipts r
    where r.id=target_receipt_id and r.store_id=target_store_id for update;
  if path_to_delete is null then raise exception 'Receipt not found' using errcode='P0002'; end if;
  delete from storage.objects where bucket_id='expense-receipts' and name=path_to_delete;
  delete from public.sale_expense_receipts where id=target_receipt_id and store_id=target_store_id;
end; $$;

create or replace function public.get_owner_monthly_finance(target_store_id uuid,target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  month_start date:=date_trunc('month',target_month)::date;
  month_end date:=(date_trunc('month',target_month)+interval '1 month')::date;
  result jsonb;
  manual_total bigint;
  sale_cost_total bigint;
  category_rows jsonb;
begin
  if not public.store_uses_full_expense_management(target_store_id) then raise exception 'Only store owners using full expense management can view finance data' using errcode='42501'; end if;
  select jsonb_build_object(
    'month',month_start,
    'total_sales',coalesce(sum(s.total_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.recognized_via_sale_id is null),0),
    'cash_sales',coalesce(sum(s.total_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='現金' and s.recognized_via_sale_id is null),0),
    'card_sales',coalesce(sum(s.total_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='カード' and s.recognized_via_sale_id is null),0),
    'other_sales',coalesce(sum(s.total_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method not in ('現金','カード') and s.recognized_via_sale_id is null),0),
    'unpaid_amount',coalesce(sum(s.total_amount) filter(where s.payment_status='未収'),0),
    'unpaid_count',count(*) filter(where s.payment_status='未収')) into result
  from public.sales s where s.store_id=target_store_id and s.business_date>=month_start and s.business_date<month_end;

  select coalesce(sum(x.amount),0) into manual_total from public.expenses x
    where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end;
  select coalesce(sum(s.delivery_tobacco_amount),0) into sale_cost_total from public.sales s
    where s.store_id=target_store_id and s.business_date>=month_start and s.business_date<month_end
      and s.recognized_via_sale_id is null and s.delivery_tobacco_amount>0;

  with sale_sources as (
    select s.id,s.delivery_tobacco_amount,coalesce(sum(a.amount),0) allocation_total,count(a.id) allocation_count
    from public.sales s left join public.sale_expense_allocations a on a.sale_id=s.id and a.store_id=s.store_id
    where s.store_id=target_store_id and s.business_date>=month_start and s.business_date<month_end
      and s.recognized_via_sale_id is null and s.delivery_tobacco_amount>0 group by s.id,s.delivery_tobacco_amount
  ), category_source as (
    select x.category,x.amount from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end
    union all
    select a.category,a.amount from public.sale_expense_allocations a join sale_sources ss on ss.id=a.sale_id
      where ss.allocation_count>0 and ss.allocation_total=ss.delivery_tobacco_amount
    union all
    select '未整理（出前・タバコ等）',ss.delivery_tobacco_amount from sale_sources ss
      where ss.allocation_count=0 or ss.allocation_total<>ss.delivery_tobacco_amount
  ), grouped as (select category,sum(amount) amount from category_source group by category)
  select coalesce(jsonb_agg(jsonb_build_object('category',category,'amount',amount) order by amount desc),'[]'::jsonb)
    into category_rows from grouped;

  return result || jsonb_build_object(
    'collected_unpaid',coalesce((select sum(e.amount) from public.sale_payment_events e where e.store_id=target_store_id and e.event_type='collected' and e.occurred_at>=month_start and e.occurred_at<month_end),0),
    'expense_total',manual_total+sale_cost_total,
    'sale_expense_total',sale_cost_total,
    'category_expenses',category_rows,
    'supply_expense',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end and x.category in ('仕入','酒類')),0),
    'monthly_goal',coalesce((select g.target_amount from public.monthly_sales_goals g where g.store_id=target_store_id and g.goal_month=month_start),0));
end; $$;

revoke all on function public.store_uses_full_expense_management(uuid) from public,anon;
revoke all on function public.replace_sale_expense_allocations(uuid,uuid,jsonb) from public,anon;
revoke all on function public.replace_sale_expense_receipt(uuid,uuid,text,text,text,bigint) from public,anon;
revoke all on function public.delete_sale_expense_receipt(uuid,uuid) from public,anon;
grant execute on function public.store_uses_full_expense_management(uuid),
  public.replace_sale_expense_allocations(uuid,uuid,jsonb),
  public.replace_sale_expense_receipt(uuid,uuid,text,text,text,bigint),
  public.delete_sale_expense_receipt(uuid,uuid) to authenticated;

commit;
