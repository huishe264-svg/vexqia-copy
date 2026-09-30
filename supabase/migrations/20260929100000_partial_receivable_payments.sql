begin;

-- Preserve the original ticket amount. The remaining balance is independent.
alter table public.sales add column if not exists receivable_remaining_amount bigint;
alter table public.sales add column if not exists receivable_current_amount bigint not null default 0;
alter table public.sales add constraint sales_receivable_remaining_check check(receivable_remaining_amount between 0 and total_amount);
alter table public.sales add constraint sales_receivable_current_check check(receivable_current_amount>=0);
alter table public.sale_receivable_links drop constraint if exists sale_receivable_links_receivable_sale_id_key;
alter table public.sale_receivable_links add constraint sale_receivable_links_payment_receivable_key unique(payment_sale_id,receivable_sale_id);
alter table public.sale_receivable_links add column requested_amount bigint;
alter table public.sale_receivable_links add column allocated_amount bigint;

-- Existing receipts cannot repay more than their actual amount. Allocate older
-- selected debts first; preserve every original link and audit record.
with ranked as (
 select l.id,l.original_receivable_amount,p.total_amount,
 coalesce(sum(l.original_receivable_amount) over(partition by l.payment_sale_id order by s.business_date,l.created_at,l.id rows between unbounded preceding and 1 preceding),0) prior
 from public.sale_receivable_links l join public.sales p on p.id=l.payment_sale_id join public.sales s on s.id=l.receivable_sale_id
)
update public.sale_receivable_links l set requested_amount=r.original_receivable_amount,
 allocated_amount=greatest(0,least(r.original_receivable_amount,r.total_amount-r.prior)) from ranked r where r.id=l.id;
alter table public.sale_receivable_links alter column requested_amount set not null;
alter table public.sale_receivable_links alter column allocated_amount set not null;
alter table public.sale_receivable_links add constraint receivable_allocation_amount_check check(requested_amount>0 and allocated_amount>=0 and allocated_amount<=requested_amount);

-- This metadata does not change a settled receipt's amount or settlement.
update public.sales p set receivable_current_amount=greatest(0,p.total_amount-q.paid)
from (select payment_sale_id,sum(allocated_amount) paid from public.sale_receivable_links group by payment_sale_id) q where p.id=q.payment_sale_id;

