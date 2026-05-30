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
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // 1. Authenticate Caregiver
    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
    });

    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData.user?.id) {
      return new Response(JSON.stringify({ error: "Authentication required" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Verified Caregiver ID - NEVER TRUST CLIENT INPUT FOR THIS
    const caregiverId = userData.user.id;
    const body = await req.json();

    const firstName = String(body.first_name || "").trim();
    const lastName = String(body.last_name || "").trim();
    const dateOfBirth = body.date_of_birth ? String(body.date_of_birth) : null;
    const allergies = Array.isArray(body.allergies) ? body.allergies.map(String) : [];
    const conditions = Array.isArray(body.conditions) ? body.conditions.map(String) : [];
    
    if (!firstName) {
      return new Response(JSON.stringify({ error: "First name is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const serviceClient = createClient(supabaseURL, serviceRoleKey);

    // 3. Create the patient user record
    const { data: newPatient, error: patientError } = await serviceClient
      .from("users")
      .insert({
        role: "patient",
        first_name: firstName,
        last_name: lastName.length > 0 ? lastName : null,
        date_of_birth: dateOfBirth,
        allergies: allergies,
        conditions: conditions,
      })
      .select("id")
      .single();

    if (patientError || !newPatient) {
      console.error("Failed to create patient record. DB Error:", patientError?.code);
      return new Response(JSON.stringify({ error: "Failed to create patient profile" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const patientId = newPatient.id;

    // 4. Create caregiver_relation
    const { error: relationError } = await serviceClient
      .from("caregiver_relations")
      .insert({
        caregiver_id: caregiverId,
        patient_id: patientId,
        status: "active",
        can_patient_add_meds: Boolean(body.can_patient_add_meds ?? true),
        can_patient_manage_calendar: Boolean(body.can_patient_manage_calendar ?? true),
        notify_patient_meds: Boolean(body.notify_patient_meds ?? true),
        notify_patient_appointments: Boolean(body.notify_patient_appointments ?? true),
      });

    if (relationError) {
      console.error("Failed to create caregiver relation. DB Error:", relationError?.code);
      return new Response(JSON.stringify({ error: "Failed to create caregiver relation" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 5. Generate the canonical 6-digit care code. Leading zeroes are preserved.
    const code = await uniqueCareCode(serviceClient);

    const expiresAtDate = new Date();
    expiresAtDate.setHours(expiresAtDate.getHours() + 72);
    const expiresAt = expiresAtDate.toISOString();

    const { error: codeError } = await serviceClient
      .from("care_codes")
      .insert({
        code: code,
        patient_id: patientId,
        caregiver_id: caregiverId,
        status: "active",
        expires_at: expiresAt,
      });

    if (codeError) {
      console.error("Failed to insert care code. DB Error:", codeError?.code);
      return new Response(JSON.stringify({ error: "Failed to generate care code" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 6. Return strictly what iOS expects
    if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) {
      console.error("Generated invalid code:", { length: String(code).length, isString: typeof code === "string" });
      return new Response(JSON.stringify({ error: "Backend generated invalid care code format." }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      patient_id: patientId,
      code: code,
      care_code: code,
      generatedCode: code,
      expires_at: expiresAt,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in create-family-member.");
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function uniqueCareCode(serviceClient: ReturnType<typeof createClient>) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = generateCanonicalCareCode();

    const { data } = await serviceClient
      .from("care_codes")
      .select("id")
      .eq("code", code)
      .limit(1);

    if (!data || data.length === 0) {
      console.log("create-family-member generated care code", {
        canonicalLength: code.length,
        canonicalFingerprint: await careCodeFingerprint(code),
      });
      return code;
    }
  }

  throw new Error("Could not generate unique care code");
}
