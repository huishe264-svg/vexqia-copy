begin;
-- Preserve the nullable legacy column so already-open older clients still work.
-- Discard submitted manual readings; search now derives readings locally from names.
create or replace function public.clear_legacy_customer_reading()
returns trigger language plpgsql set search_path='' as $$
begin
 new.name_kana := null;
 return new;
end $$;
create trigger clear_legacy_customer_reading
before insert or update of name_kana on public.customers
for each row execute function public.clear_legacy_customer_reading();
update public.customers set name_kana=null
where store_id in ('54012814-9c5e-4509-9279-3e6ee9c2c8eb','b547f9fd-73ab-4883-9ba4-ed8f6a57b367')
 and name_kana is not null;
commit;