create or replace function public.refresh_receivable_balance(target_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare original public.sales; paid bigint; payment_id uuid; method text;
begin
 select * into original from public.sales where id=target_id for update;
 if not found then return; end if;
 select coalesce(sum(allocated_amount),0) into paid from public.sale_receivable_links where receivable_sale_id=target_id;
 if paid>original.total_amount then raise exception '未収の元金を超える返済は登録できません' using errcode='22023'; end if;
 select p.id,p.payment_method into payment_id,method from public.sale_receivable_links l join public.sales p on p.id=l.payment_sale_id
 where l.receivable_sale_id=target_id and l.allocated_amount>0 order by l.created_at,l.id limit 1;
 update public.sales set receivable_remaining_amount=case when exists(select 1 from public.sale_receivable_links where receivable_sale_id=target_id) then original.total_amount-paid else null end,
 payment_status=case when paid>=original.total_amount then '回収済み' else '未収' end,
 payment_method=case when paid>=original.total_amount then method else null end,
 recognized_via_sale_id=case when paid>=original.total_amount then payment_id else null end,
 updated_by=coalesce((select auth.uid()),updated_by) where id=target_id;
end; $$;
revoke all on function public.refresh_receivable_balance(uuid) from public,anon,authenticated;

do $$ declare row record; begin
 for row in select distinct receivable_sale_id id from public.sale_receivable_links loop
  perform public.refresh_receivable_balance(row.id);
 end loop;
end $$;

create or replace function public.attach_receivable_allocations(target_store_id uuid,target_payment_sale_id uuid,target_allocations jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); payment public.sales; debt public.sales; entry record; amount bigint; total bigint:=0; count_links int:=0;
begin
 if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
 select * into payment from public.sales where id=target_payment_sale_id and store_id=target_store_id for update;
 if not found or payment.created_by<>caller or payment.is_settled or payment.payment_status<>'回収済み' or payment.payment_method is null or payment.receivable_remaining_amount is not null then
  raise exception 'この会計には未収の返済を登録できません' using errcode='22023';
 end if;
 if exists(select 1 from public.sale_receivable_links where payment_sale_id=payment.id) then raise exception '返済は登録済みです' using errcode='22023'; end if;
 if target_allocations is null or jsonb_typeof(target_allocations)<>'array' or jsonb_array_length(target_allocations)=0 then raise exception '返済する未収を選択してください' using errcode='22023'; end if;
 -- Lock every source in a consistent order, including when payments overlap.
 for entry in select (value->>'sale_id')::uuid id,(value->>'amount')::bigint amount from jsonb_array_elements(target_allocations) order by (value->>'sale_id')::uuid loop
  amount:=entry.amount;
  select * into debt from public.sales where id=entry.id and store_id=target_store_id for update;
  if not found or debt.customer_id<>payment.customer_id or debt.payment_status<>'未収' or debt.id=payment.id or debt.is_settled
    or amount is null or amount<=0 or amount>coalesce(debt.receivable_remaining_amount,debt.total_amount) then
   raise exception '今回の返済額は未収残額以内の1円以上にしてください。残額を再確認してください' using errcode='22023';
  end if;
  if not public.is_store_owner_or_manager(target_store_id) and debt.employee_id is distinct from public.current_store_employee_id(target_store_id) then raise exception 'この未収を回収する権限がありません' using errcode='42501'; end if;
  total:=total+amount;
  if total>payment.total_amount then raise exception '返済額の合計が会計金額を超えています' using errcode='22023'; end if;
  insert into public.sale_receivable_links(store_id,payment_sale_id,receivable_sale_id,original_receivable_amount,requested_amount,allocated_amount,created_by)
   values(target_store_id,payment.id,debt.id,debt.total_amount,amount,amount,caller);
  perform public.refresh_receivable_balance(debt.id);count_links:=count_links+1;
 end loop;
 update public.sales set record_type=case when record_type='receivable_payment' then record_type else 'combined_sale' end,
 receivable_current_amount=payment.total_amount-total,updated_by=caller where id=payment.id;
 return jsonb_build_object('payment_sale_id',payment.id,'linked_count',count_links);
end; $$;
revoke all on function public.attach_receivable_allocations(uuid,uuid,jsonb) from public,anon,authenticated;

-- Compatibility for an older open browser: cap allocation at actual cash paid.
create or replace function public.attach_receivables_to_sale(target_store_id uuid,target_payment_sale_id uuid,target_receivable_sale_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare budget bigint; row record; amount bigint; allocations jsonb:='[]'::jsonb;
begin
 select total_amount into budget from public.sales where id=target_payment_sale_id and store_id=target_store_id;
 for row in select * from public.sales where id=any(target_receivable_sale_ids) order by business_date,id loop
  amount:=least(budget,coalesce(row.receivable_remaining_amount,row.total_amount));
  if amount>0 then allocations:=allocations||jsonb_build_array(jsonb_build_object('sale_id',row.id,'amount',amount));budget:=budget-amount; end if;
 end loop;
 return public.attach_receivable_allocations(target_store_id,target_payment_sale_id,allocations);
end; $$;

create or replace function public.reallocate_receivable_payment()
returns trigger language plpgsql security definer set search_path='' as $$
declare link record; budget bigint; amount bigint;
begin
 if not exists(select 1 from public.sale_receivable_links where payment_sale_id=old.id) then return case when tg_op='DELETE' then old else new end; end if;
 if tg_op='UPDATE' and (new.store_id<>old.store_id or new.customer_id<>old.customer_id or new.payment_status<>'回収済み') then
  raise exception '未収返済を含む会計の顧客・店舗・回収状態は変更できません' using errcode='22023';
 end if;
 budget:=case when tg_op='DELETE' then 0 else greatest(0,new.total_amount-old.receivable_current_amount) end;
 for link in select l.* from public.sale_receivable_links l where payment_sale_id=old.id order by receivable_sale_id loop
  perform 1 from public.sales where id=link.receivable_sale_id for update;
  amount:=least(budget,link.requested_amount);budget:=budget-amount;
  if tg_op='DELETE' then delete from public.sale_receivable_links where id=link.id;
  else update public.sale_receivable_links set allocated_amount=amount where id=link.id; end if;
  perform public.refresh_receivable_balance(link.receivable_sale_id);
 end loop;
 return case when tg_op='DELETE' then old else new end;
end; $$;
revoke all on function public.reallocate_receivable_payment() from public,anon,authenticated;
create trigger sales_reallocate_receivable_update after update of total_amount,payment_status,payment_method,customer_id,store_id on public.sales for each row execute function public.reallocate_receivable_payment();
create trigger sales_reallocate_receivable_delete before delete on public.sales for each row execute function public.reallocate_receivable_payment();

create or replace function public.protect_receivable_source()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and new.is_settled and new.receivable_remaining_amount is not null then raise exception '元の未収伝票は精算できません。返済伝票を精算してください' using errcode='22023'; end if;
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' then
   if new.receivable_remaining_amount is not null or new.receivable_current_amount<>0 then raise exception '返済情報は専用処理で登録してください' using errcode='42501'; end if;
  elsif tg_op='UPDATE' then
   if new.receivable_remaining_amount is distinct from old.receivable_remaining_amount or new.receivable_current_amount<>old.receivable_current_amount
    or exists(select 1 from public.sale_receivable_links where receivable_sale_id=old.id) then raise exception '元の未収伝票は変更できません。返済伝票を修正してください' using errcode='42501'; end if;
  end if;
 end if;
 return new;
end; $$;
create trigger sales_protect_receivable_source before insert or update on public.sales for each row execute function public.protect_receivable_source();

create or replace function public.delete_sale_with_receivable_restore(target_store_id uuid,target_sale_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare target public.sales;
begin
 select * into target from public.sales where id=target_sale_id and store_id=target_store_id for update;
 if not found then raise exception 'Sale not found' using errcode='P0002'; end if;
 if not public.can_edit_sale(target_sale_id) then raise exception 'Sale delete denied' using errcode='42501'; end if;
 if target.is_settled then raise exception '精算済みの会計は削除できません' using errcode='22023'; end if;
 if exists(select 1 from public.sale_receivable_links where receivable_sale_id=target.id) then raise exception '元の未収伝票は削除できません。返済伝票を先に削除してください' using errcode='22023'; end if;
 delete from public.sales where id=target.id;
end; $$;

create or replace function public.collect_receivable_payment(target_store_id uuid,target_receivable_sale_id uuid,target_business_date date,target_received_amount bigint,target_payment_method text)
returns public.sales language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); debt public.sales; payment public.sales;
begin
 if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
 if target_business_date is null or target_received_amount is null or target_received_amount<=0 or target_payment_method is null or target_payment_method not in ('現金','カード','銀行振込') then raise exception '回収日・金額・支払方法を確認してください' using errcode='22023'; end if;
 select * into debt from public.sales where id=target_receivable_sale_id and store_id=target_store_id for update;
 if not found or debt.payment_status<>'未収' then raise exception 'この未収はすでに回収済みです' using errcode='22023'; end if;
 insert into public.sales(store_id,business_date,customer_id,employee_id,payment_status,payment_method,party_size,total_amount,delivery_tobacco_amount,consumables_amount,notes,is_settled,created_by,updated_by,record_type)
 values(target_store_id,target_business_date,debt.customer_id,debt.employee_id,'回収済み',target_payment_method,0,target_received_amount,0,0,'過去の未収回収',false,caller,caller,'receivable_payment') returning * into payment;
 perform public.attach_receivable_allocations(target_store_id,payment.id,jsonb_build_array(jsonb_build_object('sale_id',debt.id,'amount',target_received_amount)));
 return payment;
end; $$;


-- The six-argument overload makes retries of partial collections idempotent.
-- Older clients can continue using the existing five-argument signature.
create or replace function public.collect_receivable_payment(target_store_id uuid,target_receivable_sale_id uuid,target_business_date date,target_received_amount bigint,target_payment_method text,target_request_id uuid)
returns public.sales language plpgsql security definer set search_path='' as $$
declare saved public.sales; caller uuid:=(select auth.uid());
begin
 if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
 if target_request_id is null then raise exception 'Request ID is required' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_store_id::text||target_request_id::text,0));
 select * into saved from public.sales where store_id=target_store_id and client_request_id=target_request_id;
 if found then
  if saved.created_by<>caller then raise exception 'Request access denied' using errcode='42501'; end if;
  return saved;
 end if;
 select * into saved from public.collect_receivable_payment(target_store_id,target_receivable_sale_id,target_business_date,target_received_amount,target_payment_method);
 update public.sales set client_request_id=target_request_id where id=saved.id returning * into saved;
 return saved;
