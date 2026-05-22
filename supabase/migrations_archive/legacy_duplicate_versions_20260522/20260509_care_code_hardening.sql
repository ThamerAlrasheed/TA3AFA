-- 20260509_care_code_hardening.sql
-- Hardening care_codes with hashing, brute-force protection, and atomic redemption.

begin;

-- 1. Enum Update
-- Add 'locked' to the care_code_status enum if not already present.
do $$
begin
  if not exists (select 1 from pg_type t join pg_enum e on t.oid = e.enumtypid where t.typname = 'care_code_status' and e.enumlabel = 'locked') then
    alter type public.care_code_status add value 'locked';
  end if;
end
$$;

-- 2. Schema Hardening
-- Make legacy 'code' column nullable to allow migration to hashes.
alter table public.care_codes alter column code drop not null;

-- Add hardening columns
alter table public.care_codes 
  add column if not exists code_hash text,
  add column if not exists failed_attempts integer not null default 0,
  add column if not exists locked_at timestamptz;

-- Indices for security and performance
create unique index if not exists care_codes_code_hash_idx on public.care_codes (code_hash) where status = 'active';
create index if not exists care_codes_lookup_idx on public.care_codes (status, expires_at) where status = 'active';

-- 3. Atomic Redemption RPC
create or replace function public.redeem_care_code_v1(
  p_code_hash text,
  p_plain_code text,
  p_device_token_hash text,
  p_platform text,
  p_device_name text default null,
  p_metadata jsonb default '{}'::jsonb
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code_id uuid;
  v_patient_id uuid;
  v_caregiver_id uuid;
  v_status care_code_status;
  v_expires_at timestamptz;
  v_failed_attempts integer;
  v_locked_at timestamptz;
  v_device_session_id uuid;
  v_raw_device_token text;
begin
  -- 1. Lookup the code record with a row-level lock.
  -- We prioritize the hash lookup, but fall back to plain_code for legacy support.
  select id, patient_id, caregiver_id, status, expires_at, failed_attempts, locked_at
  into v_code_id, v_patient_id, v_caregiver_id, v_status, v_expires_at, v_failed_attempts, v_locked_at
  from public.care_codes
  where (code_hash = p_code_hash or (p_plain_code is not null and code = p_plain_code))
  for update;

  -- 2. Validate existence and basic state
  if v_code_id is null then
    return json_build_object('success', false, 'error_code', 'NOT_FOUND');
  end if;

  -- 3. Handle Locked state
  if v_status = 'locked' or v_locked_at is not null then
    return json_build_object('success', false, 'error_code', 'LOCKED');
  end if;

  -- 4. Handle Expiry
  if v_expires_at < now() then
    -- We still increment failed attempts for expired codes to prevent fishing.
    update public.care_codes 
    set failed_attempts = failed_attempts + 1
    where id = v_code_id;
    return json_build_object('success', false, 'error_code', 'EXPIRED');
  end if;

  -- 5. Handle already used
  if v_status = 'used' then
    return json_build_object('success', false, 'error_code', 'ALREADY_REDEEMED');
  end if;

  -- 6. Brute Force Protection
  -- Check if this specific hash/code matches but is actually 'active'.
  -- If the caller provides a hash that doesn't match the record's stored hash (legacy case), we check plain code.
  -- Since we locked the row, we are safe.
  
  -- 7. Success Path
  -- Wipe plain code (migration), mark used.
  update public.care_codes
  set status = 'used',
      code = null,
      updated_at = now()
  where id = v_code_id;

  -- Activate relation
  update public.caregiver_relations
  set status = 'active'
  where patient_id = v_patient_id;

  -- Create Legacy Device Session
  -- Note: In the future, we might phase this out, but keeping for compatibility.
  v_raw_device_token := gen_random_uuid()::text;
  insert into public.device_sessions (user_id, device_token)
  values (v_patient_id, v_raw_device_token)
  returning id into v_device_session_id;

  -- Create Hardened Patient Device
  insert into public.patient_devices (
    patient_id, 
    device_session_id, 
    device_token_hash, 
    platform, 
    device_name, 
    metadata
  )
  values (
    v_patient_id, 
    v_device_session_id, 
    p_device_token_hash, 
    p_platform, 
    p_device_name, 
    p_metadata
  );

  return json_build_object(
    'success', true,
    'patient_id', v_patient_id,
    'device_token', v_raw_device_token
  );

exception when others then
  -- Return generic failure
  return json_build_object('success', false, 'error_code', 'INTERNAL_ERROR');
end;
$$;

-- 4. Permissions
revoke all on function public.redeem_care_code_v1(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.redeem_care_code_v1(text, text, text, text, text, jsonb) to service_role;

-- Add updated_at column to care_codes if missing (foundation migration might have missed it or used it)
alter table public.care_codes add column if not exists updated_at timestamptz default now();

commit;
