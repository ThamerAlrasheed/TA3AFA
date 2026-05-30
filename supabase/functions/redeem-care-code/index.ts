import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  careCodeFingerprint,
  normalizeCareCode,
} from "../_shared/care-code.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
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
    const body = await req.json();
    const rawCode = String(body.code ?? "");
    const rawLength = rawCode.length;
    const code = normalizeCareCode(rawCode);
    const canonicalFingerprint = await careCodeFingerprint(code);
    
    if (code.length !== 6) {
      return new Response(JSON.stringify({ error: "Enter the 6-digit family code." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const serviceClient = createClient(supabaseURL, serviceRoleKey);
    const nowISO = new Date().toISOString();

    const { updatedCode, updateError, matchedLookupIndex } = await redeemFirstMatchingCode(
      serviceClient,
      [code],
      nowISO,
    );

    console.log("redeem-care-code lookup", {
      rawLength,
      canonicalLength: code.length,
      canonicalFingerprint,
      foundActiveCode: Boolean(updatedCode),
      usedLegacyLookup: false,
    });

    // If updateError or no data, it means it doesn't exist, is expired, or is already used.
    // We intentionally return a generic error to prevent leaking code existence.
    if (updateError || !updatedCode) {
      return new Response(JSON.stringify({ error: "Invalid, expired, or already used care code." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const patientId = updatedCode.patient_id;

    // Generate device session token
    const deviceToken = crypto.randomUUID();

    // Create device session
    const { error: sessionError } = await serviceClient
      .from("device_sessions")
      .insert({
        user_id: patientId,
        device_token: deviceToken,
      });

    if (sessionError) {
      console.error("Failed to create device session. DB Error:", sessionError?.code);
      return new Response(JSON.stringify({ error: "Failed to initialize device session" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Return strictly what iOS expects
    return new Response(JSON.stringify({
      patient_id: patientId,
      device_token: deviceToken,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in redeem-care-code.");
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function redeemFirstMatchingCode(
  serviceClient: ReturnType<typeof createClient>,
  lookupCodes: string[],
  nowISO: string,
) {
  let updateError: unknown = null;

  for (let index = 0; index < lookupCodes.length; index += 1) {
    const candidate = lookupCodes[index];
    const { data, error } = await serviceClient
      .from("care_codes")
      .update({ status: "used" })
      .eq("code", candidate)
      .eq("status", "active")
      .gt("expires_at", nowISO)
      .select("id, patient_id")
      .maybeSingle();

    if (error) {
      updateError = error;
      console.error("redeem-care-code lookup update error", {
        lookupIndex: index,
        errorCode: error.code,
      });
      continue;
    }

    if (data) {
      return { updatedCode: data, updateError: null, matchedLookupIndex: index };
    }
  }

  return { updatedCode: null, updateError, matchedLookupIndex: -1 };
}
