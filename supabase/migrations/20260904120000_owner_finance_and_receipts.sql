begin;

create or replace function public.is_store_owner(target_store_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_platform_admin() or exists (
    select 1 from public.store_users u
    where u.store_id = target_store_id and u.user_id = (select auth.uid()) and u.role = 'owner'
  );
$$;

alter table public.expenses add column if not exists vendor text;
alter table public.expenses add column if not exists category text;
alter table public.expenses add column if not exists payment_method text;
alter table public.expenses add column if not exists memo text;
alter table public.expenses add column if not exists accounting_category text;
alter table public.expenses add column if not exists updated_by uuid references auth.users(id);
alter table public.expenses add column if not exists updated_at timestamptz not null default now();
alter table public.expenses add column if not exists deleted_at timestamptz;
alter table public.expenses add column if not exists deleted_by uuid references auth.users(id);

update public.expenses set category = coalesce(category, 'その他'),
  payment_method = coalesce(payment_method, '現金'), memo = coalesce(memo, description),
  updated_by = coalesce(updated_by, created_by), updated_at = coalesce(updated_at, created_at);
alter table public.expenses alter column category set default 'その他';
alter table public.expenses alter column category set not null;
alter table public.expenses alter column payment_method set default '現金';
alter table public.expenses alter column payment_method set not null;
alter table public.expenses drop constraint if exists expenses_payment_method_check;
alter table public.expenses add constraint expenses_payment_method_check
  check (payment_method in ('現金','カード','振込','その他'));
alter table public.expenses add constraint expenses_vendor_length_check check (vendor is null or length(vendor) <= 120);
alter table public.expenses add constraint expenses_category_length_check check (length(category) between 1 and 60);
alter table public.expenses add constraint expenses_memo_length_check check (memo is null or length(memo) <= 500);

create index if not exists expenses_store_active_date_idx
  on public.expenses(store_id, expense_date desc) where deleted_at is null;

drop policy if exists "store members read expenses" on public.expenses;
drop policy if exists "store owners read expenses" on public.expenses;
create policy "store owners read expenses" on public.expenses for select to authenticated
  using (public.is_store_owner(store_id));

create table if not exists public.expense_receipts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  expense_id uuid not null references public.expenses(id) on delete cascade,
  storage_path text not null unique,
  original_filename text,
  mime_type text,
  file_size bigint check (file_size is null or file_size between 1 and 10485760),
  ocr_status text not null default 'not_requested' check (ocr_status in ('not_requested','pending','completed','failed')),
  ocr_candidates jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists expense_receipts_store_expense_idx on public.expense_receipts(store_id, expense_id);
alter table public.expense_receipts enable row level security;
create policy "store owners read receipts" on public.expense_receipts for select to authenticated using (public.is_store_owner(store_id));
create policy "store owners create receipts" on public.expense_receipts for insert to authenticated with check (public.is_store_owner(store_id) and created_by = (select auth.uid()));
create policy "store owners delete receipts" on public.expense_receipts for delete to authenticated using (public.is_store_owner(store_id));
grant select, insert, delete on public.expense_receipts to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('expense-receipts','expense-receipts',false,10485760,array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.can_manage_expense_receipt(object_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare folder text;
begin
  folder := split_part(object_name, '/', 1);
  if folder !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  return public.is_store_owner(folder::uuid);
exception when others then return false;
end; $$;

drop policy if exists "owners read expense receipt objects" on storage.objects;
drop policy if exists "owners create expense receipt objects" on storage.objects;
drop policy if exists "owners update expense receipt objects" on storage.objects;
drop policy if exists "owners delete expense receipt objects" on storage.objects;
create policy "owners read expense receipt objects" on storage.objects for select to authenticated
  using (bucket_id='expense-receipts' and public.can_manage_expense_receipt(name));
create policy "owners create expense receipt objects" on storage.objects for insert to authenticated
  with check (bucket_id='expense-receipts' and public.can_manage_expense_receipt(name));
create policy "owners update expense receipt objects" on storage.objects for update to authenticated
  using (bucket_id='expense-receipts' and public.can_manage_expense_receipt(name))
  with check (bucket_id='expense-receipts' and public.can_manage_expense_receipt(name));
create policy "owners delete expense receipt objects" on storage.objects for delete to authenticated
  using (bucket_id='expense-receipts' and public.can_manage_expense_receipt(name));

alter table public.cash_register_history drop constraint if exists cash_register_history_action_check;
alter table public.cash_register_history add constraint cash_register_history_action_check
 check (action in ('set_amount','settlement','reset','expense','expense_adjustment','expense_delete'));

create table if not exists public.sale_payment_events (
  id uuid primary key default gen_random_uuid(), store_id uuid not null references public.stores(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  event_type text not null check(event_type in ('unpaid_created','collected','reopened')),
  amount bigint not null default 0, payment_method text, occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id)
);
create index if not exists sale_payment_events_store_time_idx on public.sale_payment_events(store_id,occurred_at desc);
alter table public.sale_payment_events enable row level security;
create policy "store owners read payment events" on public.sale_payment_events for select to authenticated using(public.is_store_owner(store_id));
revoke insert,update,delete on public.sale_payment_events from anon,authenticated;
grant select on public.sale_payment_events to authenticated;

create or replace function public.track_sale_payment_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' and new.payment_status='未収' then
   insert into public.sale_payment_events(store_id,sale_id,event_type,amount,actor_id) values(new.store_id,new.id,'unpaid_created',new.total_amount,coalesce(new.created_by,(select auth.uid())));
 elsif tg_op='UPDATE' and old.payment_status='未収' and new.payment_status='回収済み' then
   insert into public.sale_payment_events(store_id,sale_id,event_type,amount,payment_method,actor_id) values(new.store_id,new.id,'collected',new.total_amount,new.payment_method,(select auth.uid()));
 elsif tg_op='UPDATE' and old.payment_status='回収済み' and new.payment_status='未収' then
   insert into public.sale_payment_events(store_id,sale_id,event_type,amount,actor_id) values(new.store_id,new.id,'reopened',new.total_amount,(select auth.uid()));
 end if; return new;
end; $$;
drop trigger if exists track_sale_payment_event on public.sales;
create trigger track_sale_payment_event after insert or update of payment_status on public.sales for each row execute function public.track_sale_payment_event();

create or replace function public.create_store_expense(target_store_id uuid,target_expense_date date,target_amount bigint,target_vendor text,target_category text,target_payment_method text,target_memo text default null,target_accounting_category text default null)
returns public.expenses language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); before_amount bigint; saved public.expenses;
begin
 if caller is null or not public.is_store_owner(target_store_id) then raise exception 'Only store owners can manage expenses' using errcode='42501'; end if;
 if target_expense_date is null or target_amount<=0 or btrim(coalesce(target_category,''))='' or target_payment_method not in ('現金','カード','振込','その他') then raise exception 'Invalid expense data' using errcode='22023'; end if;
 insert into public.expenses(store_id,expense_date,amount,vendor,category,payment_method,memo,accounting_category,description,created_by,updated_by)
 values(target_store_id,target_expense_date,target_amount,nullif(btrim(target_vendor),''),btrim(target_category),target_payment_method,nullif(btrim(target_memo),''),nullif(btrim(target_accounting_category),''),nullif(btrim(target_memo),''),caller,caller) returning * into saved;
 if target_payment_method='現金' then
  insert into public.cash_registers(store_id,base_amount,current_amount,updated_by) values(target_store_id,0,0,caller) on conflict(store_id) do nothing;
  select current_amount into before_amount from public.cash_registers where store_id=target_store_id for update;
  update public.cash_registers set current_amount=before_amount-target_amount,updated_by=caller,updated_at=now() where store_id=target_store_id;
  insert into public.cash_register_history(store_id,action,amount_delta,balance_before,balance_after,base_amount,business_date,expense_id,created_by)
   select target_store_id,'expense',-target_amount,before_amount,before_amount-target_amount,base_amount,target_expense_date,saved.id,caller from public.cash_registers where store_id=target_store_id;
 end if; return saved;
end; $$;

create or replace function public.update_store_expense(target_store_id uuid,target_expense_id uuid,target_expense_date date,target_amount bigint,target_vendor text,target_category text,target_payment_method text,target_memo text default null,target_accounting_category text default null)
returns public.expenses language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); old public.expenses; saved public.expenses; before_amount bigint; cash_delta bigint;
begin
 if caller is null or not public.is_store_owner(target_store_id) then raise exception 'Only store owners can manage expenses' using errcode='42501'; end if;
 select * into old from public.expenses where id=target_expense_id and store_id=target_store_id and deleted_at is null for update; if not found then raise exception 'Expense not found' using errcode='P0002'; end if;
 if target_amount<=0 or btrim(coalesce(target_category,''))='' or target_payment_method not in ('現金','カード','振込','その他') then raise exception 'Invalid expense data' using errcode='22023'; end if;
 cash_delta := (case when old.payment_method='現金' then old.amount else 0 end) - (case when target_payment_method='現金' then target_amount else 0 end);
 update public.expenses set expense_date=target_expense_date,amount=target_amount,vendor=nullif(btrim(target_vendor),''),category=btrim(target_category),payment_method=target_payment_method,memo=nullif(btrim(target_memo),''),accounting_category=nullif(btrim(target_accounting_category),''),description=nullif(btrim(target_memo),''),updated_by=caller,updated_at=now() where id=target_expense_id returning * into saved;
 if cash_delta<>0 then
  select current_amount into before_amount from public.cash_registers where store_id=target_store_id for update;
  update public.cash_registers set current_amount=before_amount+cash_delta,updated_by=caller,updated_at=now() where store_id=target_store_id;
  insert into public.cash_register_history(store_id,action,amount_delta,balance_before,balance_after,base_amount,business_date,expense_id,created_by)
   select target_store_id,'expense_adjustment',cash_delta,before_amount,before_amount+cash_delta,base_amount,target_expense_date,saved.id,caller from public.cash_registers where store_id=target_store_id;
 end if; return saved;
end; $$;

create or replace function public.delete_store_expense(target_store_id uuid,target_expense_id uuid)
returns public.expenses language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid()); old public.expenses; saved public.expenses; before_amount bigint;
begin
 if caller is null or not public.is_store_owner(target_store_id) then raise exception 'Only store owners can manage expenses' using errcode='42501'; end if;
 select * into old from public.expenses where id=target_expense_id and store_id=target_store_id and deleted_at is null for update; if not found then raise exception 'Expense not found' using errcode='P0002'; end if;
 update public.expenses set deleted_at=now(),deleted_by=caller,updated_by=caller,updated_at=now() where id=target_expense_id returning * into saved;
 if old.payment_method='現金' then
  select current_amount into before_amount from public.cash_registers where store_id=target_store_id for update;
  update public.cash_registers set current_amount=before_amount+old.amount,updated_by=caller,updated_at=now() where store_id=target_store_id;
  insert into public.cash_register_history(store_id,action,amount_delta,balance_before,balance_after,base_amount,business_date,expense_id,created_by)
   select target_store_id,'expense_delete',old.amount,before_amount,before_amount+old.amount,base_amount,old.expense_date,old.id,caller from public.cash_registers where store_id=target_store_id;
 end if; return saved;
