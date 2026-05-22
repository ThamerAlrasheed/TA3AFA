-- Add final missing columns that the app payload requires.
-- These were added manually in the Supabase SQL Editor on 2026-05-22.
-- This migration ensures the repo history matches production.

alter table public.user_medications
  add column if not exists is_manual boolean not null default false;

alter table public.user_medications
  add column if not exists medication_name text;

alter table public.user_medications
  add column if not exists source_type text;

-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';

-- ============================================================
-- DEVELOPER REFERENCE: Payload Column Coverage Checker
-- Run this in Supabase SQL Editor to verify no columns are missing.
-- Expected result: zero rows.
-- ============================================================
--
-- with expected_columns(column_name) as (
--   values
--     ('id'),
--     ('user_id'),
--     ('medication_id'),
--     ('dosage'),
--     ('frequency_per_day'),
--     ('frequency_hours'),
--     ('food_rule'),
--     ('dosage_times'),
--     ('is_prn'),
--     ('is_manual'),
--     ('is_manual_schedule'),
--     ('medication_name'),
--     ('source_type'),
--     ('medication_form'),
--     ('strength_value'),
--     ('strength_unit'),
--     ('dose_amount'),
--     ('dose_amount_unit'),
--     ('dose_quantity'),
--     ('dose_unit'),
--     ('dose_quantity_unit'),
--     ('strength_amount'),
--     ('parsed_strength_unit'),
--     ('concentration_amount'),
--     ('concentration_unit'),
--     ('route'),
--     ('application_area'),
--     ('dose_display'),
--     ('food_rule_source'),
--     ('dose_details_source'),
--     ('is_dose_auto_filled'),
--     ('dose_details_confirmed_by_user'),
--     ('schedule_mode'),
--     ('times_per_day'),
--     ('times_per_week'),
--     ('selected_weekdays'),
--     ('interval_days'),
--     ('reminders_enabled'),
--     ('caregiver_reminders_enabled'),
--     ('visual_shape'),
--     ('visual_color'),
--     ('visual_background_color'),
--     ('refill_reminder_enabled'),
--     ('refill_current_supply'),
--     ('refill_supply_unit'),
--     ('refill_threshold_quantity'),
--     ('refill_estimated_runout_date'),
--     ('refill_reminder_date'),
--     ('refill_reminder_mode'),
--     ('refill_notes'),
--     ('scan_source'),
--     ('scan_confidence'),
--     ('scan_confirmed_by_user'),
--     ('scan_extracted_fields'),
--     ('scan_candidate_snapshot'),
--     ('custom_form_text'),
--     ('custom_unit_text'),
--     ('source_metadata'),
--     ('start_date'),
--     ('end_date'),
--     ('notes'),
--     ('is_active')
-- )
-- select e.column_name as missing_column
-- from expected_columns e
-- left join information_schema.columns c
--   on c.table_schema = 'public'
--  and c.table_name = 'user_medications'
--  and c.column_name = e.column_name
-- where c.column_name is null
-- order by e.column_name;
