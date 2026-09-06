-- Reliability foundation shared by the original and sales-demo stores.
alter table public.sales add column if not exists client_request_id uuid default gen_random_uuid();
create unique index if not exists sales_store_client_request_unique
  on public.sales(store_id,client_request_id) where client_request_id is not null;

create table if not exists public.sale_audit_log (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  sale_id uuid not null,
  action text not null check(action in ('baseline','created','updated','deleted')),
  before_data jsonb,
  after_data jsonb,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists sale_audit_log_store_sale_idx on public.sale_audit_log(store_id,sale_id,changed_at desc);
alter table public.sale_audit_log enable row level security;
drop policy if exists "store managers read sale audit" on public.sale_audit_log;
create policy "store managers read sale audit" on public.sale_audit_log
  for select to authenticated using(public.is_store_owner_or_manager(store_id));
revoke insert,update,delete on public.sale_audit_log from anon,authenticated;
grant select on public.sale_audit_log to authenticated;

insert into public.sale_audit_log(store_id,sale_id,action,after_data,changed_by,changed_at)
select sale.store_id,sale.id,'baseline',to_jsonb(sale),sale.updated_by,coalesce(sale.updated_at,sale.created_at,now())
from public.sales sale
where not exists(select 1 from public.sale_audit_log log where log.sale_id=sale.id);

create or replace function public.audit_sale_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    insert into public.sale_audit_log(store_id,sale_id,action,after_data,changed_by) values(new.store_id,new.id,'created',to_jsonb(new),(select auth.uid()));
    return new;
  elsif tg_op='UPDATE' then
    if to_jsonb(old) is distinct from to_jsonb(new) then
      insert into public.sale_audit_log(store_id,sale_id,action,before_data,after_data,changed_by) values(new.store_id,new.id,'updated',to_jsonb(old),to_jsonb(new),(select auth.uid()));
    end if;
    return new;
  else
    insert into public.sale_audit_log(store_id,sale_id,action,before_data,changed_by) values(old.store_id,old.id,'deleted',to_jsonb(old),(select auth.uid()));
    return old;
  end if;
end; $$;
drop trigger if exists sales_audit_change on public.sales;
create trigger sales_audit_change after insert or update or delete on public.sales for each row execute function public.audit_sale_change();

create or replace function public.guard_settled_sale() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' and coalesce(old.is_settled,false) then
    raise exception '精算済みの売上は削除できません。訂正処理が必要です' using errcode='55000';
  end if;
  if tg_op='UPDATE' and coalesce(old.is_settled,false) and (
    new.store_id is distinct from old.store_id or new.business_date is distinct from old.business_date
    or new.customer_id is distinct from old.customer_id or new.employee_id is distinct from old.employee_id
    or new.payment_status is distinct from old.payment_status or new.payment_method is distinct from old.payment_method
    or new.party_size is distinct from old.party_size or new.total_amount is distinct from old.total_amount
    or new.delivery_tobacco_amount is distinct from old.delivery_tobacco_amount
    or new.consumables_amount is distinct from old.consumables_amount or new.bottle_id is distinct from old.bottle_id
    or new.notes is distinct from old.notes or new.record_type is distinct from old.record_type
    or new.recognized_via_sale_id is distinct from old.recognized_via_sale_id
  ) then
    raise exception '精算済みの売上は直接変更できません。訂正処理が必要です' using errcode='55000';
  end if;
  return case when tg_op='DELETE' then old else new end;
end; $$;
drop trigger if exists sales_00_guard_settled on public.sales;
create trigger sales_00_guard_settled before update or delete on public.sales for each row execute function public.guard_settled_sale();

create or replace function public.can_edit_sale(target_sale_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.sales sale
    where sale.id=target_sale_id and not coalesce(sale.is_settled,false) and (
      public.is_store_owner_or_manager(sale.store_id)
      or (public.is_store_member(sale.store_id) and sale.created_by=(select auth.uid()))
    )
  );
$$;

drop policy if exists "sale editors delete sales" on public.sales;
create policy "sale editors delete sales" on public.sales for delete to authenticated using(
  not coalesce(is_settled,false) and (
    public.is_store_owner_or_manager(store_id)
    or (public.is_store_member(store_id) and created_by=(select auth.uid()))
  )
);

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
  if target_business_date is null or target_party_size<1 or target_total_amount<=0 or coalesce(target_extras_amount,0)<0 then raise exception 'Invalid sale values' using errcode='22023'; end if;
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

create or replace function public.check_store_data_integrity(target_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not public.is_store_owner_or_manager(target_store_id) then raise exception 'Store manager access required' using errcode='42501'; end if;
  select jsonb_build_object(
    'checked_at',now(),
    'settled_without_settlement',count(*) filter(where sale.is_settled and sale.settlement_id is null),
    'linked_receivable_mismatch',count(*) filter(where sale.recognized_via_sale_id is not null and (sale.payment_status<>'回収済み' or sale.is_settled)),
    'invalid_amount',count(*) filter(where sale.total_amount<=0 or sale.delivery_tobacco_amount<0),
    'issue_count',count(*) filter(where (sale.is_settled and sale.settlement_id is null) or (sale.recognized_via_sale_id is not null and (sale.payment_status<>'回収済み' or sale.is_settled)) or sale.total_amount<=0 or sale.delivery_tobacco_amount<0)
  ) into result from public.sales sale where sale.store_id=target_store_id;
  return result;
end; $$;

revoke all on function public.create_reliable_sale(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[]) from public,anon;
revoke all on function public.check_store_data_integrity(uuid) from public,anon;
grant execute on function public.create_reliable_sale(uuid,uuid,date,uuid,uuid,text,text,integer,bigint,bigint,uuid,text,uuid[],uuid,text,text,uuid[],uuid[]),public.check_store_data_integrity(uuid) to authenticated;
