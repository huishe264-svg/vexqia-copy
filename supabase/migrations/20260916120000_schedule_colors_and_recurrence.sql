begin;

alter table public.schedules
  add column if not exists color_key text not null default 'navy',
  add column if not exists recurrence_type text not null default 'none',
  add column if not exists recurrence_end_date date,
  add column if not exists recurrence_group_id uuid;

alter table public.schedules
  drop constraint if exists schedules_color_key_check,
  add constraint schedules_color_key_check
    check (color_key in ('navy', 'gold', 'green', 'wine', 'bluegray')),
  drop constraint if exists schedules_recurrence_type_check,
  add constraint schedules_recurrence_type_check
    check (recurrence_type in ('none', 'monthly', 'yearly')),
  drop constraint if exists schedules_recurrence_end_date_check,
  add constraint schedules_recurrence_end_date_check
    check (
      (recurrence_type = 'none' and recurrence_end_date is null)
      or
      (recurrence_type <> 'none' and recurrence_end_date is not null and recurrence_end_date >= schedule_date)
    );

create index if not exists schedules_recurrence_group_idx
  on public.schedules (recurrence_group_id)
  where recurrence_group_id is not null;

comment on column public.schedules.color_key is
  'VEXQIA fixed schedule color: navy, gold, green, wine, or bluegray.';
comment on column public.schedules.recurrence_type is
  'Materialized recurrence rule used when the schedule series was created.';
comment on column public.schedules.recurrence_group_id is
  'Shared identifier for occurrences created from the same recurring schedule.';

commit;
