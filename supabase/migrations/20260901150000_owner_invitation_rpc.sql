begin;

create or replace function public.save_store_invitation(
  target_store_id uuid,
  target_email text,
  target_role text,
  target_employee_id uuid default null,
  target_provisional_user_id uuid default null
)
returns public.store_invitations
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_email text := lower(btrim(coalesce(target_email, '')));
  saved_invitation public.store_invitations;
begin
  if caller_id is null or not exists (
    select 1
    from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role = 'owner'
  ) then
    raise exception 'Only store owners can create invitations'
      using errcode = '42501';
  end if;

  if normalized_email = '' or position('@' in normalized_email) = 0 then
    raise exception 'Valid email is required'
      using errcode = '22023';
  end if;

  if target_role not in ('manager', 'staff') then
    raise exception 'Role must be manager or staff'
      using errcode = '22023';
  end if;

  if target_role = 'staff' and target_employee_id is null then
    raise exception 'Staff accounts must be linked to an employee account'
      using errcode = '23502';
  end if;

  if target_employee_id is not null and not exists (
    select 1
    from public.employees employee
    where employee.id = target_employee_id
      and employee.store_id = target_store_id
  ) then
    raise exception 'Employee does not belong to this store'
      using errcode = '23503';
  end if;

  insert into public.store_invitations (
    store_id,
    email,
    role,
    employee_id,
    status,
    invited_by,
    provisional_user_id,
    accepted_by,
    accepted_at,
    updated_at
  )
  values (
    target_store_id,
    normalized_email,
    target_role,
    target_employee_id,
    'pending',
    caller_id,
    target_provisional_user_id,
    null,
    null,
    now()
  )
  on conflict (store_id, email) do update
  set role = excluded.role,
      employee_id = excluded.employee_id,
      status = 'pending',
      invited_by = excluded.invited_by,
      provisional_user_id = excluded.provisional_user_id,
      accepted_by = null,
      accepted_at = null,
      updated_at = now()
  returning * into saved_invitation;

  return saved_invitation;
end;
$$;

revoke all on function public.save_store_invitation(uuid, text, text, uuid, uuid) from public;
revoke all on function public.save_store_invitation(uuid, text, text, uuid, uuid) from anon;
grant execute on function public.save_store_invitation(uuid, text, text, uuid, uuid) to authenticated;

commit;

