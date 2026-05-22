-- 20260510_medication_scheduling_hardening.sql
-- Additive columns for as-needed status and manual schedule tracking.

begin;

-- 1. Add is_prn (as_needed) to user_medications
alter table public.user_medications 
  add column if not exists is_prn boolean not null default false;

-- 2. Add is_manual_schedule to track user overrides of dosage_times
alter table public.user_medications 
  add column if not exists is_manual_schedule boolean not null default false;

-- 3. Update comments
comment on column public.user_medications.is_prn is 'True if this medication is taken as needed (PRN).';
comment on column public.user_medications.is_manual_schedule is 'True if the user has manually edited the dosage_times, preventing automatic routine-based updates.';

commit;
