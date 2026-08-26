begin;

alter table public.store_users
  add column if not exists employee_id uuid references public.employees(id) on delete set null;

create unique index if not exists store_users_store_employee_unique
  on public.store_users (store_id, employee_id)
  where employee_id is not null;

alter table public.schedules
  add column if not exists employee_id uuid references public.employees(id) on delete set null,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null,
  add column if not exists status text not null default '予定',
  add column if not exists party_size integer,
  add column if not exists updated_at timestamptz not null default now();

alter table public.schedules
  drop constraint if exists schedules_status_check,
  add constraint schedules_status_check
    check (status in ('予定', '来店済み', 'キャンセル')),
  drop constraint if exists schedules_party_size_check,
  add constraint schedules_party_size_check
    check (party_size is null or party_size > 0);

create index if not exists schedules_store_date_idx
  on public.schedules (store_id, schedule_date);
create index if not exists schedules_created_by_idx
  on public.schedules (created_by);
create index if not exists schedules_employee_id_idx
  on public.schedules (employee_id);

-- Existing schedules are attributed to the store owner without changing their content.
update public.schedules s
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
    )
where s.created_by is null or s.updated_by is null;

create or replace function public.is_store_owner_or_manager(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_users su
    where su.store_id = target_store_id
      and su.user_id = auth.uid()
      and su.role in ('owner', 'manager')
  );
$$;

create or replace function public.current_store_employee_id(target_store_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select su.employee_id
  from public.store_users su
  where su.store_id = target_store_id
    and su.user_id = auth.uid()
  limit 1;
$$;

create or replace function public.employee_belongs_to_store(
  target_employee_id uuid,
  target_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_employee_id is null or exists (
    select 1
    from public.employees e
    where e.id = target_employee_id
      and e.store_id = target_store_id
  );
$$;

create or replace function public.customer_belongs_to_store(
  target_customer_id uuid,
  target_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_customer_id is null or exists (
    select 1
    from public.customers c
    where c.id = target_customer_id
      and c.store_id = target_store_id
  );
$$;

create or replace function public.set_schedule_audit_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.updated_by := auth.uid();
    new.updated_at := now();
  else
    new.store_id := old.store_id;
    new.created_by := old.created_by;
    new.updated_by := auth.uid();
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists schedules_set_audit_fields on public.schedules;
create trigger schedules_set_audit_fields
before insert or update on public.schedules
for each row execute function public.set_schedule_audit_fields();

revoke all on function public.is_store_owner_or_manager(uuid) from public;
revoke all on function public.current_store_employee_id(uuid) from public;
revoke all on function public.employee_belongs_to_store(uuid, uuid) from public;
revoke all on function public.customer_belongs_to_store(uuid, uuid) from public;
grant execute on function public.is_store_owner_or_manager(uuid) to authenticated;
grant execute on function public.current_store_employee_id(uuid) to authenticated;
grant execute on function public.employee_belongs_to_store(uuid, uuid) to authenticated;
grant execute on function public.customer_belongs_to_store(uuid, uuid) to authenticated;

drop policy if exists "own memberships" on public.store_users;
drop policy if exists "store members read memberships" on public.store_users;
create policy "store members read memberships" on public.store_users
  for select to authenticated
  using (public.is_store_member(store_id));

drop policy if exists "store member access" on public.schedules;
drop policy if exists "store members read schedules" on public.schedules;
drop policy if exists "store members create schedules" on public.schedules;
drop policy if exists "schedule editors update schedules" on public.schedules;
drop policy if exists "schedule managers delete schedules" on public.schedules;

create policy "store members read schedules" on public.schedules
  for select to authenticated
  using (public.is_store_member(store_id));

create policy "store members create schedules" on public.schedules
  for insert to authenticated
  with check (
    public.is_store_member(store_id)
    and created_by = auth.uid()
    and updated_by = auth.uid()
    and public.employee_belongs_to_store(employee_id, store_id)
    and public.customer_belongs_to_store(customer_id, store_id)
  );

create policy "schedule editors update schedules" on public.schedules
  for update to authenticated
  using (
    public.is_store_owner_or_manager(store_id)
    or (
      public.is_store_member(store_id)
      and schedule_date >= current_date
      and (
        created_by = auth.uid()
        or employee_id = public.current_store_employee_id(store_id)
      )
    )
  )
  with check (
    public.is_store_member(store_id)
    and updated_by = auth.uid()
    and public.employee_belongs_to_store(employee_id, store_id)
    and public.customer_belongs_to_store(customer_id, store_id)
    and (
      public.is_store_owner_or_manager(store_id)
      or (
        schedule_date >= current_date
        and (
          created_by = auth.uid()
          or employee_id = public.current_store_employee_id(store_id)
        )
      )
    )
  );

create policy "schedule managers delete schedules" on public.schedules
  for delete to authenticated
  using (public.is_store_owner_or_manager(store_id));

grant select, insert, update, delete on public.schedules to authenticated;

commit;

