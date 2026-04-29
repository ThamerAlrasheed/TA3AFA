import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";
import { corsHeaders } from "../_shared/drug-utils.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  // Auth check
  const authHeader = req.headers.get("Authorization")!;
  const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });
  }

  try {
    const { patientId, newCaregiverEmail } = await req.json();

    if (!patientId || !newCaregiverEmail) {
      return new Response(JSON.stringify({ error: "Missing patientId or newCaregiverEmail" }), { status: 400, headers: corsHeaders });
    }

    // 1. Verify caller is current caregiver
    const { data: relation, error: relationError } = await supabase
      .from("caregiver_relations")
      .select("*")
      .eq("patient_id", patientId)
      .eq("caregiver_id", user.id)
      .single();

    if (relationError || !relation) {
      return new Response(JSON.stringify({ error: "Unauthorized: You are not the caregiver for this patient" }), { status: 403, headers: corsHeaders });
    }

    // 2. Lookup new caregiver by email (we need their ID)
    // Note: This requires the new caregiver to be registered and their email to be public/searchable or we use admin API
    const { data: newCaregiver, error: lookupError } = await supabase
      .from("users")
      .select("id")
      .eq("email", newCaregiverEmail)
      .single();

    if (lookupError || !newCaregiver) {
      return new Response(JSON.stringify({ error: "New caregiver not found. Make sure they have registered." }), { status: 404, headers: corsHeaders });
    }

    // 3. Update the relation
    const { error: updateError } = await supabase
      .from("caregiver_relations")
      .update({ caregiver_id: newCaregiver.id })
      .eq("patient_id", patientId);

    if (updateError) {
      throw updateError;
    }

    return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: corsHeaders });
  }
});
