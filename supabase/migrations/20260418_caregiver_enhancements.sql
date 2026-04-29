-- 20260418_caregiver_enhancements.sql
-- Enhances caregiver features and prepares for medication caching

begin;

-- 1. Update medications table for full caching
-- Adding columns that might be missing for DrugIntel structure
alter table if exists public.medications
  add column if not exists strengths text[],
  add column if not exists indications text[],
  add column if not exists interactions_to_avoid text[],
  add column if not exists common_side_effects text[],
  add column if not exists how_to_take text[],
  add column if not exists what_for text[];

-- 2. Update caregiver_relations table with granular settings
alter table if exists public.caregiver_relations
  add column if not exists can_patient_add_meds boolean not null default true,
  add column if not exists notify_patient_meds boolean not null default true,
  add column if not exists notify_patient_appointments boolean not null default true;

-- 3. Enhance RLS Policies to allow caregivers to manage patients
-- Appointments: Caregiver can manage if linked in caregiver_relations
drop policy if exists "appointments_select_caregiver" on public.appointments;
create policy "appointments_select_caregiver"
  on public.appointments
  for select
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "appointments_insert_caregiver" on public.appointments;
create policy "appointments_insert_caregiver"
  on public.appointments
  for insert
  to authenticated
  with check (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "appointments_update_caregiver" on public.appointments;
create policy "appointments_update_caregiver"
  on public.appointments
  for update
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  )
  with check (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "appointments_delete_caregiver" on public.appointments;
create policy "appointments_delete_caregiver"
  on public.appointments
  for delete
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

-- User Medications: Caregiver can manage if linked
drop policy if exists "user_medications_select_caregiver" on public.user_medications;
create policy "user_medications_select_caregiver"
  on public.user_medications
  for select
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "user_medications_insert_caregiver" on public.user_medications;
create policy "user_medications_insert_caregiver"
  on public.user_medications
  for insert
  to authenticated
  with check (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "user_medications_update_caregiver" on public.user_medications;
create policy "user_medications_update_caregiver"
  on public.user_medications
  for update
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  )
  with check (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "user_medications_delete_caregiver" on public.user_medications;
create policy "user_medications_delete_caregiver"
  on public.user_medications
  for delete
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

-- Search History: Caregiver can manage if linked
drop policy if exists "search_history_select_caregiver" on public.search_history;
create policy "search_history_select_caregiver"
  on public.search_history
  for select
  to authenticated
  using (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

drop policy if exists "search_history_insert_caregiver" on public.search_history;
create policy "search_history_insert_caregiver"
  on public.search_history
  for insert
  to authenticated
  with check (
    user_id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

-- User Profiles: Caregivers can view their patients' profiles
drop policy if exists "users_select_caregiver" on public.users;
create policy "users_select_caregiver"
  on public.users
  for select
  to authenticated
  using (
    id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

-- 4. Enable Patient "Add Meds" restriction enforcement (on DB level if desired, but primarily app-side)
-- We can add a CHECK constraint or handle it in RLS if we want strict enforcement.
-- For now, we'll enforce it via RLS on insert/update if the user is a patient.

commit;
