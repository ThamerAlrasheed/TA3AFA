-- 20260418_caregiver_status_and_initial_settings.sql
-- Adds status to caregiver relations and allows initial settings during creation

begin;

-- 1. Add status column to caregiver_relations
alter table if exists public.caregiver_relations
  add column if not exists status text not null default 'pending';

-- 2. Ensure initial settings columns exist (added in previous migration, but good for completeness)
alter table if exists public.caregiver_relations
  add column if not exists can_patient_add_meds boolean not null default true,
  add column if not exists notify_patient_meds boolean not null default true,
  add column if not exists notify_patient_appointments boolean not null default true;

commit;
