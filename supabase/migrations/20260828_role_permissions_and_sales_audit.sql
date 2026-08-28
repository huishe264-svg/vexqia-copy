begin;

-- Record who created and last updated every sale.
alter table public.sales
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists sales_created_by_idx on public.sales (created_by);

create or replace function public.bottle_belongs_to_store(
  target_bottle_id uuid,
  target_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_bottle_id is null or exists (
    select 1 from public.bottles b
    where b.id = target_bottle_id and b.store_id = target_store_id
  );
$$;

create or replace function public.bottle_brand_belongs_to_store(
  target_brand_id uuid,
  target_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_brand_id is null or exists (
    select 1 from public.bottle_brands b
    where b.id = target_brand_id and b.store_id = target_store_id
  );
$$;

create or replace function public.sale_belongs_to_store(
  target_sale_id uuid,
  target_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sales s
    where s.id = target_sale_id and s.store_id = target_store_id
  );
$$;

revoke all on function public.bottle_belongs_to_store(uuid, uuid) from public;
revoke all on function public.bottle_brand_belongs_to_store(uuid, uuid) from public;
revoke all on function public.sale_belongs_to_store(uuid, uuid) from public;
grant execute on function public.bottle_belongs_to_store(uuid, uuid) to authenticated;
grant execute on function public.bottle_brand_belongs_to_store(uuid, uuid) to authenticated;
grant execute on function public.sale_belongs_to_store(uuid, uuid) to authenticated;

-- Existing sales remain owner-managed and are attributed to the oldest owner.
update public.sales s
set created_by = coalesce(
      s.created_by,
      (
        select su.user_id
        from public.store_users su
        where su.store_id = s.store_id
        order by
          case su.role when 'owner' then 0 when 'manager' then 1 else 2 end,
          su.created_at
        limit 1
      )
    ),
    updated_by = coalesce(
      s.updated_by,
      (
        select su.user_id
        from public.store_users su
        where su.store_id = s.store_id
        order by
          case su.role when 'owner' then 0 when 'manager' then 1 else 2 end,
          su.created_at
        limit 1
      )
    );

create or replace function public.set_sale_audit_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_employee_id uuid;
begin
  if tg_op = 'INSERT' then
    new.created_by := (select auth.uid());
    new.updated_by := (select auth.uid());
    new.updated_at := now();

    if not public.is_store_owner_or_manager(new.store_id) then
      caller_employee_id := public.current_store_employee_id(new.store_id);
      if caller_employee_id is null then
        raise exception 'Your account is not linked to an employee account'
          using errcode = '42501';
      end if;
      new.employee_id := caller_employee_id;
    end if;
  else
    new.store_id := old.store_id;
    new.created_by := old.created_by;
    new.updated_by := (select auth.uid());
    new.updated_at := now();

    if not public.is_store_owner_or_manager(old.store_id) then
      new.employee_id := old.employee_id;
      new.is_settled := old.is_settled;
      new.settled_at := old.settled_at;
      new.settlement_id := old.settlement_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists sales_set_audit_fields on public.sales;
create trigger sales_set_audit_fields
before insert or update on public.sales
for each row execute function public.set_sale_audit_fields();

create or replace function public.can_edit_sale(target_sale_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sales s
    where s.id = target_sale_id
      and (
        public.is_store_owner_or_manager(s.store_id)
        or (
          public.is_store_member(s.store_id)
          and s.created_by = (select auth.uid())
          and not coalesce(s.is_settled, false)
        )
      )
  );
$$;

revoke all on function public.can_edit_sale(uuid) from public;
grant execute on function public.can_edit_sale(uuid) to authenticated;

-- Every store member can see sales and analytics. Editing is role-aware.
drop policy if exists "store member access" on public.sales;
drop policy if exists "store members read sales" on public.sales;
drop policy if exists "store members create sales" on public.sales;
drop policy if exists "sale editors update sales" on public.sales;
drop policy if exists "sale editors delete sales" on public.sales;

create policy "store members read sales" on public.sales
  for select to authenticated
  using (public.is_store_member(store_id));

create policy "store members create sales" on public.sales
  for insert to authenticated
  with check (
    public.is_store_member(store_id)
    and created_by = (select auth.uid())
    and updated_by = (select auth.uid())
    and public.customer_belongs_to_store(customer_id, store_id)
    and public.employee_belongs_to_store(employee_id, store_id)
    and public.bottle_belongs_to_store(bottle_id, store_id)
    and (
      public.is_store_owner_or_manager(store_id)
      or employee_id = public.current_store_employee_id(store_id)
    )
  );

create policy "sale editors update sales" on public.sales
  for update to authenticated
  using (
    public.is_store_owner_or_manager(store_id)
    or (
      public.is_store_member(store_id)
      and created_by = (select auth.uid())
      and not coalesce(is_settled, false)
    )
  )
  with check (
    public.customer_belongs_to_store(customer_id, store_id)
    and public.employee_belongs_to_store(employee_id, store_id)
    and public.bottle_belongs_to_store(bottle_id, store_id)
    and (
      public.is_store_owner_or_manager(store_id)
      or (
        public.is_store_member(store_id)
        and created_by = (select auth.uid())
        and updated_by = (select auth.uid())
        and employee_id = public.current_store_employee_id(store_id)
        and not coalesce(is_settled, false)
      )
    )
  );

create policy "sale editors delete sales" on public.sales
  for delete to authenticated
  using (
    public.is_store_owner_or_manager(store_id)
    or (
      public.is_store_member(store_id)
      and created_by = (select auth.uid())
      and not coalesce(is_settled, false)
    )
  );

-- Companions follow the edit permission of their sale.
drop policy if exists "store member access" on public.sale_companions;
drop policy if exists "store members read sale companions" on public.sale_companions;
drop policy if exists "sale editors create companions" on public.sale_companions;
drop policy if exists "sale editors update companions" on public.sale_companions;
drop policy if exists "sale editors delete companions" on public.sale_companions;

create policy "store members read sale companions" on public.sale_companions
  for select to authenticated
  using (public.is_store_member(store_id));
create policy "sale editors create companions" on public.sale_companions
  for insert to authenticated
  with check (
    public.is_store_member(store_id)
    and public.can_edit_sale(sale_id)
    and public.sale_belongs_to_store(sale_id, store_id)
    and public.customer_belongs_to_store(customer_id, store_id)
  );
create policy "sale editors update companions" on public.sale_companions
  for update to authenticated
  using (public.can_edit_sale(sale_id))
  with check (
    public.is_store_member(store_id)
    and public.can_edit_sale(sale_id)
    and public.sale_belongs_to_store(sale_id, store_id)
    and public.customer_belongs_to_store(customer_id, store_id)
  );
create policy "sale editors delete companions" on public.sale_companions
  for delete to authenticated
  using (public.can_edit_sale(sale_id));

-- Store operations reserved for owner/manager.
drop policy if exists "store member access" on public.employees;
drop policy if exists "store members read employees" on public.employees;
drop policy if exists "store managers create employees" on public.employees;
drop policy if exists "store managers update employees" on public.employees;
drop policy if exists "store managers delete employees" on public.employees;
create policy "store members read employees" on public.employees for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create employees" on public.employees for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update employees" on public.employees for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete employees" on public.employees for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.bottle_brands;
drop policy if exists "store members read bottle brands" on public.bottle_brands;
drop policy if exists "store members create bottle brands" on public.bottle_brands;
drop policy if exists "store managers update bottle brands" on public.bottle_brands;
drop policy if exists "store managers delete bottle brands" on public.bottle_brands;
create policy "store members read bottle brands" on public.bottle_brands for select to authenticated using (public.is_store_member(store_id));
create policy "store members create bottle brands" on public.bottle_brands for insert to authenticated with check (public.is_store_member(store_id));
create policy "store managers update bottle brands" on public.bottle_brands for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete bottle brands" on public.bottle_brands for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.bottles;
drop policy if exists "store members read bottles" on public.bottles;
drop policy if exists "store members create bottles" on public.bottles;
drop policy if exists "store members update bottles" on public.bottles;
drop policy if exists "store managers delete bottles" on public.bottles;
create policy "store members read bottles" on public.bottles for select to authenticated using (public.is_store_member(store_id));
create policy "store members create bottles" on public.bottles for insert to authenticated with check (
  public.is_store_member(store_id)
  and public.customer_belongs_to_store(customer_id, store_id)
  and public.bottle_brand_belongs_to_store(brand_id, store_id)
);
create policy "store members update bottles" on public.bottles for update to authenticated using (public.is_store_member(store_id)) with check (
  public.is_store_member(store_id)
  and public.customer_belongs_to_store(customer_id, store_id)
  and public.bottle_brand_belongs_to_store(brand_id, store_id)
);
create policy "store managers delete bottles" on public.bottles for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.daily_settlements;
drop policy if exists "store members read settlements" on public.daily_settlements;
drop policy if exists "store managers create settlements" on public.daily_settlements;
drop policy if exists "store managers update settlements" on public.daily_settlements;
drop policy if exists "store managers delete settlements" on public.daily_settlements;
create policy "store members read settlements" on public.daily_settlements for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create settlements" on public.daily_settlements for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update settlements" on public.daily_settlements for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete settlements" on public.daily_settlements for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.sales_goal_settings;
drop policy if exists "store members read goal settings" on public.sales_goal_settings;
drop policy if exists "store managers create goal settings" on public.sales_goal_settings;
drop policy if exists "store managers update goal settings" on public.sales_goal_settings;
drop policy if exists "store managers delete goal settings" on public.sales_goal_settings;
create policy "store members read goal settings" on public.sales_goal_settings for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create goal settings" on public.sales_goal_settings for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update goal settings" on public.sales_goal_settings for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete goal settings" on public.sales_goal_settings for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.business_day_overrides;
drop policy if exists "store members read business overrides" on public.business_day_overrides;
drop policy if exists "store managers create business overrides" on public.business_day_overrides;
drop policy if exists "store managers update business overrides" on public.business_day_overrides;
drop policy if exists "store managers delete business overrides" on public.business_day_overrides;
create policy "store members read business overrides" on public.business_day_overrides for select to authenticated using (public.is_store_member(store_id));
create policy "store managers create business overrides" on public.business_day_overrides for insert to authenticated with check (public.is_store_owner_or_manager(store_id));
create policy "store managers update business overrides" on public.business_day_overrides for update to authenticated using (public.is_store_owner_or_manager(store_id)) with check (public.is_store_owner_or_manager(store_id));
create policy "store managers delete business overrides" on public.business_day_overrides for delete to authenticated using (public.is_store_owner_or_manager(store_id));

drop policy if exists "store member access" on public.customers;
drop policy if exists "store members read customers" on public.customers;
drop policy if exists "store members create customers" on public.customers;
drop policy if exists "store members update customers" on public.customers;
drop policy if exists "store managers delete customers" on public.customers;
create policy "store members read customers" on public.customers for select to authenticated using (public.is_store_member(store_id));
create policy "store members create customers" on public.customers for insert to authenticated with check (public.is_store_member(store_id));
create policy "store members update customers" on public.customers for update to authenticated using (public.is_store_member(store_id)) with check (public.is_store_member(store_id));
create policy "store managers delete customers" on public.customers for delete to authenticated using (public.is_store_owner_or_manager(store_id));

-- Keep staff accounts usable by requiring the employee account used for sales.
create or replace function public.update_store_member(
  target_store_id uuid,
  target_user_id uuid,
  target_role text,
  target_employee_id uuid default null
)
returns public.store_users
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  existing_member public.store_users;
  updated_member public.store_users;
begin
  select su.role into caller_role
  from public.store_users su
  where su.store_id = target_store_id
    and su.user_id = (select auth.uid());

  if caller_role is distinct from 'owner' then
    raise exception 'Only store owners can manage member permissions' using errcode = '42501';
  end if;
  if target_role not in ('manager', 'staff') then
    raise exception 'Role must be manager or staff' using errcode = '22023';
  end if;
  if target_role = 'staff' and target_employee_id is null then
    raise exception 'Staff accounts must be linked to an employee account' using errcode = '23502';
  end if;

  select su.* into existing_member
  from public.store_users su
  where su.store_id = target_store_id and su.user_id = target_user_id
  for update;
  if not found then
    raise exception 'Store member was not found' using errcode = 'P0002';
  end if;
  if existing_member.role = 'owner' then
    raise exception 'Owner permissions cannot be changed here' using errcode = '42501';
  end if;
  if target_employee_id is not null and not exists (
    select 1 from public.employees e
    where e.id = target_employee_id and e.store_id = target_store_id
  ) then
    raise exception 'Employee does not belong to this store' using errcode = '23503';
  end if;

  update public.store_users su
  set role = target_role,
      employee_id = target_employee_id,
      updated_at = now()
  where su.store_id = target_store_id and su.user_id = target_user_id
  returning su.* into updated_member;
  return updated_member;
end;
$$;

revoke all on function public.update_store_member(uuid, uuid, text, uuid) from public;
revoke all on function public.update_store_member(uuid, uuid, text, uuid) from anon;
grant execute on function public.update_store_member(uuid, uuid, text, uuid) to authenticated;

-- Staff can maintain customer details, but only managers can remove a customer
-- from the active customer list.
create or replace function public.protect_customer_archive_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.store_id := old.store_id;
  if (
    old.is_active is distinct from new.is_active
    or old.deleted_at is distinct from new.deleted_at
  ) and not public.is_store_owner_or_manager(old.store_id) then
    raise exception 'Only store managers can archive customers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists customers_protect_archive_fields on public.customers;
create trigger customers_protect_archive_fields
before update on public.customers
for each row execute function public.protect_customer_archive_fields();

grant select, insert, update, delete on public.sales to authenticated;
grant select, insert, update, delete on public.sale_companions to authenticated;

commit;

