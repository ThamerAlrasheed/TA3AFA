import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, logAudit, hashCareCode, getPepper } from "../_shared/audit-helpers.ts";

type CreateFamilyMemberRequest = {
  first_name?: string;
  last_name?: string;
  date_of_birth?: string;
  allergies?: unknown;
  conditions?: unknown;
  can_patient_add_meds?: boolean;
  can_patient_manage_calendar?: boolean;
  notify_patient_meds?: boolean;
  notify_patient_appointments?: boolean;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error(
    "Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY environment variables."
  );
}

const admin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function normalizeName(value: string | undefined) {
  return (value ?? "").trim();
}

function sanitizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return [] as string[];

  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0);
}

function randomCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { error: "Use POST for create-family-member." });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { error: "Missing Authorization header." });
  }

  const caller = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) {
    return json(401, { error: "Invalid caregiver session." });
  }

  let payload: CreateFamilyMemberRequest;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body." });
  }

  const firstName = normalizeName(payload.first_name);
  const lastName = normalizeName(payload.last_name);
  const dateOfBirth = (payload.date_of_birth ?? "").trim();
  const allergies = sanitizeStringArray(payload.allergies);
  const conditions = sanitizeStringArray(payload.conditions);
  
  const canPatientAddMeds = payload.can_patient_add_meds ?? true;
  const canPatientManageCalendar = payload.can_patient_manage_calendar ?? true;
  const notifyPatientMeds = payload.notify_patient_meds ?? true;
  const notifyPatientAppointments = payload.notify_patient_appointments ?? true;

  if (!firstName || !lastName || !dateOfBirth) {
    return json(400, { error: "First name, last name, and date of birth are required." });
  }

  const caregiverId = authData.user.id;
  const patientId = crypto.randomUUID();
  const code = randomCode();
  
  // Hardening: Use peppered hash and short 10-minute expiry
  const pepper = getPepper();
  const codeHash = await hashCareCode(code, pepper);
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

  const { error: patientError } = await admin.from("users").insert({
    id: patientId,
    role: "patient",
    first_name: firstName,
    last_name: lastName,
    date_of_birth: dateOfBirth,
    allergies,
    conditions,
  });

  if (patientError) {
    return json(500, { error: `Failed to create patient profile: ${patientError.message}` });
  }

  const { error: relationError } = await admin.from("caregiver_relations").insert({
    caregiver_id: caregiverId,
    patient_id: patientId,
    status: "pending",
    can_patient_add_meds: canPatientAddMeds,
    can_patient_manage_calendar: canPatientManageCalendar,
    notify_patient_meds: notifyPatientMeds,
    notify_patient_appointments: notifyPatientAppointments,
  });

  if (relationError) {
    await admin.from("users").delete().eq("id", patientId);
    return json(500, { error: `Failed to create caregiver link: ${relationError.message}` });
  }

  const { data: codeRow, error: codeError } = await admin.from("care_codes").insert({
    code: null, // Wipe plain code for new entries
    code_hash: codeHash,
    patient_id: patientId,
    caregiver_id: caregiverId,
    status: "active",
    expires_at: expiresAt,
  }).select("id").single();

  if (codeError) {
    await admin.from("caregiver_relations").delete().eq("patient_id", patientId);
    await admin.from("users").delete().eq("id", patientId);
    return json(500, { error: `Failed to create care code: ${codeError.message}` });
  }

  // Audit Log
  await logAudit(admin, {
    patient_id: patientId,
    actor_user_id: caregiverId,
    actor_role: 'caregiver',
    action: 'care_code_created',
    entity_table: 'care_codes',
    entity_id: codeRow.id,
    metadata: { expires_at: expiresAt },
    req
  });

  await admin.from("users").update({ role: "caregiver" }).eq("id", caregiverId);

  return json(200, {
    patient_id: patientId,
    code,
    expires_at: expiresAt,
  });
});
