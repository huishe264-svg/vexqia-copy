begin;

alter table public.employees
  add column if not exists is_active boolean not null default true,
  add column if not exists deleted_at timestamptz;

drop index if exists public.employees_store_name_unique;
create unique index employees_store_name_unique
  on public.employees (store_id, lower(trim(name)))
  where is_active;

create index if not exists employees_store_active_idx
  on public.employees (store_id, is_active);

create or replace function public.archive_employee(
  target_store_id uuid,
  target_employee_id uuid
)
returns public.employees
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_employee public.employees;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = auth.uid()
      and membership.role in ('owner', 'manager')
  ) then
    raise exception 'Only store managers can archive employees' using errcode = '42501';
  end if;

  select employee.*
  into archived_employee
  from public.employees employee
  where employee.id = target_employee_id
    and employee.store_id = target_store_id
    and employee.is_active
  for update;

  if archived_employee.id is null then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;

  update public.customers
  set employee_id = null
  where store_id = target_store_id
    and employee_id = target_employee_id;

  update public.store_users
  set employee_id = null
  where store_id = target_store_id
    and employee_id = target_employee_id;

  update public.employees
  set is_active = false,
      deleted_at = now()
  where id = target_employee_id
  returning * into archived_employee;

  return archived_employee;
end;
$$;

revoke all on function public.archive_employee(uuid, uuid) from public;
revoke all on function public.archive_employee(uuid, uuid) from anon;
grant execute on function public.archive_employee(uuid, uuid) to authenticated;

commit;
