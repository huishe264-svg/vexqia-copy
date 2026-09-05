-- Keep the original unpaid sale as history while recognising the actual receipt
-- on the business date on which money was received.
alter table public.sales
  add column if not exists record_type text not null default 'sale',
  add column if not exists recognized_via_sale_id uuid references public.sales(id) on delete restrict;

alter table public.sales drop constraint if exists sales_record_type_check;
alter table public.sales add constraint sales_record_type_check
  check (record_type in ('sale','combined_sale','receivable_payment'));

create index if not exists sales_recognized_via_idx on public.sales(recognized_via_sale_id);

create table if not exists public.sale_receivable_links (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  payment_sale_id uuid not null references public.sales(id) on delete cascade,
  receivable_sale_id uuid not null references public.sales(id) on delete restrict,
  original_receivable_amount bigint not null check (original_receivable_amount > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(receivable_sale_id),
  check(payment_sale_id <> receivable_sale_id)
);
create index if not exists sale_receivable_links_store_idx on public.sale_receivable_links(store_id);
create index if not exists sale_receivable_links_payment_idx on public.sale_receivable_links(payment_sale_id);
alter table public.sale_receivable_links enable row level security;
drop policy if exists "store members read receivable links" on public.sale_receivable_links;
create policy "store members read receivable links" on public.sale_receivable_links
  for select to authenticated using(public.is_store_member(store_id));
revoke insert,update,delete on public.sale_receivable_links from anon,authenticated;
grant select on public.sale_receivable_links to authenticated;

create or replace function public.attach_receivables_to_sale(target_store_id uuid,target_payment_sale_id uuid,target_receivable_sale_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); payment_sale public.sales; receivable public.sales; linked_count int:=0;
begin
  if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
  select * into payment_sale from public.sales where id=target_payment_sale_id and store_id=target_store_id for update;
  if not found or payment_sale.created_by<>caller or payment_sale.is_settled or payment_sale.payment_status<>'回収済み' or payment_sale.payment_method is null then
    raise exception 'The payment sale cannot receive unpaid balances' using errcode='22023';
  end if;
  if coalesce(array_length(target_receivable_sale_ids,1),0)=0 then raise exception 'No unpaid sale selected' using errcode='22023'; end if;
  for receivable in select * from public.sales where id=any(target_receivable_sale_ids) for update loop
    if receivable.store_id<>target_store_id or receivable.customer_id<>payment_sale.customer_id or receivable.payment_status<>'未収' or receivable.recognized_via_sale_id is not null or receivable.id=payment_sale.id then
      raise exception 'Selected unpaid sale is invalid' using errcode='22023';
    end if;
    insert into public.sale_receivable_links(store_id,payment_sale_id,receivable_sale_id,original_receivable_amount,created_by)
      values(target_store_id,payment_sale.id,receivable.id,receivable.total_amount,caller);
    update public.sales set payment_status='回収済み',payment_method=payment_sale.payment_method,recognized_via_sale_id=payment_sale.id,updated_by=caller
      where id=receivable.id;
    linked_count:=linked_count+1;
  end loop;
  if linked_count<>cardinality(target_receivable_sale_ids) then raise exception 'Some unpaid sales were not found' using errcode='22023'; end if;
  update public.sales set record_type='combined_sale',updated_by=caller where id=payment_sale.id;
  return jsonb_build_object('payment_sale_id',payment_sale.id,'linked_count',linked_count);
end; $$;

create or replace function public.collect_receivable_payment(target_store_id uuid,target_receivable_sale_id uuid,target_business_date date,target_received_amount bigint,target_payment_method text)
returns public.sales language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); old_sale public.sales; payment_sale public.sales;
begin
  if caller is null or not public.is_store_member(target_store_id) then raise exception 'Store access denied' using errcode='42501'; end if;
  if target_business_date is null or target_received_amount<=0 or target_payment_method not in ('現金','カード') then raise exception 'Invalid payment data' using errcode='22023'; end if;
  select * into old_sale from public.sales where id=target_receivable_sale_id and store_id=target_store_id for update;
  if not found or old_sale.payment_status<>'未収' or old_sale.recognized_via_sale_id is not null then raise exception 'Unpaid sale is no longer available' using errcode='22023'; end if;
  insert into public.sales(store_id,business_date,customer_id,employee_id,payment_status,payment_method,party_size,total_amount,delivery_tobacco_amount,consumables_amount,notes,is_settled,created_by,updated_by,record_type)
    values(target_store_id,target_business_date,old_sale.customer_id,old_sale.employee_id,'回収済み',target_payment_method,0,target_received_amount,0,0,'過去の未収回収',false,caller,caller,'receivable_payment') returning * into payment_sale;
  insert into public.sale_receivable_links(store_id,payment_sale_id,receivable_sale_id,original_receivable_amount,created_by)
    values(target_store_id,payment_sale.id,old_sale.id,old_sale.total_amount,caller);
  update public.sales set payment_status='回収済み',payment_method=target_payment_method,recognized_via_sale_id=payment_sale.id,updated_by=caller where id=old_sale.id;
  return payment_sale;
end; $$;

