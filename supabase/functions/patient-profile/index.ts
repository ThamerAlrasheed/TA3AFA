import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";
import { logAudit } from "../_shared/audit-helpers.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

interface Allergy {
  id: string;
  name: string;
  severity: string;
  reaction?: string;
  notes?: string;
  is_active: boolean;
}

interface Condition {
  id: string;
  name: string;
  status: string;
  diagnosed_at?: string;
  notes?: string;
  is_active: boolean;
}

interface PatientRoutine {
  breakfast_time?: string;
  lunch_time?: string;
  dinner_time?: string;
  bedtime?: string;
  wakeup_time?: string;
}

interface ProfileRequest {
  action: "list_allergies" | "save_allergy" | "deactivate_allergy" | "list_conditions" | "save_condition" | "deactivate_condition" | "get_routine" | "update_routine";
  patient_id?: string;
  device_token?: string;
  allergy?: Allergy;
  condition?: Condition;
  id?: string;
  routine?: PatientRoutine;
}

type PatientContext = {
  patientId: string;
  actorId: string;
  actorRole: "patient" | "caregiver";
};

async function patientIdForDeviceToken(deviceToken: string) {
  const { data, error } = await admin
    .from("device_sessions")
    .select(`
      user_id,
      patient_devices!device_session_id(revoked_at)
    `)
    .eq("device_token", deviceToken)
    .limit(1)
    .maybeSingle();

  if (error || !data) return undefined;
  
  const devices = data.patient_devices as any[];
  if (devices && devices.some(d => d.revoked_at !== null)) return undefined;

  return data.user_id as string | undefined;
}

async function patientContextForDeviceToken(deviceToken: string): Promise<PatientContext | undefined> {
  const patientId = await patientIdForDeviceToken(deviceToken);
  if (!patientId) return undefined;
  return { patientId, actorId: patientId, actorRole: "patient" };
}

