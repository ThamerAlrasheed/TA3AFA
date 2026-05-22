create extension if not exists pg_trgm;

alter table public.medications
  add column if not exists barcode_values text[] default '{}'::text[],
  add column if not exists brand_aliases text[] default '{}'::text[],
  add column if not exists generic_aliases text[] default '{}'::text[],
  add column if not exists normalized_brand_name text,
  add column if not exists normalized_generic_name text,
  add column if not exists normalized_strength text,
  add column if not exists dosage_form_normalized text,
  add column if not exists manufacturer_normalized text;

create index if not exists idx_medications_normalized_brand_name
  on public.medications using gin (normalized_brand_name gin_trgm_ops);

create index if not exists idx_medications_normalized_generic_name
  on public.medications using gin (normalized_generic_name gin_trgm_ops);

create index if not exists idx_medications_barcode_values
  on public.medications using gin (barcode_values);

create index if not exists idx_medications_brand_aliases
  on public.medications using gin (brand_aliases);

create index if not exists idx_medications_generic_aliases
  on public.medications using gin (generic_aliases);

alter table public.user_medications
  add column if not exists scan_source text,
  add column if not exists scan_confidence numeric,
  add column if not exists scan_confirmed_by_user boolean default false,
  add column if not exists scan_extracted_fields jsonb,
  add column if not exists scan_candidate_snapshot jsonb;

comment on column public.user_medications.scan_extracted_fields is
  'Structured scan fields extracted from OCR/local classification. Raw image is not stored.';

create table if not exists public.medication_scan_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  patient_id uuid,
  created_at timestamptz not null default now(),
  scan_source text not null,
  extraction_method text,
  top_match_score numeric,
  fallback_used boolean default false,
  fallback_reason text,
  selected_medication_id uuid,
  confirmed_by_user boolean default false,
  image_stored boolean default false,
  extracted_fields jsonb,
  candidate_snapshot jsonb
);

create index if not exists idx_medication_scan_sessions_user_id
  on public.medication_scan_sessions(user_id);

create index if not exists idx_medication_scan_sessions_patient_id
  on public.medication_scan_sessions(patient_id);

create index if not exists idx_medication_scan_sessions_created_at
  on public.medication_scan_sessions(created_at);

alter table public.medication_scan_sessions enable row level security;

drop policy if exists "medication_scan_sessions_select_own"
  on public.medication_scan_sessions;
create policy "medication_scan_sessions_select_own"
  on public.medication_scan_sessions
  for select
  to authenticated
  using (user_id = auth.uid() or patient_id = auth.uid());

drop policy if exists "medication_scan_sessions_insert_own"
  on public.medication_scan_sessions;
create policy "medication_scan_sessions_insert_own"
  on public.medication_scan_sessions
  for insert
  to authenticated
  with check (user_id = auth.uid() or patient_id = auth.uid());

drop policy if exists "medication_scan_sessions_service_role_all"
  on public.medication_scan_sessions;
create policy "medication_scan_sessions_service_role_all"
  on public.medication_scan_sessions
  for all
  to service_role
  using (true)
  with check (true);

comment on table public.medication_scan_sessions is
  'Non-image metadata about medication scan attempts and user confirmation.';

notify pgrst, 'reload schema';
