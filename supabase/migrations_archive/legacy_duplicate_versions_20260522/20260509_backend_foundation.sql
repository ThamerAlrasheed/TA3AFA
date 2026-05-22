-- 20260509_backend_foundation.sql
-- Additive backend foundation tables for audit, patient device tracking,
-- structured patient medical context, drug caches, and durable dose history.

begin;

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid references public.users(id) on delete cascade,
  actor_user_id uuid references public.users(id) on delete set null,
  actor_role text not null default 'system'
    check (actor_role in ('regular', 'caregiver', 'patient', 'system', 'service')),
  action text not null,
  entity_table text not null,
  entity_id uuid,
  request_id text,
  ip_address inet,
  user_agent text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.patient_devices (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  device_session_id uuid references public.device_sessions(id) on delete set null,
  device_token_hash text not null,
  platform text not null default 'unknown'
    check (platform in ('ios', 'android', 'web', 'unknown')),
  device_name text,
  push_token text,
  app_version text,
  os_version text,
  locale text,
  timezone text,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.interaction_rules (
  id uuid primary key default gen_random_uuid(),
  primary_drug_key text not null,
  interacting_drug_key text not null,
  severity text not null default 'unknown'
    check (severity in ('contraindicated', 'major', 'moderate', 'minor', 'unknown')),
  evidence_level text,
  mechanism text,
  clinical_effect text,
  management text,
  source_name text,
  source_url text,
  source_updated_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (primary_drug_key <> interacting_drug_key)
);

create table if not exists public.patient_allergies (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  severity text check (severity in ('mild', 'moderate', 'severe', 'unknown')),
  reaction text,
  notes text,
  source text not null default 'user'
    check (source in ('user', 'caregiver', 'clinician', 'import', 'system')),
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(name)) > 0)
);

create table if not exists public.patient_conditions (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'resolved', 'unknown')),
  diagnosed_at date,
  notes text,
  source text not null default 'user'
    check (source in ('user', 'caregiver', 'clinician', 'import', 'system')),
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(name)) > 0)
);

create table if not exists public.drug_source_cache (
  id uuid primary key default gen_random_uuid(),
  cache_scope text not null default 'public'
    check (cache_scope = 'public'),
  source text not null,
  query_type text not null,
  query_key text not null,
  locale text not null default 'en',
  response jsonb not null,
  source_updated_at timestamptz,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(source)) > 0),
  check (length(btrim(query_type)) > 0),
  check (length(btrim(query_key)) > 0)
);

create table if not exists public.drug_ai_summary_cache (
  id uuid primary key default gen_random_uuid(),
  cache_scope text not null default 'public'
    check (cache_scope = 'public'),
  drug_key text not null,
  locale text not null default 'en',
  model text not null,
  prompt_version text not null,
  summary jsonb not null,
  safety_notes text[] not null default '{}'::text[],
  source_cache_ids uuid[] not null default '{}'::uuid[],
  generated_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(drug_key)) > 0),
  check (length(btrim(model)) > 0),
  check (length(btrim(prompt_version)) > 0)
);

create table if not exists public.medication_schedules (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  user_medication_id uuid references public.user_medications(id) on delete cascade,
  medication_id uuid references public.medications(id) on delete set null,
  title text,
  dose_amount numeric,
  dose_unit text,
  instructions text,
  schedule_kind text not null default 'daily'
    check (schedule_kind in ('daily', 'interval', 'weekly', 'custom')),
  frequency_per_day integer check (frequency_per_day is null or frequency_per_day > 0),
  interval_hours integer check (interval_hours is null or interval_hours > 0),
  dose_times time without time zone[] not null default '{}'::time without time zone[],
  days_of_week smallint[] not null default '{}'::smallint[],
  start_date date not null default current_date,
  end_date date,
  timezone text not null default 'UTC',
  food_rule public.food_rule_enum not null default 'none'::public.food_rule_enum,
  reminder_enabled boolean not null default true,
  is_active boolean not null default true,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date),
  check (
    days_of_week = '{}'::smallint[]
    or days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  )
);

