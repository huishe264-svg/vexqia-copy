begin;

alter table public.customers
  add column if not exists employee_id uuid references public.employees(id) on delete set null;

alter table public.employees
  add column if not exists color text not null default '#65758B';

alter table public.employees
  drop constraint if exists employees_color_format;

alter table public.employees
  add constraint employees_color_format check (color ~ '^#[0-9A-Fa-f]{6}$');

create index if not exists customers_employee_id_idx
  on public.customers(employee_id);

create or replace function public.validate_customer_employee_store()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.employee_id is not null and not exists (
    select 1
    from public.employees e
    where e.id = new.employee_id
      and e.store_id = new.store_id
  ) then
    raise exception 'Employee does not belong to this store' using errcode = '23503';
  end if;
  return new;
end;
$$;

drop trigger if exists customers_validate_employee_store on public.customers;
create trigger customers_validate_employee_store
before insert or update of employee_id, store_id on public.customers
for each row execute function public.validate_customer_employee_store();

commit;

