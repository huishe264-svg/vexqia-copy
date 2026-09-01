begin;

create table if not exists public.store_invitations (
  store_id uuid not null references public.stores(id) on delete cascade,
  email text not null,
  role text not null check (role in ('manager', 'staff')),
  employee_id uuid references public.employees(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled')),
  invited_by uuid references auth.users(id) on delete set null,
  provisional_user_id uuid references auth.users(id) on delete set null,
  accepted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (store_id, email),
  check (email = lower(btrim(email))),
  check (role <> 'staff' or employee_id is not null)
);

create unique index if not exists store_invitations_pending_employee_unique
  on public.store_invitations (store_id, employee_id)
  where status = 'pending' and employee_id is not null;

create index if not exists store_invitations_pending_email_idx
  on public.store_invitations (email)
  where status = 'pending';

alter table public.store_invitations enable row level security;
revoke all on public.store_invitations from anon, authenticated;

create or replace function public.claim_store_invitations()
returns table (
  claimed_store_id uuid,
  claimed_role text,
  claimed_employee_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_email text := lower(btrim(coalesce((select auth.jwt() ->> 'email'), '')));
  invitation public.store_invitations%rowtype;
  existing_role text;
begin
  if caller_id is null or caller_email = '' then
    raise exception 'A verified login email is required' using errcode = '42501';
  end if;

  for invitation in
    select invitation_row.*
    from public.store_invitations invitation_row
    where invitation_row.email = caller_email
      and invitation_row.status = 'pending'
    order by invitation_row.created_at
    for update
  loop
    -- Older invitation code could create a provisional membership before the
    -- recipient signed in. Remove only that exact non-owner row when the final
    -- authenticated user id is different.
    if invitation.provisional_user_id is not null
       and invitation.provisional_user_id <> caller_id then
      delete from public.store_users membership
      where membership.store_id = invitation.store_id
        and membership.user_id = invitation.provisional_user_id
        and membership.role <> 'owner';
    end if;

    select membership.role
      into existing_role
    from public.store_users membership
    where membership.store_id = invitation.store_id
      and membership.user_id = caller_id;

    if existing_role = 'owner' then
      update public.store_invitations invitation_row
      set status = 'accepted',
          accepted_by = caller_id,
          accepted_at = now(),
          updated_at = now()
      where invitation_row.store_id = invitation.store_id
        and invitation_row.email = invitation.email;
    else
      insert into public.store_users (
        store_id,
        user_id,
        role,
        employee_id,
        created_at,
        updated_at
      )
      values (
        invitation.store_id,
        caller_id,
        invitation.role,
        invitation.employee_id,
        now(),
        now()
      )
      on conflict (store_id, user_id) do update
      set role = excluded.role,
          employee_id = excluded.employee_id,
          updated_at = now();

      update public.store_invitations invitation_row
      set status = 'accepted',
          accepted_by = caller_id,
          accepted_at = now(),
          updated_at = now()
      where invitation_row.store_id = invitation.store_id
        and invitation_row.email = invitation.email;
    end if;

    claimed_store_id := invitation.store_id;
    claimed_role := case when existing_role = 'owner' then 'owner' else invitation.role end;
    claimed_employee_id := case when existing_role = 'owner' then null else invitation.employee_id end;
    return next;
  end loop;
end;
$$;

revoke all on function public.claim_store_invitations() from public;
grant execute on function public.claim_store_invitations() to authenticated;

commit;
