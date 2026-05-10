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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing Authorization header" }, 401);

    const client = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Invalid user session" }, 401);

    const { patient_id, patient_device_id } = await req.json();
    if (!patient_id || !patient_device_id) {
      return jsonResponse({ error: "Missing patient_id or patient_device_id" }, 400);
    }

    // 1. Verify requesting user is an active caregiver for this patient
    const { data: relation, error: relError } = await admin
      .from("caregiver_relations")
      .select("status")
      .eq("caregiver_id", user.id)
      .eq("patient_id", patient_id)
      .eq("status", "active")
      .maybeSingle();

    if (relError || !relation) {
      return jsonResponse({ error: "Unauthorized. Must be an active caregiver." }, 403);
    }

    // 2. Perform Revocation
    // We use admin client to ensure we can update the row
    const { data: device, error: devError } = await admin
      .from("patient_devices")
      .update({ revoked_at: new Date().toISOString() })
      .eq("id", patient_device_id)
      .eq("patient_id", patient_id)
      .select("device_name, platform")
      .single();

    if (devError) throw devError;

    // 3. Log Audit Event
    await logAudit(admin, {
      patient_id,
      actor_user_id: user.id,
      actor_role: 'caregiver',
      action: "patient_device_revoked",
      entity_table: "patient_devices",
      entity_id: patient_device_id,
      metadata: { 
        device_name: device?.device_name,
        platform: device?.platform
      },
      req
    });

    return jsonResponse({ success: true });

  } catch (e) {
    console.error("revoke-patient-device error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
