-- Keep RLS enabled
alter table public.appointments enable row level security;

-- Remove unsafe legacy anon appointment policies
drop policy if exists allow_anon_appointments on public.appointments;
drop policy if exists anon_delete_appointments on public.appointments;
drop policy if exists anon_insert_appointments on public.appointments;
drop policy if exists anon_select_appointments on public.appointments;
drop policy if exists anon_update_appointments on public.appointments;
drop policy if exists appointments_delete_caregiver on public.appointments;
drop policy if exists appointments_delete_own on public.appointments;
drop policy if exists appointments_insert_caregiver on public.appointments;
drop policy if exists appointments_insert_own on public.appointments;
drop policy if exists appointments_select_caregiver on public.appointments;
drop policy if exists appointments_select_own on public.appointments;
drop policy if exists appointments_update_caregiver on public.appointments;
drop policy if exists appointments_update_own on public.appointments;
drop policy if exists "Users can delete own appointments" on public.appointments;
drop policy if exists "Users can insert own appointments" on public.appointments;
drop policy if exists "Users can read own appointments" on public.appointments;
drop policy if exists "Users can update own appointments" on public.appointments;

-- Add fields needed by the new Today/Calendar board if they do not exist
alter table public.appointments
add column if not exists is_completed boolean not null default false;

alter table public.appointments
add column if not exists appointment_type text not null default 'doctor';

alter table public.appointments
add column if not exists location text;

-- Helpful indexes
create index if not exists appointments_user_id_idx
on public.appointments(user_id);

create index if not exists appointments_user_time_idx
on public.appointments(user_id, appointment_time);

-- Authenticated users can read only their own appointments
create policy "Users can read own appointments"
on public.appointments
for select
to authenticated
using (
  user_id = auth.uid()
);

-- Authenticated users can insert only their own appointments
create policy "Users can insert own appointments"
on public.appointments
for insert
to authenticated
with check (
  user_id = auth.uid()
);

-- Authenticated users can update only their own appointments
create policy "Users can update own appointments"
on public.appointments
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
);

-- Authenticated users can delete only their own appointments
create policy "Users can delete own appointments"
on public.appointments
for delete
to authenticated
using (
  user_id = auth.uid()
);