create or replace function public.replace_sale_companions(target_store_id uuid,target_sale_id uuid,target_customer_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare main_customer uuid; companion_id uuid; saved_count int:=0;
begin
  if not public.can_edit_sale(target_sale_id) then raise exception 'Sale edit denied' using errcode='42501'; end if;
  select customer_id into main_customer from public.sales where id=target_sale_id and store_id=target_store_id;
  if not found then raise exception 'Sale not found' using errcode='P0002'; end if;
  delete from public.sale_companions where sale_id=target_sale_id;
  foreach companion_id in array coalesce(target_customer_ids,'{}'::uuid[]) loop
    if companion_id<>main_customer and public.customer_belongs_to_store(companion_id,target_store_id) then
      insert into public.sale_companions(store_id,sale_id,customer_id) values(target_store_id,target_sale_id,companion_id) on conflict(sale_id,customer_id) do nothing;
      saved_count:=saved_count+1;
    end if;
  end loop;
  return saved_count;
end; $$;

create or replace function public.delete_sale_with_receivable_restore(target_store_id uuid,target_sale_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare target public.sales; caller uuid:=(select auth.uid()); link record;
begin
  select * into target from public.sales where id=target_sale_id and store_id=target_store_id for update;
  if not found then raise exception 'Sale not found' using errcode='P0002'; end if;
  if not public.can_edit_sale(target_sale_id) then raise exception 'Sale delete denied' using errcode='42501'; end if;
  if target.recognized_via_sale_id is not null then raise exception '合算先の会計を先に削除してください' using errcode='22023'; end if;
  if target.is_settled then raise exception '精算済みの会計は削除できません' using errcode='22023'; end if;
  for link in select * from public.sale_receivable_links where payment_sale_id=target.id for update loop
    update public.sales set payment_status='未収',payment_method=null,recognized_via_sale_id=null,is_settled=false,settled_at=null,settlement_id=null,updated_by=caller where id=link.receivable_sale_id;
  end loop;
  delete from public.sale_receivable_links where payment_sale_id=target.id;
  delete from public.sales where id=target.id;
end; $$;

create or replace function public.prevent_settling_recognized_receivable() returns trigger language plpgsql set search_path='' as $$
begin
  if new.recognized_via_sale_id is not null and coalesce(new.is_settled,false) then raise exception 'A linked historical receivable cannot be settled again'; end if;
  return new;
end; $$;
drop trigger if exists prevent_settling_recognized_receivable on public.sales;
create trigger prevent_settling_recognized_receivable before insert or update on public.sales for each row execute function public.prevent_settling_recognized_receivable();

revoke all on function public.attach_receivables_to_sale(uuid,uuid,uuid[]) from public,anon;
revoke all on function public.collect_receivable_payment(uuid,uuid,date,bigint,text) from public,anon;
revoke all on function public.replace_sale_companions(uuid,uuid,uuid[]) from public,anon;
revoke all on function public.delete_sale_with_receivable_restore(uuid,uuid) from public,anon;
grant execute on function public.attach_receivables_to_sale(uuid,uuid,uuid[]), public.collect_receivable_payment(uuid,uuid,date,bigint,text), public.replace_sale_companions(uuid,uuid,uuid[]), public.delete_sale_with_receivable_restore(uuid,uuid) to authenticated;

-- Old unpaid rows linked to a later receipt remain visible, but never count twice.
create or replace function public.get_owner_monthly_finance(target_store_id uuid,target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare month_start date:=date_trunc('month',target_month)::date; month_end date:=(date_trunc('month',target_month)+interval '1 month')::date; result jsonb;
begin
 if not public.is_store_owner(target_store_id) then raise exception 'Only store owners can view finance data' using errcode='42501'; end if;
 select jsonb_build_object(
  'month',month_start,'total_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.recognized_via_sale_id is null),0),
  'cash_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='現金' and s.recognized_via_sale_id is null),0),
  'card_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='カード' and s.recognized_via_sale_id is null),0),
  'other_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method not in ('現金','カード') and s.recognized_via_sale_id is null),0),
  'unpaid_amount',coalesce(sum(s.total_amount) filter(where s.payment_status='未収'),0),'unpaid_count',count(*) filter(where s.payment_status='未収')) into result
 from public.sales s where s.store_id=target_store_id and s.business_date>=month_start and s.business_date<month_end;
 return result || jsonb_build_object(
  'collected_unpaid',coalesce((select sum(e.amount) from public.sale_payment_events e where e.store_id=target_store_id and e.event_type='collected' and e.occurred_at>=month_start and e.occurred_at<month_end),0),
  'expense_total',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end),0),
  'category_expenses',coalesce((select jsonb_agg(jsonb_build_object('category',q.category,'amount',q.amount) order by q.amount desc) from (select category,sum(amount) amount from public.expenses where store_id=target_store_id and deleted_at is null and expense_date>=month_start and expense_date<month_end group by category) q),'[]'::jsonb),
  'supply_expense',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end and x.category in ('仕入','酒類')),0),
  'monthly_goal',coalesce((select g.target_amount from public.monthly_sales_goals g where g.store_id=target_store_id and g.goal_month=month_start),0));
end; $$;
