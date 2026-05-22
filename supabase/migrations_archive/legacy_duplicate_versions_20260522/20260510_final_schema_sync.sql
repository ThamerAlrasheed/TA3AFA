-- 20260510_final_schema_sync.sql
-- Ensure all required columns for release exist and refresh schema cache.

begin;

-- 1. Hardening user_medications
alter table public.user_medications 
  add column if not exists dosage_times text[] default '{}'::text[],
  add column if not exists is_prn boolean not null default false,
  add column if not exists is_manual_schedule boolean not null default false;

-- 2. Ensure medication_dose_events has correct columns
alter table public.medication_dose_events
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'taken', 'skipped', 'missed'));

-- 3. Trigger a schema cache reload by adding a dummy comment or touching a table
comment on table public.user_medications is 'Patient medication records including smart scheduling and adherence data.';

commit;

-- Outside transaction to ensure notify reaches pgrst if supported
notify pgrst, 'reload schema';
