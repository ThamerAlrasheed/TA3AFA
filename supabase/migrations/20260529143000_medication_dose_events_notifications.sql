begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'dose_status_enum') then
    create type public.dose_status_enum as enum ('pending', 'taken', 'skipped', 'missed');
  end if;
end $$;

create table if not exists public.medication_dose_events (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  user_medication_id uuid references public.user_medications(id) on delete set null,
  scheduled_for timestamptz not null,
  status text not null default 'pending',
  taken_at timestamptz,
  recorded_by uuid references public.users(id) on delete set null,
  source text not null default 'system',
  device_session_id uuid references public.device_sessions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.medication_dose_events
  add column if not exists user_medication_id uuid references public.user_medications(id) on delete set null,
  add column if not exists scheduled_for timestamptz not null default now(),
  add column if not exists status text not null default 'pending',
  add column if not exists taken_at timestamptz,
  add column if not exists recorded_by uuid references public.users(id) on delete set null,
  add column if not exists source text not null default 'system',
  add column if not exists device_session_id uuid references public.device_sessions(id) on delete set null,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.medication_dose_events
  drop constraint if exists medication_dose_events_status_check,
  add constraint medication_dose_events_status_check
    check (status in ('pending', 'taken', 'skipped', 'missed'));

alter table public.medication_dose_events
  drop constraint if exists medication_dose_events_source_check,
  add constraint medication_dose_events_source_check
    check (source in ('system', 'patient', 'caregiver', 'device', 'import', 'today_button', 'calendar_button', 'notification_action', 'patient_device'));

-- Clean up duplicate records before creating unique index
delete from public.medication_dose_events a
using public.medication_dose_events b
where a.id < b.id
  and a.patient_id = b.patient_id
  and a.user_medication_id = b.user_medication_id
  and a.scheduled_for = b.scheduled_for;

create unique index if not exists medication_dose_events_patient_med_scheduled_key
  on public.medication_dose_events(patient_id, user_medication_id, scheduled_for);

create index if not exists medication_dose_events_patient_due_idx
  on public.medication_dose_events(patient_id, scheduled_for);

create index if not exists medication_dose_events_patient_status_due_idx
  on public.medication_dose_events(patient_id, status, scheduled_for);

create index if not exists medication_dose_events_user_medication_id_idx
  on public.medication_dose_events(user_medication_id);

alter table public.medication_dose_events enable row level security;

grant select, insert, update on public.medication_dose_events to authenticated;
grant all on public.medication_dose_events to service_role;

drop policy if exists "medication_dose_events_select_related" on public.medication_dose_events;
create policy "medication_dose_events_select_related"
  on public.medication_dose_events
  for select
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_dose_events.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "medication_dose_events_insert_related" on public.medication_dose_events;
create policy "medication_dose_events_insert_related"
  on public.medication_dose_events
  for insert
  to authenticated
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_dose_events.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "medication_dose_events_update_related" on public.medication_dose_events;
create policy "medication_dose_events_update_related"
  on public.medication_dose_events
  for update
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_dose_events.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  )
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_dose_events.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

notify pgrst, 'reload schema';

commit;
