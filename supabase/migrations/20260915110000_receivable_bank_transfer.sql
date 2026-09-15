begin;
-- Bank transfers are received revenue without cash-register inflow.
alter table public.sales drop constraint if exists sales_payment_method_check;
alter table public.sales add constraint sales_payment_method_check check (
 (payment_status='未収' and payment_method is null)
 or (payment_status='回収済み' and payment_method is not null and payment_method in ('現金','カード','銀行振込'))
);

create or replace function public.collect_receivable_payment(
  target_store_id uuid,
  target_receivable_sale_id uuid,
  target_business_date date,
  target_received_amount bigint,
  target_payment_method text
)
returns public.sales language plpgsql security definer set search_path='' as $$
declare caller uuid := (select auth.uid()); old_sale public.sales; payment_sale public.sales;
begin
  if caller is null or not public.is_store_member(target_store_id) then
    raise exception 'この店舗の未収を回収する権限がありません' using errcode='42501';
  end if;
  if target_business_date is null or target_received_amount is null or target_received_amount <= 0 or target_payment_method is null or target_payment_method not in ('現金','カード','銀行振込') then
    raise exception '回収日・金額・支払方法を確認してください' using errcode='22023';
  end if;

  select * into old_sale from public.sales
  where id=target_receivable_sale_id and store_id=target_store_id for update;
  if not found or old_sale.payment_status<>'未収' or old_sale.recognized_via_sale_id is not null then
    raise exception 'この未収はすでに回収済みか、現在利用できません' using errcode='22023';
  end if;
  if not public.is_store_owner_or_manager(target_store_id)
     and old_sale.employee_id is distinct from public.current_store_employee_id(target_store_id) then
    raise exception 'この未収を回収できるのは、紐づいた口座または店舗管理者です' using errcode='42501';
  end if;

  insert into public.sales(
    store_id,business_date,customer_id,employee_id,payment_status,payment_method,
    party_size,total_amount,delivery_tobacco_amount,consumables_amount,notes,
    is_settled,created_by,updated_by,record_type
  ) values (
    target_store_id,target_business_date,old_sale.customer_id,old_sale.employee_id,
    '回収済み',target_payment_method,0,target_received_amount,0,0,
    '過去の未収回収',false,caller,caller,'receivable_payment'
  ) returning * into payment_sale;

  insert into public.sale_receivable_links(store_id,payment_sale_id,receivable_sale_id,original_receivable_amount,created_by)
    values(target_store_id,payment_sale.id,old_sale.id,old_sale.total_amount,caller);
  update public.sales set payment_status='回収済み',payment_method=target_payment_method,
    recognized_via_sale_id=payment_sale.id,updated_by=caller where id=old_sale.id;
  return payment_sale;
end; $$;

revoke all on function public.collect_receivable_payment(uuid,uuid,date,bigint,text) from public,anon;
grant execute on function public.collect_receivable_payment(uuid,uuid,date,bigint,text) to authenticated;
commit;
