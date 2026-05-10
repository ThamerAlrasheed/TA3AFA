import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
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

    const { patient_id } = await req.json();
    if (!patient_id) return jsonResponse({ error: "Missing patient_id" }, 400);

    // Verify requesting user is an active caregiver for this patient
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

    // List devices using the safe view
    // The safe view already has a WHERE clause checking caregiver_relations, 
    // but we use the admin client here to bypass RLS if needed, or we can use the client.
    // However, the view doesn't have RLS, it has a WHERE clause based on the caller.
    // Wait, the view definition uses cr.caregiver_id = auth.uid().
    // So we MUST use the client to get the correct view results.
    
    const { data: devices, error: devError } = await client
      .from("patient_devices_caregiver_safe")
      .select("*")
      .eq("patient_id", patient_id)
      .is("revoked_at", null)
      .order("last_seen_at", { ascending: false });

    if (devError) throw devError;

    return jsonResponse({ devices: devices || [] });

  } catch (e) {
    console.error("list-patient-devices error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
