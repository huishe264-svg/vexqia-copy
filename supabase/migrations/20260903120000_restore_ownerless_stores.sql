begin;

do $$
declare
  administrator_user_id uuid;
begin
  select auth_user.id
  into administrator_user_id
  from auth.users auth_user
  where lower(auth_user.email) = lower('huishe264@gmail.com')
  order by auth_user.created_at
  limit 1;

  if administrator_user_id is null then
    raise exception 'Platform administrator account was not found in Supabase Auth';
  end if;

  -- Never leave an existing store without an owner. The platform administrator
  -- stays registered separately, and can transfer this temporary ownership to
  -- the store's real owner from the private administration screen.
  update public.store_users administrator_membership
  set role = 'owner',
      updated_at = now()
  where administrator_membership.user_id = administrator_user_id
    and administrator_membership.role = 'manager'
    and not exists (
      select 1
      from public.store_users owner_membership
      where owner_membership.store_id = administrator_membership.store_id
        and owner_membership.role = 'owner'
    );
end;
$$;

commit;
