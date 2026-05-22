-- 20260510_runtime_meds_safety_sync.sql
-- Additive production sync for Meds scheduling, food-rule persistence, and safety/profile tables.

alter type public.food_rule_enum add value if not exists 'withFood';

alter table public.user_medications
  add column if not exists dosage_times text[] default '{}'::text[],
  add column if not exists is_prn boolean not null default false,
  add column if not exists is_manual_schedule boolean not null default false;

notify pgrst, 'reload schema';
