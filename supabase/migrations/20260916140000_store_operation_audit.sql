begin;

create table if not exists public.operation_audit_log (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  action text not null check (action in ('created', 'updated', 'deleted')),
  before_data jsonb,
  after_data jsonb,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists operation_audit_store_changed_idx
  on public.operation_audit_log (store_id, changed_at desc);
create index if not exists operation_audit_entity_idx
  on public.operation_audit_log (store_id, entity_type, entity_id, changed_at desc);

alter table public.operation_audit_log enable row level security;

drop policy if exists "store managers read operation audit" on public.operation_audit_log;
create policy "store managers read operation audit"
  on public.operation_audit_log for select to authenticated
  using (public.is_store_owner_or_manager(store_id));

revoke insert, update, delete on public.operation_audit_log from anon, authenticated;
grant select on public.operation_audit_log to authenticated;

create or replace function public.audit_store_operation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous jsonb;
  current jsonb;
  audit_store_id uuid;
  audit_entity_id uuid;
begin
  previous := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end;
  current := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end;
  audit_store_id := coalesce((current ->> 'store_id')::uuid, (previous ->> 'store_id')::uuid);
  audit_entity_id := coalesce((current ->> 'id')::uuid, (previous ->> 'id')::uuid);

  if tg_op <> 'UPDATE' or previous is distinct from current then
    insert into public.operation_audit_log (
      store_id, entity_type, entity_id, action,
      before_data, after_data, changed_by
    ) values (
      audit_store_id, tg_table_name, audit_entity_id,
      case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
      previous, current, (select auth.uid())
    );
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'customers', 'employees', 'bottles', 'schedules', 'expenses', 'daily_settlements'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'operation_audit_change', table_name);
    execute format(
      'create trigger operation_audit_change after insert or update or delete on public.%I for each row execute function public.audit_store_operation()',
      table_name
    );
  end loop;
end;
$$;

revoke all on function public.audit_store_operation() from public;

commit;
