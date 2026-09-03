begin;

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins administrator
    where administrator.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_store_member(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_platform_admin() or exists (
    select 1
    from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_store_owner_or_manager(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_platform_admin() or exists (
    select 1
    from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'manager')
  );
$$;

create or replace function public.get_accessible_stores()
returns table (id uuid, name text, access_role text)
language sql
stable
security definer
set search_path = ''
as $$
  select store.id,
         store.name,
         case when public.is_platform_admin() then 'admin' else membership.role end
  from public.stores store
  left join public.store_users membership
    on membership.store_id = store.id
   and membership.user_id = (select auth.uid())
  where public.is_platform_admin() or membership.user_id is not null
  order by store.name, store.created_at;
$$;

alter table public.store_invitations
  drop constraint if exists store_invitations_role_check;
alter table public.store_invitations
  add constraint store_invitations_role_check
  check (role in ('owner', 'manager', 'staff'));

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
  if caller_id is null or not (
    public.is_platform_admin() or exists (
      select 1 from public.store_users membership
      where membership.store_id = target_store_id
        and membership.user_id = caller_id
        and membership.role = 'owner'
    )
  ) then
    raise exception 'Only store owners or platform administrators can create invitations'
      using errcode = '42501';
  end if;

  if normalized_email = '' or position('@' in normalized_email) = 0 then
    raise exception 'Valid email is required' using errcode = '22023';
  end if;
  if target_role not in ('owner', 'manager', 'staff') then
    raise exception 'Role must be owner, manager or staff' using errcode = '22023';
  end if;
  if target_role = 'staff' and target_employee_id is null then
    raise exception 'Staff accounts must be linked to an employee account' using errcode = '23502';
  end if;
  if target_role = 'owner' then
    target_employee_id := null;
  end if;
  if target_employee_id is not null and not exists (
    select 1 from public.employees employee
    where employee.id = target_employee_id and employee.store_id = target_store_id
  ) then
    raise exception 'Employee does not belong to this store' using errcode = '23503';
  end if;

  insert into public.store_invitations (
    store_id, email, role, employee_id, status, invited_by,
    provisional_user_id, accepted_by, accepted_at, updated_at
  ) values (
    target_store_id, normalized_email, target_role, target_employee_id, 'pending', caller_id,
    target_provisional_user_id, null, null, now()
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

create or replace function public.create_managed_store(
  target_name text,
  target_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  normalized_name text := btrim(coalesce(target_name, ''));
  normalized_email text := lower(btrim(coalesce(target_owner_email, '')));
  created_store public.stores;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception 'Only platform administrators can create stores' using errcode = '42501';
  end if;
  if normalized_name = '' then
    raise exception 'Store name is required' using errcode = '22023';
  end if;
  if normalized_email = '' or position('@' in normalized_email) = 0 then
    raise exception 'Valid owner email is required' using errcode = '22023';
  end if;

  insert into public.stores (name)
  values (normalized_name)
  returning * into created_store;

  -- A hidden manager membership lets platform administrators exercise existing
  -- settlement RPCs without exposing them in the store-facing member directory.
  insert into public.store_users (store_id, user_id, role, employee_id, created_at, updated_at)
  select created_store.id, administrator.user_id, 'manager', null, now(), now()
  from public.platform_admins administrator
  on conflict (store_id, user_id) do update
  set role = 'manager', employee_id = null, updated_at = now();

  insert into public.store_invitations (
    store_id, email, role, employee_id, status, invited_by, updated_at
  ) values (
    created_store.id, normalized_email, 'owner', null, 'pending', caller_id, now()
  );

  return jsonb_build_object(
    'store_id', created_store.id,
    'store_name', created_store.name,
    'owner_email', normalized_email
  );
end;
$$;

create or replace function public.transfer_store_ownership(
  target_store_id uuid,
  target_user_id uuid,
  previous_owner_action text default 'manager'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_is_owner boolean;
begin
  select exists (
    select 1 from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = caller_id
      and membership.role = 'owner'
  ) into caller_is_owner;

  if caller_id is null or not (public.is_platform_admin() or caller_is_owner) then
    raise exception 'Only the current owner or platform administrator can transfer ownership'
      using errcode = '42501';
  end if;
  if previous_owner_action not in ('manager', 'remove') then
    raise exception 'Previous owner action must be manager or remove' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.store_users membership
    where membership.store_id = target_store_id
      and membership.user_id = target_user_id
  ) then
    raise exception 'New owner must log in and join the store first' using errcode = 'P0002';
  end if;

  update public.store_users
  set role = 'owner', employee_id = null, updated_at = now()
  where store_id = target_store_id and user_id = target_user_id;

  if previous_owner_action = 'remove' then
    delete from public.store_users
    where store_id = target_store_id
      and role = 'owner'
      and user_id <> target_user_id;
  else
    update public.store_users
    set role = 'manager', employee_id = null, updated_at = now()
    where store_id = target_store_id
      and role = 'owner'
      and user_id <> target_user_id;
  end if;

  return jsonb_build_object(
    'store_id', target_store_id,
    'owner_user_id', target_user_id,
    'previous_owner_action', previous_owner_action
  );
end;
$$;

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
  select membership.role into caller_role
  from public.store_users membership
  where membership.store_id = target_store_id
    and membership.user_id = (select auth.uid());

  if not public.is_platform_admin() and caller_role is distinct from 'owner' then
    raise exception 'Only store owners can manage member permissions' using errcode = '42501';
  end if;
  if target_role not in ('manager', 'staff') then
    raise exception 'Role must be manager or staff' using errcode = '22023';
  end if;
  if target_role = 'staff' and target_employee_id is null then
    raise exception 'Staff accounts must be linked to an employee account' using errcode = '23502';
  end if;

  select membership.* into existing_member
  from public.store_users membership
  where membership.store_id = target_store_id and membership.user_id = target_user_id
  for update;
  if not found then
    raise exception 'Store member was not found' using errcode = 'P0002';
  end if;
  if existing_member.role = 'owner' then
    raise exception 'Use ownership transfer for owner permissions' using errcode = '42501';
  end if;
  if target_employee_id is not null and not exists (
    select 1 from public.employees employee
    where employee.id = target_employee_id and employee.store_id = target_store_id
  ) then
    raise exception 'Employee does not belong to this store' using errcode = '23503';
  end if;

  update public.store_users membership
  set role = target_role, employee_id = target_employee_id, updated_at = now()
  where membership.store_id = target_store_id and membership.user_id = target_user_id
  returning membership.* into updated_member;
  return updated_member;
end;
$$;

create or replace function public.get_store_member_directory(target_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  members_json jsonb;
  invitations_json jsonb;
begin
  if caller_id is null or not (
    public.is_platform_admin() or exists (
      select 1 from public.store_users membership
      where membership.store_id = target_store_id
        and membership.user_id = caller_id
        and membership.role = 'owner'
    )
  ) then
    raise exception 'Only store owners can view member email addresses' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(member_row) order by member_row.created_at), '[]'::jsonb)
  into members_json
  from (
    select membership.store_id, membership.user_id, membership.role,
           membership.employee_id, membership.created_at, membership.updated_at,
           coalesce(auth_user.email, '') as email
    from public.store_users membership
    left join auth.users auth_user on auth_user.id = membership.user_id
    where membership.store_id = target_store_id
      and not exists (
        select 1 from public.platform_admins administrator
        where administrator.user_id = membership.user_id
      )
  ) member_row;

  select coalesce(jsonb_agg(to_jsonb(invitation_row) order by invitation_row.created_at), '[]'::jsonb)
  into invitations_json
  from (
    select invitation.store_id, invitation.email, invitation.role, invitation.employee_id,
           invitation.status, invitation.created_at, invitation.updated_at
    from public.store_invitations invitation
    where invitation.store_id = target_store_id and invitation.status = 'pending'
  ) invitation_row;

  return jsonb_build_object('members', members_json, 'invitations', invitations_json);
end;
$$;

revoke all on function public.is_platform_admin() from public, anon;
revoke all on function public.get_accessible_stores() from public, anon;
revoke all on function public.create_managed_store(text, text) from public, anon;
revoke all on function public.transfer_store_ownership(uuid, uuid, text) from public, anon;
revoke all on function public.save_store_invitation(uuid, text, text, uuid, uuid) from public, anon;
revoke all on function public.update_store_member(uuid, uuid, text, uuid) from public, anon;
revoke all on function public.get_store_member_directory(uuid) from public, anon;

grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.get_accessible_stores() to authenticated;
grant execute on function public.create_managed_store(text, text) to authenticated;
grant execute on function public.transfer_store_ownership(uuid, uuid, text) to authenticated;
grant execute on function public.save_store_invitation(uuid, text, text, uuid, uuid) to authenticated;
grant execute on function public.update_store_member(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.get_store_member_directory(uuid) to authenticated;

commit;
