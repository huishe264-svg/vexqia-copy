alter table public.stores
  add column if not exists business_day_cutoff_hour smallint not null default 7,
  add column if not exists business_timezone text not null default 'Asia/Tokyo';

alter table public.stores drop constraint if exists stores_business_day_cutoff_hour_check;
alter table public.stores
  add constraint stores_business_day_cutoff_hour_check
  check (business_day_cutoff_hour between 0 and 12);

create or replace function public.update_store_business_clock(
  target_store_id uuid,
  target_cutoff_hour smallint
)
returns public.stores
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  saved_store public.stores;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_cutoff_hour is null or target_cutoff_hour < 0 or target_cutoff_hour > 12 then
    raise exception 'Cutoff hour must be between 0 and 12' using errcode = '22023';
  end if;

  if not public.is_platform_admin()
     and not exists (
       select 1
       from public.store_users membership
       where membership.store_id = target_store_id
         and membership.user_id = caller_id
         and membership.role in ('owner', 'manager')
     ) then
    raise exception 'Only owners or managers can update the business clock' using errcode = '42501';
  end if;

  update public.stores
  set business_day_cutoff_hour = target_cutoff_hour,
      business_timezone = 'Asia/Tokyo'
  where id = target_store_id
  returning * into saved_store;

  if saved_store.id is null then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  return saved_store;
end;
$$;

revoke all on function public.update_store_business_clock(uuid, smallint) from public, anon;
grant execute on function public.update_store_business_clock(uuid, smallint) to authenticated;
