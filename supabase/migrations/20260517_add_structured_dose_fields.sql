alter table public.user_medications
  add column if not exists dose_amount numeric null,
  add column if not exists dose_amount_unit text null,
  add column if not exists dose_quantity_unit text null,
  add column if not exists strength_amount numeric null,
  add column if not exists parsed_strength_unit text null,
  add column if not exists concentration_amount numeric null,
  add column if not exists concentration_unit text null,
  add column if not exists route text null,
  add column if not exists application_area text null,
  add column if not exists dose_display text null,
  add column if not exists food_rule_source text null,
  add column if not exists dose_details_source text null,
  add column if not exists is_dose_auto_filled boolean not null default false,
  add column if not exists dose_details_confirmed_by_user boolean not null default false;

update public.user_medications
set
  strength_amount = coalesce(strength_amount, strength_value),
  parsed_strength_unit = coalesce(parsed_strength_unit, strength_unit),
  dose_quantity_unit = coalesce(dose_quantity_unit, dose_unit),
  dose_display = coalesce(dose_display, dosage)
where strength_amount is null
   or parsed_strength_unit is null
   or dose_quantity_unit is null
   or dose_display is null;

comment on column public.user_medications.dose_amount is 'Parsed numeric dose amount, when distinct from quantity per intake.';
comment on column public.user_medications.dose_amount_unit is 'Unit for dose_amount.';
comment on column public.user_medications.dose_quantity_unit is 'Unit for quantity per intake, such as tablets, capsules, mL, drops, puffs, sprays, patches, or doses.';
comment on column public.user_medications.strength_amount is 'Parsed strength amount from selected or entered dose size.';
comment on column public.user_medications.parsed_strength_unit is 'Parsed strength unit from selected or entered dose size.';
comment on column public.user_medications.concentration_amount is 'Parsed concentration amount, such as 10 for 10 mg/mL.';
comment on column public.user_medications.concentration_unit is 'Parsed concentration unit, such as mg/mL.';
comment on column public.user_medications.route is 'Optional route for injections or route-specific medicines.';
comment on column public.user_medications.application_area is 'Optional application or target area for topical, drops, sprays, and patches.';
comment on column public.user_medications.dose_display is 'User-facing dose label used in lists, Today, Calendar, and notifications.';
comment on column public.user_medications.food_rule_source is 'Source of food timing rule, such as source or user.';
comment on column public.user_medications.dose_details_source is 'Source of structured dose details, such as auto or user.';
comment on column public.user_medications.is_dose_auto_filled is 'Whether dose details were auto-filled from parser/source.';
comment on column public.user_medications.dose_details_confirmed_by_user is 'Whether the user explicitly confirmed or edited structured dose details.';
