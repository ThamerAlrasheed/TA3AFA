import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  careCodeFingerprint,
  generateCanonicalCareCode,
} from "../_shared/care-code.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!supabaseURL || !anonKey || !serviceRoleKey) {
    return json({ error: "Supabase function environment is not configured." }, 500);
  }

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "Unauthorized" }, 401);

    const authClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const serviceClient = createClient(supabaseURL, serviceRoleKey);

    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData.user?.id) return json({ error: "Authentication required" }, 401);

    const body = await req.json();
    const patientId = String(body.patient_id ?? "").trim();
    if (!patientId) return json({ error: "patient_id is required" }, 400);

    const caregiverId = userData.user.id;
    const { data: relation, error: relationError } = await serviceClient
      .from("caregiver_relations")
      .select("id,status")
      .eq("caregiver_id", caregiverId)
      .eq("patient_id", patientId)
      .in("status", ["active", "pending", "accepted", "linked"])
      .maybeSingle();

    if (relationError) return json({ error: "Could not validate caregiver relation" }, 500);
    if (!relation) return json({ error: "You do not have access to this family member" }, 403);

    await serviceClient
      .from("care_codes")
      .update({ status: "expired" })
      .eq("caregiver_id", caregiverId)
      .eq("patient_id", patientId)
      .eq("status", "active");

    const code = await uniqueCode(serviceClient);
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();

    const { error: codeError } = await serviceClient
      .from("care_codes")
      .insert({
        code,
        patient_id: patientId,
        caregiver_id: caregiverId,
        status: "active",
        expires_at: expiresAt,
      });

    if (codeError) return json({ error: "Failed to generate care code" }, 500);

    if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) {
      console.error("Generated invalid code:", { length: String(code).length, isString: typeof code === "string" });
      return json({ error: "Backend generated invalid care code format." }, 500);
    }

    return json({ 
      patient_id: patientId, 
      code: code, 
      care_code: code, 
      generatedCode: code, 
      expires_at: expiresAt 
    }, 200);
  } catch {
    return json({ error: "Internal server error" }, 500);
  }
});

async function uniqueCode(serviceClient: ReturnType<typeof createClient>) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = generateCanonicalCareCode();

    const { data } = await serviceClient
      .from("care_codes")
      .select("id")
      .eq("code", code)
      .limit(1);

    if (!data || data.length === 0) {
      console.log("generate-care-code generated care code", {
        canonicalLength: code.length,
        canonicalFingerprint: await careCodeFingerprint(code),
      });
      return code;
    }
  }

  throw new Error("Could not generate unique code");
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
