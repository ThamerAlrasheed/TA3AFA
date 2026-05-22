alter table public.user_medications
  add column if not exists refill_reminder_enabled boolean not null default false,
  add column if not exists refill_current_supply numeric null,
  add column if not exists refill_supply_unit text null,
  add column if not exists refill_threshold_quantity numeric null,
  add column if not exists refill_estimated_runout_date date null,
  add column if not exists refill_reminder_date timestamptz null,
  add column if not exists refill_notes text null;

comment on column public.user_medications.refill_reminder_enabled is 'Whether a separate refill reminder notification should be scheduled for this medication.';
comment on column public.user_medications.refill_current_supply is 'Current medication supply quantity entered by the user.';
comment on column public.user_medications.refill_supply_unit is 'Unit for refill supply and threshold, such as tablets, capsules, mL, doses, puffs, units, or other.';
comment on column public.user_medications.refill_threshold_quantity is 'Supply quantity at or below which the user wants a refill reminder.';
comment on column public.user_medications.refill_estimated_runout_date is 'Estimated date when supply reaches the threshold, if calculable.';
comment on column public.user_medications.refill_reminder_date is 'User-visible local reminder date/time for refill notification.';
comment on column public.user_medications.refill_notes is 'Optional pharmacy or refill notes.';