end; $$;

create or replace function public.get_owner_monthly_finance(target_store_id uuid,target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare month_start date:=date_trunc('month',target_month)::date; month_end date:=(date_trunc('month',target_month)+interval '1 month')::date; result jsonb;
begin
 if not public.is_store_owner(target_store_id) then raise exception 'Only store owners can view finance data' using errcode='42501'; end if;
 select jsonb_build_object(
  'month',month_start,'total_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み'),0),
  'cash_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='現金'),0),
  'card_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method='カード'),0),
  'other_sales',coalesce(sum(s.total_amount-s.delivery_tobacco_amount) filter(where s.is_settled and s.payment_status='回収済み' and s.payment_method not in ('現金','カード')),0),
  'unpaid_amount',coalesce(sum(s.total_amount) filter(where s.payment_status='未収'),0),'unpaid_count',count(*) filter(where s.payment_status='未収')) into result
 from public.sales s where s.store_id=target_store_id and s.business_date>=month_start and s.business_date<month_end;
 return result || jsonb_build_object(
  'collected_unpaid',coalesce((select sum(e.amount) from public.sale_payment_events e where e.store_id=target_store_id and e.event_type='collected' and e.occurred_at>=month_start and e.occurred_at<month_end),0),
  'expense_total',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end),0),
  'category_expenses',coalesce((select jsonb_agg(jsonb_build_object('category',q.category,'amount',q.amount) order by q.amount desc) from (select category,sum(amount) amount from public.expenses where store_id=target_store_id and deleted_at is null and expense_date>=month_start and expense_date<month_end group by category) q),'[]'::jsonb),
  'supply_expense',coalesce((select sum(x.amount) from public.expenses x where x.store_id=target_store_id and x.deleted_at is null and x.expense_date>=month_start and x.expense_date<month_end and x.category in ('仕入','酒類')),0),
  'monthly_goal',coalesce((select g.target_amount from public.monthly_sales_goals g where g.store_id=target_store_id and g.goal_month=month_start),0));
