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

  insert into public.platform_admins (user_id, created_by)
  values (administrator_user_id, administrator_user_id)
  on conflict (user_id) do nothing;

  -- Platform administrators are not store owners. A hidden manager membership
  -- preserves compatibility with settlement RPCs while the directory function
  -- filters platform administrators from every store-facing member list.
  insert into public.store_users (
    store_id, user_id, role, employee_id, created_at, updated_at
  )
  select store.id, administrator_user_id, 'manager', null, now(), now()
  from public.stores store
  on conflict (store_id, user_id) do update
  set role = 'manager',
      employee_id = null,
      updated_at = now();
end;
$$;

commit;
