begin;

alter table public.store_operating_settings
  add column if not exists expense_management_mode text not null default 'simple';

alter table public.store_operating_settings
  drop constraint if exists store_operating_settings_expense_management_mode_check;

alter table public.store_operating_settings
  add constraint store_operating_settings_expense_management_mode_check
  check (expense_management_mode in ('simple', 'full', 'disabled'));

comment on column public.store_operating_settings.expense_management_mode is
  'simple: cash-register expenses only, full: owner finance and receipts, disabled: no expense entry';

commit;
