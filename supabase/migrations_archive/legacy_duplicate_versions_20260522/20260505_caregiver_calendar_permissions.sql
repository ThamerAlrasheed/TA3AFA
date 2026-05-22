-- 20260505_caregiver_calendar_permissions.sql
-- Adds can_patient_manage_calendar column to caregiver_relations

begin;

alter table if exists public.caregiver_relations
  add column if not exists can_patient_manage_calendar boolean not null default true;

commit;
