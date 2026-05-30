import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Required Supabase function secrets:
// APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY, APNS_ENVIRONMENT=sandbox|production.
// Keep the APNs .p8 private key only in Supabase secrets; never ship it in the iOS app.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type NotifyDoseEventRequest = {
  dose_event_id?: string;
  patient_id?: string;
  user_medication_id?: string;
  medication_id?: string;
  status?: string;
  occurred_at?: string;
  actor_user_id?: string;
  actor_device_id?: string;
  actor_push_token?: string;
  device_token?: string;
};

type CallerContext = {
  actorUserId: string | null;
  actorRole: "patient" | "caregiver" | "regular";
  patientId: string;
};

type APNsToken = {
  id: string;
  user_id: string;
  token: string;
  environment: string;
  device_id: string | null;
  language: string | null;
};

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const apnsKeyID = Deno.env.get("APNS_KEY_ID") ?? "";
const apnsTeamID = Deno.env.get("APNS_TEAM_ID") ?? "";
const apnsBundleID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const apnsPrivateKey = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const apnsEnvironment = (Deno.env.get("APNS_ENVIRONMENT") ?? "sandbox").toLowerCase();

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

  let body: NotifyDoseEventRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  try {
    const serviceClient = createClient(supabaseURL, serviceRoleKey);
    const authorization = req.headers.get("Authorization") ?? "";
    const authClient = createClient(supabaseURL, anonKey, {
      global: { headers: authorization ? { Authorization: authorization } : {} },
    });

    const doseEventId = requireString(body.dose_event_id, "dose_event_id");
    const requestedPatientId = requireString(body.patient_id, "patient_id");
    const context = await resolveCallerContext(serviceClient, authClient, body, requestedPatientId);
    const event = await loadDoseEvent(serviceClient, doseEventId);

    if (String(event.patient_id) !== requestedPatientId || context.patientId !== requestedPatientId) {
      throw new FunctionError(403, "Dose event does not match the requested patient.");
    }

    const status = String(event.status ?? body.status ?? "");
    if (status !== "taken" && status !== "skipped" && status !== "missed") {
      return json({ caregivers_found: 0, tokens_found: 0, sent_count: 0, failed_count: 0 });
    }

    if (!apnsKeyID || !apnsTeamID || !apnsBundleID || !apnsPrivateKey) {
      throw new FunctionError(500, "APNs function secrets are not configured.");
    }

    const relations = await loadEligibleCaregivers(serviceClient, requestedPatientId);
    const caregiverIds = relations.map((relation) => String(relation.caregiver_id));
    if (caregiverIds.length === 0) {
      return json({ caregivers_found: 0, tokens_found: 0, sent_count: 0, failed_count: 0 });
    }

    const tokenRows = await loadPushTokens(serviceClient, caregiverIds, normalizedAPNsEnvironment());
    const senderToken = body.actor_push_token ? String(body.actor_push_token) : null;
    const senderDeviceId = body.actor_device_id ? String(body.actor_device_id) : null;
    const tokens = tokenRows.filter((token) => {
      if (senderToken && token.token === senderToken) return false;
      if (senderDeviceId && token.device_id === senderDeviceId) return false;
      if (context.actorUserId && token.user_id === context.actorUserId) return false;
      return true;
    });

    if (tokens.length === 0) {
      return json({ caregivers_found: caregiverIds.length, tokens_found: 0, sent_count: 0, failed_count: 0 });
    }

    const patientName = await loadPatientName(serviceClient, requestedPatientId);
    const medication = await loadMedicationInfo(serviceClient, String(event.user_medication_id ?? body.user_medication_id ?? ""));
    const jwt = await createAPNsJWT();

    let sentCount = 0;
    let failedCount = 0;

    for (const token of tokens) {
      const copy = notificationCopy(patientName, medication, status, token.language === "ar" ? "ar" : "en");
      const result = await sendAPNs(token, jwt, copy, {
        dose_event_id: doseEventId,
        patient_id: requestedPatientId,
        user_medication_id: String(event.user_medication_id ?? body.user_medication_id ?? ""),
        status,
        type: "caregiver_dose_event",
      });

      if (result.ok) {
        sentCount += 1;
      } else {
        failedCount += 1;
        if (result.permanent) {
          await deactivatePushToken(serviceClient, token.id);
        }
      }
    }

    return json({
      caregivers_found: caregiverIds.length,
      tokens_found: tokens.length,
      sent_count: sentCount,
      failed_count: failedCount,
    });
  } catch (error) {
    const status = error instanceof FunctionError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Request failed.";
    console.error("notify-caregiver-dose-event failure", { status, message });
    return json({ error: message }, status);
  }
});

