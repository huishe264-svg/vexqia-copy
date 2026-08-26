begin;

alter table public.store_users
  add column if not exists updated_at timestamptz not null default now();

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
  select su.role
  into caller_role
  from public.store_users su
  where su.store_id = target_store_id
    and su.user_id = (select auth.uid());

  if caller_role is distinct from 'owner' then
    raise exception 'Only store owners can manage member permissions'
      using errcode = '42501';
  end if;

  if target_role not in ('manager', 'staff') then
    raise exception 'Role must be manager or staff'
      using errcode = '22023';
  end if;

  select su.*
  into existing_member
  from public.store_users su
  where su.store_id = target_store_id
    and su.user_id = target_user_id
  for update;

  if not found then
    raise exception 'Store member was not found'
      using errcode = 'P0002';
  end if;

  if existing_member.role = 'owner' then
    raise exception 'Owner permissions cannot be changed here'
      using errcode = '42501';
  end if;

  if target_employee_id is not null and not exists (
    select 1
    from public.employees e
    where e.id = target_employee_id
      and e.store_id = target_store_id
  ) then
    raise exception 'Employee does not belong to this store'
      using errcode = '23503';
  end if;

  update public.store_users su
  set role = target_role,
      employee_id = target_employee_id,
      updated_at = now()
  where su.store_id = target_store_id
    and su.user_id = target_user_id
  returning su.* into updated_member;

  return updated_member;
end;
$$;

revoke all on function public.update_store_member(uuid, uuid, text, uuid) from public;
revoke all on function public.update_store_member(uuid, uuid, text, uuid) from anon;
grant execute on function public.update_store_member(uuid, uuid, text, uuid) to authenticated;

commit;

