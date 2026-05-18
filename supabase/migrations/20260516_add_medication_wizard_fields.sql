alter table public.user_medications
  add column if not exists medication_name text,
  add column if not exists is_manual boolean not null default false,
  add column if not exists source_type text not null default 'identified',
  add column if not exists medication_form text,
  add column if not exists strength_value numeric,
  add column if not exists strength_unit text,
  add column if not exists dose_quantity numeric,
  add column if not exists dose_unit text,
  add column if not exists schedule_mode text not null default 'daily',
  add column if not exists times_per_day integer,
  add column if not exists times_per_week integer,
  add column if not exists selected_weekdays integer[] not null default '{}',
  add column if not exists interval_days integer,
  add column if not exists reminders_enabled boolean not null default true,
  add column if not exists caregiver_reminders_enabled boolean,
  add column if not exists visual_shape text,
  add column if not exists visual_color text,
  add column if not exists visual_background_color text,
  add column if not exists custom_form_text text,
  add column if not exists custom_unit_text text,
  add column if not exists source_metadata jsonb;

alter type public.food_rule_enum add value if not exists 'avoidWithFood';
alter type public.food_rule_enum add value if not exists 'notSure';

update public.user_medications
set
  medication_name = coalesce(medication_name, name),
  source_type = case when medication_id is null then 'manual' else source_type end,
  is_manual = case when medication_id is null then true else is_manual end,
  schedule_mode = case
    when is_prn = true then 'as_needed'
    when schedule_mode is null then 'daily'
    else schedule_mode
  end,
  times_per_day = coalesce(times_per_day, frequency_per_day),
  reminders_enabled = case when is_prn = true then false else reminders_enabled end
where medication_name is null
   or times_per_day is null
   or is_prn = true;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_medications_source_type_check'
  ) then
    alter table public.user_medications
      add constraint user_medications_source_type_check
      check (source_type in ('identified', 'manual'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'user_medications_schedule_mode_check'
  ) then
    alter table public.user_medications
      add constraint user_medications_schedule_mode_check
      check (schedule_mode in ('daily', 'weekly', 'specific_days', 'every_x_days', 'as_needed', 'emergency_only'));
  end if;
end $$;

comment on column public.user_medications.medication_name is 'User-visible medication name snapshot for manual or identified wizard flow.';
comment on column public.user_medications.schedule_mode is 'Guided medication wizard schedule mode; PRN modes do not generate fixed dose rows.';
comment on column public.user_medications.selected_weekdays is 'Calendar weekday integers using Foundation/Calendar convention: Sunday=1 ... Saturday=7.';