create table if not exists public.medication_dose_events (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.users(id) on delete cascade,
  schedule_id uuid references public.medication_schedules(id) on delete cascade,
  user_medication_id uuid references public.user_medications(id) on delete set null,
  scheduled_for timestamptz not null,
  timezone text not null default 'UTC',
  status public.dose_status_enum not null default 'pending'::public.dose_status_enum,
  dose_amount numeric,
  dose_unit text,
  taken_at timestamptz,
  recorded_by uuid references public.users(id) on delete set null,
  source text not null default 'system'
    check (source in ('system', 'patient', 'caregiver', 'device', 'import')),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.audit_logs is
  'Service-role audit trail. Authenticated clients must not insert audit rows or provide actor_role, action, before_data, after_data, IP, user agent, or metadata.';
comment on table public.drug_source_cache is
  'Public drug source cache only. This table must never store patient-specific data, patient identifiers, allergies, conditions, or personalized recommendations.';
comment on table public.drug_ai_summary_cache is
  'Public drug AI summary cache only. This table must never store patient-specific data, patient identifiers, allergies, conditions, or personalized recommendations.';
comment on column public.drug_source_cache.cache_scope is
  'Only public cache rows are allowed in this phase; patient-specific cache scopes are intentionally rejected.';
comment on column public.drug_ai_summary_cache.cache_scope is
  'Only public cache rows are allowed in this phase; patient-specific cache scopes are intentionally rejected.';

create index if not exists audit_logs_patient_created_at_idx
  on public.audit_logs (patient_id, created_at desc);
create index if not exists audit_logs_actor_created_at_idx
  on public.audit_logs (actor_user_id, created_at desc);
create index if not exists audit_logs_entity_idx
  on public.audit_logs (entity_table, entity_id);
create index if not exists audit_logs_action_created_at_idx
  on public.audit_logs (action, created_at desc);

create unique index if not exists patient_devices_device_token_hash_key
  on public.patient_devices (device_token_hash);
create index if not exists patient_devices_patient_id_idx
  on public.patient_devices (patient_id);
create index if not exists patient_devices_active_patient_idx
  on public.patient_devices (patient_id, last_seen_at desc)
  where revoked_at is null;
create index if not exists patient_devices_device_session_id_idx
  on public.patient_devices (device_session_id);

create unique index if not exists interaction_rules_active_pair_source_key
  on public.interaction_rules (
    least(primary_drug_key, interacting_drug_key),
    greatest(primary_drug_key, interacting_drug_key),
    coalesce(source_name, '')
  )
  where is_active;
create index if not exists interaction_rules_primary_drug_key_idx
  on public.interaction_rules (primary_drug_key)
  where is_active;
create index if not exists interaction_rules_interacting_drug_key_idx
  on public.interaction_rules (interacting_drug_key)
  where is_active;
create index if not exists interaction_rules_severity_idx
  on public.interaction_rules (severity)
  where is_active;

create unique index if not exists patient_allergies_active_name_key
  on public.patient_allergies (patient_id, normalized_name)
  where is_active;
create index if not exists patient_allergies_patient_id_idx
  on public.patient_allergies (patient_id);

create unique index if not exists patient_conditions_active_name_key
  on public.patient_conditions (patient_id, normalized_name)
  where is_active;
create index if not exists patient_conditions_patient_id_idx
  on public.patient_conditions (patient_id);
create index if not exists patient_conditions_status_idx
  on public.patient_conditions (patient_id, status);

create unique index if not exists drug_source_cache_lookup_key
  on public.drug_source_cache (cache_scope, source, query_type, query_key, locale);
create index if not exists drug_source_cache_expires_at_idx
  on public.drug_source_cache (expires_at);
create index if not exists drug_source_cache_fetched_at_idx
  on public.drug_source_cache (fetched_at desc);

create unique index if not exists drug_ai_summary_cache_lookup_key
  on public.drug_ai_summary_cache (cache_scope, drug_key, locale, model, prompt_version);
create index if not exists drug_ai_summary_cache_expires_at_idx
  on public.drug_ai_summary_cache (expires_at);
create index if not exists drug_ai_summary_cache_generated_at_idx
  on public.drug_ai_summary_cache (generated_at desc);

create index if not exists medication_schedules_patient_active_idx
  on public.medication_schedules (patient_id, is_active, start_date);
create index if not exists medication_schedules_user_medication_id_idx
  on public.medication_schedules (user_medication_id);
create index if not exists medication_schedules_medication_id_idx
  on public.medication_schedules (medication_id);
create index if not exists medication_schedules_created_by_idx
  on public.medication_schedules (created_by);

create unique index if not exists medication_dose_events_schedule_time_key
  on public.medication_dose_events (schedule_id, scheduled_for)
  where schedule_id is not null;
create index if not exists medication_dose_events_patient_due_idx
  on public.medication_dose_events (patient_id, scheduled_for);
create index if not exists medication_dose_events_patient_status_due_idx
  on public.medication_dose_events (patient_id, status, scheduled_for);
create index if not exists medication_dose_events_user_medication_id_idx
  on public.medication_dose_events (user_medication_id);
create index if not exists medication_dose_events_recorded_by_idx
  on public.medication_dose_events (recorded_by);

create or replace function public.device_session_belongs_to_patient(
  p_device_session_id uuid,
  p_patient_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_device_session_id is null
    or exists (
      select 1
      from public.device_sessions ds
      where ds.id = p_device_session_id
        and ds.user_id = p_patient_id
    );
$$;

create or replace function public.user_medication_belongs_to_patient(
  p_user_medication_id uuid,
  p_patient_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_medication_id is null
    or exists (
      select 1
      from public.user_medications um
      where um.id = p_user_medication_id
        and um.user_id = p_patient_id
    );
$$;

create or replace function public.medication_schedule_belongs_to_patient(
  p_schedule_id uuid,
  p_patient_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_schedule_id is null
    or exists (
      select 1
      from public.medication_schedules ms
      where ms.id = p_schedule_id
        and ms.patient_id = p_patient_id
    );
$$;

create or replace function public.validate_patient_devices_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.device_session_belongs_to_patient(new.device_session_id, new.patient_id) then
    raise exception 'patient_devices.device_session_id must belong to the same patient_id'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists patient_devices_validate_integrity on public.patient_devices;
create trigger patient_devices_validate_integrity
  before insert or update of patient_id, device_session_id
  on public.patient_devices
  for each row
  execute function public.validate_patient_devices_integrity();

create or replace function public.validate_medication_schedules_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.user_medication_belongs_to_patient(new.user_medication_id, new.patient_id) then
    raise exception 'medication_schedules.user_medication_id must belong to the same patient_id'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists medication_schedules_validate_integrity on public.medication_schedules;
create trigger medication_schedules_validate_integrity
  before insert or update of patient_id, user_medication_id
  on public.medication_schedules
  for each row
  execute function public.validate_medication_schedules_integrity();

create or replace function public.validate_medication_dose_events_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.medication_schedule_belongs_to_patient(new.schedule_id, new.patient_id) then
    raise exception 'medication_dose_events.schedule_id must belong to the same patient_id'
      using errcode = '23514';
  end if;

  if not public.user_medication_belongs_to_patient(new.user_medication_id, new.patient_id) then
    raise exception 'medication_dose_events.user_medication_id must belong to the same patient_id'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists medication_dose_events_validate_integrity on public.medication_dose_events;
create trigger medication_dose_events_validate_integrity
  before insert or update of patient_id, schedule_id, user_medication_id
  on public.medication_dose_events
  for each row
  execute function public.validate_medication_dose_events_integrity();

create or replace view public.patient_devices_caregiver_safe
with (security_barrier = true)
as
select
  pd.id,
  pd.patient_id,
  pd.platform,
  pd.device_name,
  pd.app_version,
  pd.os_version,
  pd.locale,
  pd.timezone,
  pd.last_seen_at,
  pd.revoked_at,
  pd.created_at,
  pd.updated_at
from public.patient_devices pd
where exists (
  select 1
  from public.caregiver_relations cr
  where cr.patient_id = pd.patient_id
    and cr.caregiver_id = auth.uid()
    and cr.status = 'active'
);

comment on view public.patient_devices_caregiver_safe is
  'Redacted caregiver-readable device view. It intentionally excludes push_token, device_token_hash, device_session_id, and metadata.';

revoke all on function public.device_session_belongs_to_patient(uuid, uuid) from public, anon, authenticated;
revoke all on function public.user_medication_belongs_to_patient(uuid, uuid) from public, anon, authenticated;
revoke all on function public.medication_schedule_belongs_to_patient(uuid, uuid) from public, anon, authenticated;
revoke all on function public.validate_patient_devices_integrity() from public, anon, authenticated;
revoke all on function public.validate_medication_schedules_integrity() from public, anon, authenticated;
revoke all on function public.validate_medication_dose_events_integrity() from public, anon, authenticated;

grant execute on function public.device_session_belongs_to_patient(uuid, uuid) to service_role;
grant execute on function public.user_medication_belongs_to_patient(uuid, uuid) to service_role;
grant execute on function public.medication_schedule_belongs_to_patient(uuid, uuid) to service_role;
grant execute on function public.validate_patient_devices_integrity() to service_role;
grant execute on function public.validate_medication_schedules_integrity() to service_role;
grant execute on function public.validate_medication_dose_events_integrity() to service_role;

alter table public.audit_logs enable row level security;
alter table public.patient_devices enable row level security;
alter table public.interaction_rules enable row level security;
alter table public.patient_allergies enable row level security;
alter table public.patient_conditions enable row level security;
alter table public.drug_source_cache enable row level security;
alter table public.drug_ai_summary_cache enable row level security;
alter table public.medication_schedules enable row level security;
alter table public.medication_dose_events enable row level security;

revoke all on public.audit_logs from public, anon, authenticated;
revoke all on public.patient_devices from public, anon, authenticated;
revoke all on public.patient_devices_caregiver_safe from public, anon, authenticated;
revoke all on public.interaction_rules from public, anon, authenticated;
revoke all on public.patient_allergies from public, anon, authenticated;
revoke all on public.patient_conditions from public, anon, authenticated;
revoke all on public.drug_source_cache from public, anon, authenticated;
revoke all on public.drug_ai_summary_cache from public, anon, authenticated;
revoke all on public.medication_schedules from public, anon, authenticated;
revoke all on public.medication_dose_events from public, anon, authenticated;

grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;

grant select, insert, update, delete on public.patient_devices to authenticated;
grant all on public.patient_devices to service_role;
grant select on public.patient_devices_caregiver_safe to authenticated;
grant select on public.patient_devices_caregiver_safe to service_role;

grant select on public.interaction_rules to anon, authenticated;
grant all on public.interaction_rules to service_role;

grant select, insert, update on public.patient_allergies to authenticated;
grant all on public.patient_allergies to service_role;

grant select, insert, update on public.patient_conditions to authenticated;
grant all on public.patient_conditions to service_role;

grant select on public.drug_source_cache to anon, authenticated;
grant all on public.drug_source_cache to service_role;

grant select on public.drug_ai_summary_cache to authenticated;
grant all on public.drug_ai_summary_cache to service_role;

grant select, insert, update on public.medication_schedules to authenticated;
grant all on public.medication_schedules to service_role;

grant select, insert, update on public.medication_dose_events to authenticated;
grant all on public.medication_dose_events to service_role;

drop policy if exists "audit_logs_select_related" on public.audit_logs;
create policy "audit_logs_select_related"
  on public.audit_logs
  for select
  to authenticated
  using (
    actor_user_id = auth.uid()
    or patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = audit_logs.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "audit_logs_insert_actor" on public.audit_logs;

drop policy if exists "patient_devices_select_related" on public.patient_devices;
drop policy if exists "patient_devices_select_own" on public.patient_devices;
create policy "patient_devices_select_own"
  on public.patient_devices
  for select
  to authenticated
  using (patient_id = auth.uid());

drop policy if exists "patient_devices_insert_own" on public.patient_devices;
create policy "patient_devices_insert_own"
  on public.patient_devices
  for insert
  to authenticated
  with check (patient_id = auth.uid());

drop policy if exists "patient_devices_update_own" on public.patient_devices;
create policy "patient_devices_update_own"
  on public.patient_devices
  for update
  to authenticated
  using (patient_id = auth.uid())
  with check (patient_id = auth.uid());

drop policy if exists "patient_devices_delete_own" on public.patient_devices;
create policy "patient_devices_delete_own"
  on public.patient_devices
  for delete
  to authenticated
  using (patient_id = auth.uid());

drop policy if exists "interaction_rules_select_public" on public.interaction_rules;
create policy "interaction_rules_select_public"
  on public.interaction_rules
  for select
  to anon, authenticated
  using (is_active);

drop policy if exists "patient_allergies_select_related" on public.patient_allergies;
create policy "patient_allergies_select_related"
  on public.patient_allergies
  for select
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_allergies.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_allergies_insert_related" on public.patient_allergies;
create policy "patient_allergies_insert_related"
  on public.patient_allergies
  for insert
  to authenticated
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_allergies.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_allergies_update_related" on public.patient_allergies;
create policy "patient_allergies_update_related"
  on public.patient_allergies
  for update
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_allergies.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  )
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_allergies.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_allergies_delete_related" on public.patient_allergies;

drop policy if exists "patient_conditions_select_related" on public.patient_conditions;
create policy "patient_conditions_select_related"
  on public.patient_conditions
  for select
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_conditions.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_conditions_insert_related" on public.patient_conditions;
create policy "patient_conditions_insert_related"
  on public.patient_conditions
  for insert
  to authenticated
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_conditions.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_conditions_update_related" on public.patient_conditions;
create policy "patient_conditions_update_related"
  on public.patient_conditions
  for update
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_conditions.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  )
  with check (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = patient_conditions.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "patient_conditions_delete_related" on public.patient_conditions;

drop policy if exists "drug_source_cache_select_public" on public.drug_source_cache;
create policy "drug_source_cache_select_public"
  on public.drug_source_cache
  for select
  to anon, authenticated
  using (
    cache_scope = 'public'
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "drug_ai_summary_cache_select_public" on public.drug_ai_summary_cache;
create policy "drug_ai_summary_cache_select_public"
  on public.drug_ai_summary_cache
  for select
  to authenticated
  using (
    cache_scope = 'public'
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "medication_schedules_select_related" on public.medication_schedules;
create policy "medication_schedules_select_related"
  on public.medication_schedules
  for select
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_schedules.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  );

drop policy if exists "medication_schedules_insert_related" on public.medication_schedules;
create policy "medication_schedules_insert_related"
  on public.medication_schedules
  for insert
  to authenticated
  with check (
    (
      patient_id = auth.uid()
      or exists (
        select 1
        from public.caregiver_relations cr
        where cr.patient_id = medication_schedules.patient_id
          and cr.caregiver_id = auth.uid()
          and cr.status = 'active'
      )
    )
    and (
      user_medication_id is null
      or exists (
        select 1
        from public.user_medications um
        where um.id = medication_schedules.user_medication_id
          and um.user_id = medication_schedules.patient_id
      )
    )
  );

drop policy if exists "medication_schedules_update_related" on public.medication_schedules;
create policy "medication_schedules_update_related"
  on public.medication_schedules
  for update
  to authenticated
  using (
    patient_id = auth.uid()
    or exists (
      select 1
      from public.caregiver_relations cr
      where cr.patient_id = medication_schedules.patient_id
        and cr.caregiver_id = auth.uid()
        and cr.status = 'active'
    )
  )
  with check (
    (
      patient_id = auth.uid()
      or exists (
        select 1
        from public.caregiver_relations cr
        where cr.patient_id = medication_schedules.patient_id
          and cr.caregiver_id = auth.uid()
          and cr.status = 'active'
      )
    )
    and (
      user_medication_id is null
      or exists (
        select 1
        from public.user_medications um
        where um.id = medication_schedules.user_medication_id
          and um.user_id = medication_schedules.patient_id
      )
    )
  );

drop policy if exists "medication_schedules_delete_related" on public.medication_schedules;

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
    (
      patient_id = auth.uid()
      or exists (
        select 1
        from public.caregiver_relations cr
        where cr.patient_id = medication_dose_events.patient_id
          and cr.caregiver_id = auth.uid()
          and cr.status = 'active'
      )
    )
    and (
      schedule_id is null
      or exists (
        select 1
        from public.medication_schedules ms
        where ms.id = medication_dose_events.schedule_id
          and ms.patient_id = medication_dose_events.patient_id
      )
    )
    and (
      user_medication_id is null
      or exists (
        select 1
        from public.user_medications um
        where um.id = medication_dose_events.user_medication_id
          and um.user_id = medication_dose_events.patient_id
      )
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
    (
      patient_id = auth.uid()
      or exists (
        select 1
        from public.caregiver_relations cr
        where cr.patient_id = medication_dose_events.patient_id
          and cr.caregiver_id = auth.uid()
          and cr.status = 'active'
      )
    )
    and (
      schedule_id is null
      or exists (
        select 1
        from public.medication_schedules ms
        where ms.id = medication_dose_events.schedule_id
          and ms.patient_id = medication_dose_events.patient_id
      )
    )
    and (
      user_medication_id is null
      or exists (
        select 1
        from public.user_medications um
        where um.id = medication_dose_events.user_medication_id
          and um.user_id = medication_dose_events.patient_id
      )
    )
  );

drop policy if exists "medication_dose_events_delete_related" on public.medication_dose_events;

commit;