end; $$;
revoke all on function public.collect_receivable_payment(uuid,uuid,date,bigint,text,uuid) from public,anon;
grant execute on function public.collect_receivable_payment(uuid,uuid,date,bigint,text,uuid) to authenticated;

-- Versioned creation RPC and monthly-finance definition follow below.

create or replace function public.create_reliable_sale_with_allocations(
  target_store_id uuid,
  target_request_id uuid,
  target_business_date date,
  target_customer_id uuid,
  target_employee_id uuid,
  target_payment_status text,
  target_payment_method text,
  target_party_size integer,
  target_total_amount bigint,
  target_extras_amount bigint,
  target_bottle_id uuid default null,
  target_notes text default null,
  target_companion_ids uuid[] default array[]::uuid[],
  target_new_bottle_brand_id uuid default null,
  target_new_bottle_name text default null,
  target_new_bottle_number text default null,
  target_emptied_bottle_ids uuid[] default array[]::uuid[],
  target_receivable_sale_ids uuid[] default array[]::uuid[],
  target_receivable_allocations jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  caller uuid:=(select auth.uid()); saved_sale public.sales; saved_bottle public.bottles;
  companion_id uuid; emptied_id uuid; effective_employee uuid; existing_sale public.sales;
begin
  if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
  if target_request_id is null then raise exception 'Request ID is required' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_store_id::text||target_request_id::text,0));
  select * into existing_sale from public.sales where store_id=target_store_id and client_request_id=target_request_id;
  if found then return jsonb_build_object('sale',to_jsonb(existing_sale),'duplicate',true); end if;
  if target_receivable_allocations is null or jsonb_typeof(target_receivable_allocations)<>'array'
    or (select count(*) from jsonb_array_elements(target_receivable_allocations))<>cardinality(coalesce(target_receivable_sale_ids,'{}'::uuid[]))
    or exists(select 1 from jsonb_array_elements(target_receivable_allocations) a where not ((a->>'sale_id')::uuid=any(target_receivable_sale_ids))) then
    raise exception '未収の選択と返済額が一致しません' using errcode='22023';
  end if;
  if target_business_date is null or target_party_size<0 or target_total_amount<=0 or coalesce(target_extras_amount,0)<0 then raise exception 'Invalid sale values' using errcode='22023'; end if;
  if target_payment_status not in ('未収','回収済み') or (target_payment_status='未収' and target_payment_method is not null) or (target_payment_status='回収済み' and target_payment_method is null) then raise exception 'Invalid payment state' using errcode='22023'; end if;
  if not public.customer_belongs_to_store(target_customer_id,target_store_id) then raise exception 'Customer/store mismatch' using errcode='22023'; end if;
  effective_employee:=case when public.is_store_owner_or_manager(target_store_id) then target_employee_id else public.current_store_employee_id(target_store_id) end;
  if effective_employee is null or not public.employee_belongs_to_store(effective_employee,target_store_id) then raise exception 'Employee/store mismatch' using errcode='22023'; end if;
  if not public.bottle_belongs_to_store(target_bottle_id,target_store_id) then raise exception 'Bottle/store mismatch' using errcode='22023'; end if;
  if target_new_bottle_brand_id is not null then
    if not public.bottle_brand_belongs_to_store(target_new_bottle_brand_id,target_store_id) or btrim(coalesce(target_new_bottle_name,''))='' then raise exception 'Bottle brand/store mismatch' using errcode='22023'; end if;
    insert into public.bottles(store_id,customer_id,brand_id,name,bottle_number,status)
      values(target_store_id,target_customer_id,target_new_bottle_brand_id,btrim(target_new_bottle_name),nullif(btrim(target_new_bottle_number),''),'保有中') returning * into saved_bottle;
  end if;
  insert into public.sales(store_id,business_date,customer_id,employee_id,payment_status,payment_method,party_size,total_amount,delivery_tobacco_amount,consumables_amount,bottle_id,notes,companion_id,is_settled,created_by,updated_by,record_type,client_request_id)
    values(target_store_id,target_business_date,target_customer_id,effective_employee,target_payment_status,target_payment_method,target_party_size,target_total_amount,coalesce(target_extras_amount,0),0,coalesce(saved_bottle.id,target_bottle_id),nullif(btrim(target_notes),''),null,false,caller,caller,case when cardinality(target_receivable_sale_ids)>0 then 'combined_sale' else 'sale' end,target_request_id)
    returning * into saved_sale;
  foreach companion_id in array coalesce(target_companion_ids,array[]::uuid[]) loop
    if companion_id<>target_customer_id and public.customer_belongs_to_store(companion_id,target_store_id) then
      insert into public.sale_companions(store_id,sale_id,customer_id) values(target_store_id,saved_sale.id,companion_id) on conflict(sale_id,customer_id) do nothing;
    else raise exception 'Companion/store mismatch' using errcode='22023'; end if;
  end loop;
  foreach emptied_id in array coalesce(target_emptied_bottle_ids,array[]::uuid[]) loop
    update public.bottles set status='飲み切り' where id=emptied_id and store_id=target_store_id and customer_id=target_customer_id;
    if not found then raise exception 'Emptied bottle/store mismatch' using errcode='22023'; end if;
  end loop;
  if cardinality(coalesce(target_receivable_sale_ids,array[]::uuid[]))>0 then
    if target_payment_status<>'回収済み' then raise exception 'Combined receivables must be recovered' using errcode='22023'; end if;
    perform public.attach_receivable_allocations(target_store_id,saved_sale.id,target_receivable_allocations);
    select * into saved_sale from public.sales where id=saved_sale.id;
  end if;
  return jsonb_build_object('sale',to_jsonb(saved_sale),'duplicate',false);