async function resolveCallerContext(
  serviceClient: ReturnType<typeof createClient>,
  authClient: ReturnType<typeof createClient>,
  body: NotifyDoseEventRequest,
  patientId: string,
): Promise<CallerContext> {
  if (body.device_token) {
    const { data: session, error } = await serviceClient
      .from("device_sessions")
      .select("id,user_id")
      .eq("device_token", String(body.device_token))
      .maybeSingle();

    if (error) throw new FunctionError(500, "Could not validate device session.");
    if (!session?.user_id || String(session.user_id) !== patientId) {
      throw new FunctionError(401, "Patient session is invalid or expired.");
    }

    const { data: revokedDevice, error: deviceError } = await serviceClient
      .from("patient_devices")
      .select("id")
      .eq("device_session_id", session.id)
      .not("revoked_at", "is", null)
      .maybeSingle();

    if (deviceError && deviceError.code !== "42P01" && deviceError.code !== "42703") {
      throw new FunctionError(500, "Could not validate device status.");
    }
    if (revokedDevice) throw new FunctionError(401, "Patient session has been revoked.");

    return { actorUserId: String(session.user_id), actorRole: "patient", patientId };
  }

  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user?.id) {
    throw new FunctionError(401, "Authentication required.");
  }

  const actorUserId = userData.user.id;
  if (actorUserId === patientId) {
    return { actorUserId, actorRole: "patient", patientId };
  }

  const { data: relation, error } = await serviceClient
    .from("caregiver_relations")
    .select("caregiver_id,patient_id,status")
    .eq("caregiver_id", actorUserId)
    .eq("patient_id", patientId)
    .eq("status", "active")
    .maybeSingle();

  if (error) throw new FunctionError(500, "Could not validate caregiver relationship.");
  if (!relation) throw new FunctionError(403, "You do not have access to this patient.");

  return { actorUserId, actorRole: "caregiver", patientId };
}

async function loadDoseEvent(serviceClient: ReturnType<typeof createClient>, id: string) {
  const { data, error } = await serviceClient
    .from("medication_dose_events")
    .select("id,patient_id,user_medication_id,status,recorded_by,scheduled_for,created_at")
    .eq("id", id)
    .maybeSingle();

  if (error) throw new FunctionError(500, "Could not load dose event.");
  if (!data) throw new FunctionError(404, "Dose event was not found.");
  return data;
}

async function loadEligibleCaregivers(serviceClient: ReturnType<typeof createClient>, patientId: string) {
  const { data, error } = await serviceClient
    .from("caregiver_relations")
    .select("caregiver_id")
    .eq("patient_id", patientId)
    .eq("status", "active")
    .eq("notify_patient_meds", true);

  if (error) throw new FunctionError(500, "Could not load caregiver notification permissions.");
  return data ?? [];
}

async function loadPushTokens(serviceClient: ReturnType<typeof createClient>, caregiverIds: string[], environment: string): Promise<APNsToken[]> {
  const { data, error } = await serviceClient
    .from("user_push_tokens")
    .select("id,user_id,token,environment,device_id,language")
    .in("user_id", caregiverIds)
    .eq("platform", "ios")
    .eq("environment", environment)
    .eq("is_active", true);

  if (error) throw new FunctionError(500, "Could not load caregiver push tokens.");
  return data ?? [];
}

async function loadPatientName(serviceClient: ReturnType<typeof createClient>, patientId: string) {
  const { data, error } = await serviceClient
    .from("users")
    .select("first_name,last_name")
    .eq("id", patientId)
    .maybeSingle();

  if (error) return "Family member";
  const name = [data?.first_name, data?.last_name].filter(Boolean).join(" ").trim();
  return name || "Family member";
}

