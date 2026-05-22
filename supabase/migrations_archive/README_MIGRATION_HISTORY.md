# Supabase Migration History Notes

On 2026-05-22, the ISTSEH Supabase migration folder was cleaned because several older migration files used duplicate date-only version prefixes.

## Problem

Examples of duplicate prefixes:
- `20260418_*.sql` (2 files)
- `20260505_*.sql` (2 files)
- `20260509_*.sql` (4 files)
- `20260510_*.sql` (3 files)
- `20260517_*.sql` (3 files)

Supabase tracks migrations by numeric prefix, so multiple files with the same prefix caused:

```
ERROR: duplicate key value violates unique constraint "schema_migrations_pkey"
```

## Resolution

The production database had already been manually repaired through the Supabase SQL Editor before this cleanup.

### Confirmed production DB state (2026-05-22):
- The `user_medications` payload checker returned **zero missing columns**.
- The final medication payload columns were added manually:
  - `is_manual`
  - `medication_name`
  - `source_type`
- The visual/icon persistence columns existed:
  - `visual_shape`
  - `visual_color`
  - `visual_background_color`
- All dose/detail, schedule, refill, scan, and caregiver columns existed.

### What was done:
1. All old migration files were backed up to this archive directory.
2. Duplicate-prefix files were removed from `supabase/migrations/`.
3. Only clean unique-timestamp migrations remain active:
   - `20260522150000_fix_appointments_schema_and_rls.sql`
   - `20260522165400_fix_visual_persistence_missing_columns.sql`
   - `20260522180000_add_final_user_medication_payload_columns.sql`
4. These were marked as `applied` via `supabase migration repair`.
5. Old remote-only entries (`20260326`, `20260418`) were marked `reverted`.
6. `supabase db push` now returns "Remote database is up to date."

## Future Rule

All new migrations **must** use full unique timestamp prefixes:

✅ Good:
```
20260522181230_add_example_column.sql
20260522181545_fix_example_policy.sql
```

❌ Bad:
```
20260522_add_example_column.sql
20260522_fix_example_policy.sql
```

**Never create multiple migration files with the same numeric prefix.**

## Payload Coverage Checker

Run this SQL in Supabase SQL Editor to verify no columns are missing:

```sql
with expected_columns(column_name) as (
  values
    ('id'), ('user_id'), ('medication_id'), ('dosage'),
    ('frequency_per_day'), ('frequency_hours'), ('food_rule'),
    ('dosage_times'), ('is_prn'), ('is_manual'), ('is_manual_schedule'),
    ('medication_name'), ('source_type'), ('medication_form'),
    ('strength_value'), ('strength_unit'), ('dose_amount'),
    ('dose_amount_unit'), ('dose_quantity'), ('dose_unit'),
    ('dose_quantity_unit'), ('strength_amount'), ('parsed_strength_unit'),
    ('concentration_amount'), ('concentration_unit'), ('route'),
    ('application_area'), ('dose_display'), ('food_rule_source'),
    ('dose_details_source'), ('is_dose_auto_filled'),
    ('dose_details_confirmed_by_user'), ('schedule_mode'),
    ('times_per_day'), ('times_per_week'), ('selected_weekdays'),
    ('interval_days'), ('reminders_enabled'), ('caregiver_reminders_enabled'),
    ('visual_shape'), ('visual_color'), ('visual_background_color'),
    ('refill_reminder_enabled'), ('refill_current_supply'),
    ('refill_supply_unit'), ('refill_threshold_quantity'),
    ('refill_estimated_runout_date'), ('refill_reminder_date'),
    ('refill_reminder_mode'), ('refill_notes'), ('scan_source'),
    ('scan_confidence'), ('scan_confirmed_by_user'),
    ('scan_extracted_fields'), ('scan_candidate_snapshot'),
    ('custom_form_text'), ('custom_unit_text'), ('source_metadata'),
    ('start_date'), ('end_date'), ('notes'), ('is_active')
)
select e.column_name as missing_column
from expected_columns e
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = 'user_medications'
 and c.column_name = e.column_name
where c.column_name is null
order by e.column_name;
```

Expected result: **zero rows**.
