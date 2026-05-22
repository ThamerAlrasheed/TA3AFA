-- Fix medication visual persistence: add missing columns that cause the full payload to fail,
-- forcing fallback to legacy payload which drops visual fields.
--
-- The primary culprit is caregiver_reminders_enabled missing from user_medications.
-- We also ensure all visual, schedule, refill, and scan columns exist.

-- Visual fields (the ones being dropped)
alter table public.user_medications
  add column if not exists visual_shape text;

alter table public.user_medications
  add column if not exists visual_color text;

alter table public.user_medications
  add column if not exists visual_background_color text;

-- The column that causes PGRST204 and triggers legacy fallback
alter table public.user_medications
  add column if not exists caregiver_reminders_enabled boolean not null default false;

-- Schedule fields
alter table public.user_medications
  add column if not exists schedule_mode text;

alter table public.user_medications
  add column if not exists times_per_day integer;

alter table public.user_medications
  add column if not exists times_per_week integer;

alter table public.user_medications
  add column if not exists selected_weekdays integer[];

alter table public.user_medications
  add column if not exists interval_days integer;

alter table public.user_medications
  add column if not exists reminders_enabled boolean not null default true;

-- Refill fields
alter table public.user_medications
  add column if not exists refill_reminder_enabled boolean not null default false;

alter table public.user_medications
  add column if not exists refill_current_supply numeric;

alter table public.user_medications
  add column if not exists refill_supply_unit text;

alter table public.user_medications
  add column if not exists refill_threshold_quantity numeric;

alter table public.user_medications
  add column if not exists refill_estimated_runout_date date;

alter table public.user_medications
  add column if not exists refill_reminder_date timestamptz;

alter table public.user_medications
  add column if not exists refill_reminder_mode text;

alter table public.user_medications
  add column if not exists refill_notes text;

-- Scan fields
alter table public.user_medications
  add column if not exists scan_source text;

alter table public.user_medications
  add column if not exists scan_confidence numeric;

alter table public.user_medications
  add column if not exists scan_confirmed_by_user boolean not null default false;

alter table public.user_medications
  add column if not exists scan_extracted_fields jsonb;

alter table public.user_medications
  add column if not exists scan_candidate_snapshot jsonb;

-- Other payload fields
alter table public.user_medications
  add column if not exists custom_form_text text;

alter table public.user_medications
  add column if not exists custom_unit_text text;

alter table public.user_medications
  add column if not exists source_metadata jsonb;

-- Notify PostgREST to refresh its schema cache
notify pgrst, 'reload schema';