async function loadMedicationInfo(serviceClient: ReturnType<typeof createClient>, userMedicationId: string) {
  if (!userMedicationId) return { name: null, dose: null };
  const { data, error } = await serviceClient
    .from("user_medications")
    .select("name,medication_name,dosage,dose_display,dose_quantity,dose_quantity_unit,dose_unit,dose_amount,dose_amount_unit,strength_value,strength_unit,medications(name)")
    .eq("id", userMedicationId)
    .maybeSingle();

  if (error || !data) return { name: null, dose: null };
  const catalog = Array.isArray(data.medications) ? data.medications[0] : data.medications;
  const name = String(data.medication_name ?? data.name ?? catalog?.name ?? "").trim() || null;
  const dose = [
    data.dose_display,
    formatAmount(data.dose_quantity, data.dose_quantity_unit ?? data.dose_unit),
    formatAmount(data.dose_amount, data.dose_amount_unit),
    data.dosage,
    formatAmount(data.strength_value, data.strength_unit),
  ].map((value) => String(value ?? "").trim()).find((value) => value.length > 0) ?? null;
  return { name, dose };
}

function notificationCopy(
  patientName: string,
  medication: { name: string | null; dose: string | null },
  status: string,
  language: "en" | "ar",
) {
  const medicationName = medication.name ?? (language === "ar" ? "الدواء" : "a medication");
  const doseText = medication.dose ? (language === "ar" ? ` الجرعة: ${medication.dose}.` : ` Dose: ${medication.dose}.`) : "";

  if (language === "ar") {
    switch (status) {
    case "taken":
      return { title: "تم أخذ الدواء", body: `${patientName} سجل ${medicationName} كـ تم أخذه.${doseText}` };
    case "skipped":
      return { title: "تم تخطي الدواء", body: `${patientName} تخطى ${medicationName}. يمكن تحتاج تتطمن على الحالة.` };
    case "missed":
      return { title: "جرعة فائتة", body: `ممكن ${patientName} ما أخذ ${medicationName}. يفضل تتطمن على الحالة.` };
    default:
      return { title: "تحديث الدواء", body: `${patientName} حدث حالة ${medicationName}.` };
    }
  }

  switch (status) {
  case "taken":
    return { title: "Medication Taken", body: `${patientName} marked ${medicationName} as taken.${doseText}` };
  case "skipped":
    return { title: "Medication Skipped", body: `${patientName} skipped ${medicationName}. You may want to check in.` };
  case "missed":
    return { title: "Missed Medication", body: `${patientName} may have missed ${medicationName}. Please check in.` };
  default:
    return { title: "Medication update", body: `${patientName} updated a medication dose.` };
  }
}

function formatAmount(value: unknown, unit: unknown) {
  const number = Number(value);
  const normalizedUnit = String(unit ?? "").trim();
  if (!Number.isFinite(number) || number <= 0 || !normalizedUnit) return null;
  return `${number} ${normalizedUnit}`;
}

async function sendAPNs(
  token: APNsToken,
  jwt: string,
  copy: { title: string; body: string },
  data: Record<string, string>,
) {
  const host = normalizedAPNsEnvironment() === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const response = await fetch(`https://${host}/3/device/${token.token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": apnsBundleID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: copy,
        sound: "default",
        "thread-id": "caregiver-medication-updates",
      },
      ...data,
    }),
  });

  if (response.ok) return { ok: true, permanent: false };

  const responseText = await response.text();
  const reason = redactedAPNsReason(responseText);
  const permanent = response.status === 410
    || reason === "BadDeviceToken"
    || reason === "DeviceTokenNotForTopic"
    || reason === "Unregistered";
  console.error("APNs send failed", {
    token_id: token.id,
    status: response.status,
    permanent,
    reason,
  });
  return { ok: false, permanent };
}

async function deactivatePushToken(serviceClient: ReturnType<typeof createClient>, tokenId: string) {
  const { error } = await serviceClient
    .from("user_push_tokens")
    .update({ is_active: false })
    .eq("id", tokenId);

  if (error) {
    console.error("Could not deactivate APNs token", { token_id: tokenId, message: error.message });
  }
}

async function createAPNsJWT() {
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: apnsKeyID }));
  const claims = base64URL(JSON.stringify({ iss: apnsTeamID, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const key = await importAPNsPrivateKey(apnsPrivateKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64URL(new Uint8Array(signature))}`;
}

async function importAPNsPrivateKey(pem: string) {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    binary.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function normalizedAPNsEnvironment() {
  return apnsEnvironment === "production" ? "production" : "sandbox";
}

function base64URL(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function redactedAPNsReason(value: string) {
  try {
    const parsed = JSON.parse(value);
    return parsed.reason ?? "unknown";
  } catch {
    return "unknown";
  }
}

function requireString(value: unknown, name: string) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new FunctionError(400, `${name} is required.`);
  }
  return value.trim();
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

class FunctionError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