exception when unique_violation then
  select * into existing_sale from public.sales where store_id=target_store_id and client_request_id=target_request_id;
  if found then return jsonb_build_object('sale',to_jsonb(existing_sale),'duplicate',true); end if;
  raise;
end; $$;

revoke all on function public.create_reliable_sale_with_allocations(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[],jsonb) from public,anon;
grant execute on function public.create_reliable_sale_with_allocations(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[],jsonb) to authenticated;
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
    'unpaid_amount',coalesce(sum(coalesce(s.receivable_remaining_amount,s.total_amount)) filter(where s.payment_status='未収'),0),
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
    'collected_unpaid',coalesce((select sum(l.allocated_amount) from public.sale_receivable_links l join public.sales p on p.id=l.payment_sale_id where l.store_id=target_store_id and p.business_date>=month_start and p.business_date<month_end),0),
    'expense_total',manual_total+sale_cost_total,
    'sale_expense_total',sale_cost_total,
    'category_expenses',category_rows,
    'supply_expense',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end and x.category in ('仕入','酒類')),0),
    'monthly_goal',coalesce((select g.target_amount from public.monthly_sales_goals g where g.store_id=target_store_id and g.goal_month=month_start),0));
end; $$;
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
    case when sale.payment_status='未収' then coalesce(sale.receivable_remaining_amount,sale.total_amount)::bigint else sale.total_amount::bigint end,
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
commit;

