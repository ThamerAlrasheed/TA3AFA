alter table public.user_medications
  add column if not exists refill_reminder_mode text null;

alter table public.user_medications
  add constraint user_medications_refill_reminder_mode_check
  check (
    refill_reminder_mode is null
    or refill_reminder_mode = 'automatic'
  )
  not valid;

alter table public.user_medications
  validate constraint user_medications_refill_reminder_mode_check;