async function patientContextForAuthorizedUser(req: Request, targetPatientId: string): Promise<PatientContext | undefined> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return undefined;

  const client = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error } = await client.auth.getUser();
  if (error || !user) return undefined;

  if (user.id === targetPatientId) {
    return { patientId: targetPatientId, actorId: user.id, actorRole: "patient" };
  }

  const { data: relation } = await admin
    .from("caregiver_relations")
    .select("patient_id")
    .eq("caregiver_id", user.id)
    .eq("patient_id", targetPatientId)
    .eq("status", "active")
    .maybeSingle();

  const patientId = relation?.patient_id as string | undefined;
  if (!patientId) return undefined;
  return { patientId, actorId: user.id, actorRole: "caregiver" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const payload: ProfileRequest = await req.json();
    const { action, patient_id: targetPid, device_token } = payload;

    if (device_token && targetPid) {
      return jsonResponse({ error: "Provide either device_token or patient_id, not both" }, 400);
    }

    const context = device_token
      ? await patientContextForDeviceToken(device_token)
      : (targetPid ? await patientContextForAuthorizedUser(req, targetPid) : undefined);

    if (!context) return jsonResponse({ error: "Unauthorized" }, 401);

    const { patientId, actorId, actorRole } = context;

    if (action === "list_allergies") {
      const { data } = await admin.from("patient_allergies").select("*").eq("patient_id", patientId).eq("is_active", true);
      return jsonResponse({ allergies: data || [] });
    }

    if (action === "save_allergy") {
      const { allergy } = payload;
      if (!allergy) return jsonResponse({ error: "Missing allergy data" }, 400);
      
      const isNew = !allergy.id || allergy.id.length < 10; // Simple check
      const row = {
        ...allergy,
        id: allergy.id || crypto.randomUUID(),
        patient_id: patientId,
        created_by: actorId,
        updated_at: new Date().toISOString()
      };

      const { error } = await admin.from("patient_allergies").upsert(row);
      if (error) throw error;

      await logAudit(admin, {
        patient_id: patientId,
        actor_user_id: actorId,
        actor_role: actorRole,
        action: isNew ? "allergy_added" as any : "allergy_updated" as any,
        entity_table: "patient_allergies",
        entity_id: row.id,
        metadata: { name: allergy.name },
        req
      });
      return jsonResponse({ success: true });
    }

    if (action === "deactivate_allergy") {
      if (!payload.id) return jsonResponse({ error: "Missing id" }, 400);
      const { error } = await admin.from("patient_allergies").update({ is_active: false, updated_at: new Date().toISOString() }).eq("id", payload.id).eq("patient_id", patientId);
      if (error) throw error;

      await logAudit(admin, {
        patient_id: patientId,
        actor_user_id: actorId,
        actor_role: actorRole,
        action: "allergy_deactivated" as any,
        entity_table: "patient_allergies",
        entity_id: payload.id,
        req
      });
      return jsonResponse({ success: true });
    }

    if (action === "list_conditions") {
      const { data } = await admin.from("patient_conditions").select("*").eq("patient_id", patientId).eq("is_active", true);
      return jsonResponse({ conditions: data || [] });
    }

    if (action === "save_condition") {
      const { condition } = payload;
      if (!condition) return jsonResponse({ error: "Missing condition data" }, 400);
      
      const isNew = !condition.id || condition.id.length < 10;
      const row = {
        ...condition,
        id: condition.id || crypto.randomUUID(),
        patient_id: patientId,
        created_by: actorId,
        updated_at: new Date().toISOString()
      };

      const { error } = await admin.from("patient_conditions").upsert(row);
      if (error) throw error;

      await logAudit(admin, {
        patient_id: patientId,
        actor_user_id: actorId,
        actor_role: actorRole,
        action: isNew ? "condition_added" as any : "condition_updated" as any,
        entity_table: "patient_conditions",
        entity_id: row.id,
        metadata: { name: condition.name },
        req
      });
      return jsonResponse({ success: true });
    }

    if (action === "deactivate_condition") {
      if (!payload.id) return jsonResponse({ error: "Missing id" }, 400);
      // For conditions we set status = 'inactive' AND is_active = false for thoroughness
      const { error } = await admin.from("patient_conditions").update({ status: 'inactive', is_active: false, updated_at: new Date().toISOString() }).eq("id", payload.id).eq("patient_id", patientId);
      if (error) throw error;

      await logAudit(admin, {
        patient_id: patientId,
        actor_user_id: actorId,
        actor_role: actorRole,
        action: "condition_deactivated" as any,
        entity_table: "patient_conditions",
        entity_id: payload.id,
        req
      });
      return jsonResponse({ success: true });
    }

    if (action === "get_routine") {
      const { data, error } = await admin
        .from("users")
        .select("breakfast_time, lunch_time, dinner_time, bedtime, wakeup_time")
        .eq("id", patientId)
        .maybeSingle();
      if (error) throw error;
      return jsonResponse({ routine: data || {} });
    }

    if (action === "update_routine") {
      const { routine } = payload;
      if (!routine) return jsonResponse({ error: "Missing routine data" }, 400);
      const fields: Record<string, string | null> = {};
      if (routine.breakfast_time !== undefined) fields.breakfast_time = routine.breakfast_time;
      if (routine.lunch_time !== undefined) fields.lunch_time = routine.lunch_time;
      if (routine.dinner_time !== undefined) fields.dinner_time = routine.dinner_time;
      if (routine.bedtime !== undefined) fields.bedtime = routine.bedtime;
      if (routine.wakeup_time !== undefined) fields.wakeup_time = routine.wakeup_time;
      if (Object.keys(fields).length === 0) return jsonResponse({ success: true });
      const { error } = await admin.from("users").update(fields).eq("id", patientId);
      if (error) throw error;
      await logAudit(admin, {
        patient_id: patientId,
        actor_user_id: actorId,
        actor_role: actorRole,
        action: "routine_updated" as any,
        entity_table: "users",
        entity_id: patientId,
        metadata: fields,
        req
      });
      return jsonResponse({ success: true });
    }

    return jsonResponse({
      error: "invalid_action",
      message: `Unsupported patient-profile action: ${action ?? "missing"}`,
      expected: [
        "list_allergies",
        "save_allergy",
        "deactivate_allergy",
        "list_conditions",
        "save_condition",
        "deactivate_condition",
        "get_routine",
        "update_routine",
      ],
    }, 400);

  } catch (e) {
    console.error("patient-profile error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
