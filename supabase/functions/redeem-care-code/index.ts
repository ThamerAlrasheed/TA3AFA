import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";
import { corsHeaders, logAudit, hashCareCode, getPepper } from "../_shared/audit-helpers.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error(
    "Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY environment variables."
  );
}

const admin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const genericError = "Invalid or expired code. Please contact your caregiver.";

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  let payload: { code?: string; platform?: string; device_name?: string };
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }

  const code = (payload.code ?? "").trim();
  if (code.length !== 6 || !/^\d{6}$/.test(code)) {
    return jsonResponse({ error: "Enter a valid 6-digit code." }, 400);
  }

  const platform = payload.platform || "unknown";
  const deviceName = payload.device_name || null;

  // 1. Hardening: Peppered Hash
  const pepper = getPepper();
  const inputHash = await hashCareCode(code, pepper);

  // 2. Atomic Redemption via RPC
  // We generate the raw token here and pass its hash to the RPC
  const rawDeviceToken = crypto.randomUUID();
  const deviceTokenHash = await hashCareCode(rawDeviceToken, pepper);

  const { data, error: rpcError } = await admin.rpc("redeem_care_code_v1", {
    p_code_hash: inputHash,
    p_plain_code: code, // Fallback for legacy plain-text codes
    p_raw_device_token: rawDeviceToken,
    p_device_token_hash: deviceTokenHash,
    p_platform: platform,
    p_device_name: deviceName,
    p_metadata: { user_agent: request.headers.get("user-agent") }
  });

  if (rpcError || !data || !data.success) {
    // Log failure but return generic error to client
    const errorCode = data?.error_code || "RPC_ERROR";
    
    // Log only a fingerprint of the hash to audit logs
    const hashFingerprint = inputHash.substring(0, 8);

    await logAudit(admin, {
      action: "care_code_failed",
      actor_role: "service",
      entity_table: "care_codes",
      metadata: { 
        error_code: errorCode, 
        input_hash_fpt: hashFingerprint,
        platform
      },
      req: request
    });

    if (errorCode === "LOCKED") {
      await logAudit(admin, {
        action: "care_code_locked",
        actor_role: "system",
        entity_table: "care_codes",
        metadata: { input_hash_fpt: hashFingerprint },
        req: request
      });
    }

    return jsonResponse({ error: genericError }, 400);
  }

  // 3. Audit Success
  await logAudit(admin, {
    patient_id: data.patient_id,
    action: "care_code_redeemed",
    actor_role: "patient",
    entity_table: "care_codes",
    metadata: { platform },
    req: request
  });

  await logAudit(admin, {
    patient_id: data.patient_id,
    action: "patient_device_linked",
    actor_role: "patient",
    entity_table: "patient_devices",
    metadata: { platform, device_name: deviceName },
    req: request
  });

  return jsonResponse(
    {
      patient_id: data.patient_id,
      device_token: data.device_token,
    },
    200
  );
});

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
