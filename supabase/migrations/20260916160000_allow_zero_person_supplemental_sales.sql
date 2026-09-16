begin;

-- A zero-person sale is an additional payment at an existing table. It counts
-- toward revenue and settlement, but not toward visits or average spend/person.
alter table public.sales drop constraint if exists sales_party_size_check;
alter table public.sales add constraint sales_party_size_check
  check (party_size >= 0);

create or replace function public.create_reliable_sale(
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
  target_receivable_sale_ids uuid[] default array[]::uuid[]
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  caller uuid:=(select auth.uid()); saved_sale public.sales; saved_bottle public.bottles;
  companion_id uuid; emptied_id uuid; effective_employee uuid; existing_sale public.sales;
begin
  if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
  if target_request_id is null then raise exception 'Request ID is required' using errcode='22023'; end if;
  select * into existing_sale from public.sales where store_id=target_store_id and client_request_id=target_request_id;
  if found then return jsonb_build_object('sale',to_jsonb(existing_sale),'duplicate',true); end if;
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
    perform public.attach_receivables_to_sale(target_store_id,saved_sale.id,target_receivable_sale_ids);
    select * into saved_sale from public.sales where id=saved_sale.id;
  end if;
  return jsonb_build_object('sale',to_jsonb(saved_sale),'duplicate',false);
exception when unique_violation then
  select * into existing_sale from public.sales where store_id=target_store_id and client_request_id=target_request_id;
  if found then return jsonb_build_object('sale',to_jsonb(existing_sale),'duplicate',true); end if;
  raise;
end; $$;

revoke all on function public.create_reliable_sale(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[]) from public,anon;
grant execute on function public.create_reliable_sale(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[]) to authenticated;

commit;
