-- 20260509_care_code_hardening_v2.sql
-- Add explicit lock-after-5-attempts logic and improve RPC.

begin;

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
  select id, patient_id, caregiver_id, status, expires_at, failed_attempts, locked_at
  into v_code_id, v_patient_id, v_caregiver_id, v_status, v_expires_at, v_failed_attempts, v_locked_at
  from public.care_codes
  where (code_hash = p_code_hash or (p_plain_code is not null and code = p_plain_code))
  for update;

  -- 2. Validate existence
  if v_code_id is null then
    return json_build_object('success', false, 'error_code', 'NOT_FOUND');
  end if;

  -- 3. Handle Locked state
  if v_status = 'locked' or v_locked_at is not null then
    return json_build_object('success', false, 'error_code', 'LOCKED');
  end if;

  -- 4. Increment failure if not already locked or used
  -- We do this for ANY mismatch, expiry, or reuse attempt.
  -- But wait, if it MATCHES the hash/code, we then check other conditions.
  
  -- Handle Expiry
  if v_expires_at < now() then
    update public.care_codes 
    set failed_attempts = failed_attempts + 1,
        status = case when failed_attempts + 1 >= 5 then 'locked'::care_code_status else status end,
        locked_at = case when failed_attempts + 1 >= 5 then now() else locked_at end
    where id = v_code_id;
    return json_build_object('success', false, 'error_code', 'EXPIRED');
  end if;

  -- Handle already used
  if v_status = 'used' then
    update public.care_codes 
    set failed_attempts = failed_attempts + 1,
        status = case when failed_attempts + 1 >= 5 then 'locked'::care_code_status else status end,
        locked_at = case when failed_attempts + 1 >= 5 then now() else locked_at end
    where id = v_code_id;
    return json_build_object('success', false, 'error_code', 'ALREADY_REDEEMED');
  end if;

  -- 5. Final check: if we are here, it's a match and it's active and not expired.
  -- However, we must ensure the caller actually provided the RIGHT hash.
  -- The WHERE clause already ensured that.
  
  -- 6. Success Path
  update public.care_codes
  set status = 'used',
      code = null,
      updated_at = now()
  where id = v_code_id;

  update public.caregiver_relations
  set status = 'active'
  where patient_id = v_patient_id;

  v_raw_device_token := gen_random_uuid()::text;
  insert into public.device_sessions (user_id, device_token)
  values (v_patient_id, v_raw_device_token)
  returning id into v_device_session_id;

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
  return json_build_object('success', false, 'error_code', 'INTERNAL_ERROR');
end;
$$;

commit;
