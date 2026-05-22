-- 20260505_fix_caregiver_rls.sql
-- Fixes RLS policies to allow caregivers to see their patients and manage them

begin;

-- 1. Enable RLS on caregiver_relations and care_codes if not already
alter table if exists public.caregiver_relations enable row level security;
alter table if exists public.care_codes enable row level security;

-- 2. Caregiver Relations Policies
drop policy if exists "caregiver_select_own" on public.caregiver_relations;
create policy "caregiver_select_own"
  on public.caregiver_relations
  for select
  to authenticated
  using (caregiver_id = auth.uid());

drop policy if exists "caregiver_update_own" on public.caregiver_relations;
create policy "caregiver_update_own"
  on public.caregiver_relations
  for update
  to authenticated
  using (caregiver_id = auth.uid())
  with check (caregiver_id = auth.uid());

-- Also allow the patient (if authenticated) to see their relations
drop policy if exists "patient_select_own" on public.caregiver_relations;
create policy "patient_select_own"
  on public.caregiver_relations
  for select
  to authenticated
  using (patient_id = auth.uid());

-- 3. Care Codes Policies
drop policy if exists "care_codes_select_caregiver" on public.care_codes;
create policy "care_codes_select_caregiver"
  on public.care_codes
  for select
  to authenticated
  using (caregiver_id = auth.uid());

-- 4. Allow caregivers to update their patients' profiles (routine, names, etc.)
drop policy if exists "users_update_caregiver" on public.users;
create policy "users_update_caregiver"
  on public.users
  for update
  to authenticated
  using (
    id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  )
  with check (
    id in (
      select patient_id from public.caregiver_relations where caregiver_id = auth.uid()
    )
  );

-- 5. Ensure caregivers can see their patients' profiles (already should exist, but for completeness)
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

-- 6. Search History Policies (Caregiver)
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

commit;