end; $$;

revoke all on function public.is_store_owner(uuid) from public,anon;
grant execute on function public.is_store_owner(uuid) to authenticated;
revoke all on function public.create_store_expense(uuid,date,bigint,text,text,text,text,text) from public,anon;
revoke all on function public.update_store_expense(uuid,uuid,date,bigint,text,text,text,text,text) from public,anon;
revoke all on function public.delete_store_expense(uuid,uuid) from public,anon;
revoke all on function public.get_owner_monthly_finance(uuid,date) from public,anon;
grant execute on function public.create_store_expense(uuid,date,bigint,text,text,text,text,text), public.update_store_expense(uuid,uuid,date,bigint,text,text,text,text,text), public.delete_store_expense(uuid,uuid), public.get_owner_monthly_finance(uuid,date) to authenticated;

-- Existing compatibility RPC becomes owner-only. New UI uses create_store_expense.
create or replace function public.record_store_expense(target_store_id uuid,target_expense_date date,target_amount bigint,target_description text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved public.expenses;
begin
 saved:=public.create_store_expense(target_store_id,target_expense_date,target_amount,null,'その他','現金',target_description,null);
 return jsonb_build_object('expense',to_jsonb(saved),(select 'cash_register'),(select to_jsonb(r) from public.cash_registers r where r.store_id=target_store_id));
end; $$;

commit;
