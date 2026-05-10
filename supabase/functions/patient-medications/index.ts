import { createClient } from "npm:@supabase/supabase-js@2";

type MedicationPayload = {
  id?: string;
  name?: string;
  dosage?: string;
  frequency_per_day?: number;
  frequency_hours?: number | null;
  dosage_times?: string[];
  is_prn?: boolean;
  is_manual_schedule?: boolean;
  start_date?: string;
  end_date?: string;
  notes?: string | null;
  food_rule?: string | null;
  rxcui?: string | null;
  ingredients?: string[];
  active_ingredients?: string[];
};

type AppointmentPayload = {
  id?: string;
  title?: string;
  doctor_name?: string;
  appointment_time?: string;
  notes?: string | null;
};

type PatientMedicationRequest = {
  action?:
    | "list"
    | "save"
    | "delete_medication"
    | "archive_medication"
    | "restore_medication"
    | "list_appointments"
    | "save_appointment"
    | "delete_appointment";
  device_token?: string;
  target_patient_id?: string;
  medication?: MedicationPayload;
  appointment?: AppointmentPayload;
  id?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error("Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY environment variables.");
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

function cleanText(value: string | undefined | null) {
  return (value ?? "").trim();
}

function cleanDate(value: string | undefined) {
  const trimmed = cleanText(value);
  return /^\d{4}-\d{2}-\d{2}$/.test(trimmed) ? trimmed : null;
}

function normalizeFoodRule(value: string | undefined | null) {
  const normalized = cleanText(value).toLowerCase().replaceAll("_", "");
  switch (normalized) {
    case "beforefood": return "beforeFood";
    case "afterfood": return "afterFood";
    case "withfood": return "withFood";
    default: return "none";
  }
}

function cleanList(value: string[] | undefined | null) {
  return (value ?? [])
    .map((item) => cleanText(item))
    .filter((item, index, arr) => item.length > 0 && arr.indexOf(item) === index);
}

async function patientIdForDeviceToken(deviceToken: string) {
  // Check if session exists and is NOT revoked.
  // We use a join but we must be careful: if no patient_devices row exists (legacy), 
  // we still allow it for now.
  const { data, error } = await admin
    .from("device_sessions")
    .select(`
      user_id,
      patient_devices!device_session_id(revoked_at)
    `)
    .eq("device_token", deviceToken)
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("Auth check failed:", error);
    return undefined;
  }
  
  if (!data) return undefined;

  // If a device record exists and it has a revoked_at date, deny access.
  // Note: if multiple devices shared a session (unlikely but possible), 
  // we check if ANY are revoked? Actually device_session_id is 1:1 or 1:N.
  // The query returns an array for the joined table.
  const devices = data.patient_devices as any[];
  if (devices && devices.some(d => d.revoked_at !== null)) {
    console.warn(`Device revoked for session: ${deviceToken}`);
    return undefined;
  }

  return data.user_id as string | undefined;
}

async function patientIdForCaregiver(req: Request, targetPatientId: string) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return undefined;

  const caller = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) return undefined;

  if (authData.user.id === targetPatientId) {
    return targetPatientId;
  }

  const { data, error } = await admin
    .from("caregiver_relations")
    .select("patient_id")
    .eq("caregiver_id", authData.user.id)
    .eq("patient_id", targetPatientId)
    .limit(1);

  if (error) throw new Error(error.message);
  return data?.[0]?.patient_id as string | undefined;
}

async function permissionsForPatient(patientId: string) {
  const { data, error } = await admin
    .from("caregiver_relations")
    .select("can_patient_add_meds, can_patient_manage_calendar, notify_patient_meds, notify_patient_appointments")
    .eq("patient_id", patientId)
    .eq("status", "active")
    .limit(1);

  if (error) throw new Error(error.message);

  return data?.[0] ?? {
    can_patient_add_meds: true,
    can_patient_manage_calendar: true,
    notify_patient_meds: true,
    notify_patient_appointments: true,
  };
}

async function listMedications(patientId: string) {
  const { data, error } = await admin
    .from("user_medications")
    .select("*, medications(name, food_rule, rxcui, active_ingredients)")
    .eq("user_id", patientId)
    .eq("is_active", true)
    .order("start_date", { ascending: true });

  if (error) throw new Error(error.message);
  return data ?? [];
}

async function listAppointments(patientId: string) {
  const { data, error } = await admin
    .from("appointments")
    .select()
    .eq("user_id", patientId)
    .order("appointment_time", { ascending: true });

  if (error) throw new Error(error.message);
  return data ?? [];
}

async function medicationIdForName(name: string, foodRule: string, rxcui?: string | null, activeIngredients: string[] = []) {
  if (rxcui) {
    const { data: byRxCui, error: rxLookupError } = await admin
      .from("medications")
      .select("id")
      .eq("rxcui", rxcui)
      .limit(1);

    if (rxLookupError) throw new Error(rxLookupError.message);
    if (byRxCui?.[0]?.id) {
      const update: Record<string, unknown> = { name, food_rule: foodRule };
      if (activeIngredients.length > 0) update.active_ingredients = activeIngredients;
      await admin
        .from("medications")
        .update(update)
        .eq("id", byRxCui[0].id);
      return byRxCui[0].id as string;
    }
  }

  const { data: existing, error: lookupError } = await admin
    .from("medications")
    .select("id")
    .ilike("name", name)
    .limit(1);

  if (lookupError) throw new Error(lookupError.message);
  if (existing?.[0]?.id) {
    const update: Record<string, unknown> = { food_rule: foodRule };
    if (rxcui) update.rxcui = rxcui;
    if (activeIngredients.length > 0) update.active_ingredients = activeIngredients;
    await admin.from("medications").update(update).eq("id", existing[0].id);
    return existing[0].id as string;
  }

  const { data: inserted, error: insertError } = await admin
    .from("medications")
    .insert({
      name,
      food_rule: foodRule || "none",
      rxcui: rxcui ?? null,
      active_ingredients: activeIngredients,
    })
    .select("id")
    .limit(1);

  if (insertError) throw new Error(insertError.message);
  return inserted?.[0]?.id as string | undefined;
}

async function saveMedication(patientId: string, medication: MedicationPayload) {
  const name = cleanText(medication.name);
  const dosage = cleanText(medication.dosage);
  const startDate = cleanDate(medication.start_date);
  const endDate = cleanDate(medication.end_date);
  const frequencyPerDay = Math.max(1, Math.min(6, Math.trunc(medication.frequency_per_day ?? 1)));
  const foodRule = normalizeFoodRule(medication.food_rule);
  const activeIngredients = cleanList(medication.active_ingredients ?? medication.ingredients);

  if (!name || !dosage || !startDate || !endDate) {
    return json(400, { error: "Medication name, dosage, start date, and end date are required." });
  }

  const medicationId = await medicationIdForName(name, foodRule, cleanText(medication.rxcui) || null, activeIngredients);
  if (!medicationId) {
    return json(500, { error: `Medication '${name}' could not be found or created in the catalog.` });
  }

  const row = {
    id: cleanText(medication.id) || crypto.randomUUID(),
    user_id: patientId,
    medication_id: medicationId,
    dosage,
    frequency_per_day: frequencyPerDay,
    frequency_hours: medication.frequency_hours ?? null,
    food_rule: foodRule,
    dosage_times: medication.dosage_times ?? [],
    is_prn: medication.is_prn ?? false,
    is_manual_schedule: medication.is_manual_schedule ?? false,
    start_date: startDate,
    end_date: endDate,
    notes: cleanText(medication.notes) || null,
    is_active: true,
  };

  const { error } = await admin.from("user_medications").upsert(row);
  if (error) throw new Error(error.message);

  return json(200, { ok: true });
}

async function setMedicationActive(patientId: string, id: string, isActive: boolean) {
  const medicationId = cleanText(id);
  if (!medicationId) {
    return json(400, { error: "Medication id is required." });
  }

  const { error } = await admin
    .from("user_medications")
    .update({ is_active: isActive })
    .eq("id", medicationId)
    .eq("user_id", patientId);

  if (error) throw new Error(error.message);

  return json(200, { ok: true });
}

async function deleteMedication(patientId: string, id: string) {
  const medicationId = cleanText(id);
  if (!medicationId) {
    return json(400, { error: "Medication id is required." });
  }

  const { error } = await admin
    .from("user_medications")
    .delete()
    .eq("id", medicationId)
    .eq("user_id", patientId);

  if (error) throw new Error(error.message);

  return json(200, { ok: true });
}

async function saveAppointment(patientId: string, appointment: AppointmentPayload) {
  const title = cleanText(appointment.title);
  const doctorName = cleanText(appointment.doctor_name) || "doctor";
  const appointmentTime = cleanText(appointment.appointment_time);

  if (!title || !appointmentTime) {
    return json(400, { error: "Appointment title and time are required." });
  }

  const row = {
    id: cleanText(appointment.id) || crypto.randomUUID(),
    user_id: patientId,
    title,
    doctor_name: doctorName,
    appointment_time: appointmentTime,
    notes: cleanText(appointment.notes) || null,
  };

  const { error } = await admin.from("appointments").upsert(row);
  if (error) throw new Error(error.message);

  return json(200, { ok: true });
}

async function deleteAppointment(patientId: string, id: string) {
  const appointmentId = cleanText(id);
  if (!appointmentId) {
    return json(400, { error: "Appointment id is required." });
  }

  const { error } = await admin
    .from("appointments")
    .delete()
    .eq("id", appointmentId)
    .eq("user_id", patientId);

  if (error) throw new Error(error.message);

  return json(200, { ok: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { error: "Use POST for patient-medications." });
  }

  let payload: PatientMedicationRequest;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body." });
  }

  try {
    const deviceToken = cleanText(payload.device_token);
    const targetPatientId = cleanText(payload.target_patient_id);
    const patientId = deviceToken
      ? await patientIdForDeviceToken(deviceToken)
      : await patientIdForCaregiver(req, targetPatientId);

    if (!patientId) {
      return json(401, { error: "Patient session expired or caregiver access was not found." });
    }

    if (payload.action === "save") {
      const permissions = await permissionsForPatient(patientId);
      if (permissions.can_patient_add_meds === false) {
        return json(403, { error: "Your caregiver has disabled adding medications." });
      }

      return await saveMedication(patientId, payload.medication ?? {});
    }

    if (payload.action === "delete_medication") {
      const permissions = await permissionsForPatient(patientId);
      if (permissions.can_patient_add_meds === false) {
        return json(403, { error: "Your caregiver has disabled adding medications." });
      }

      return await deleteMedication(patientId, payload.id ?? "");
    }

    if (payload.action === "archive_medication" || payload.action === "restore_medication") {
      const permissions = await permissionsForPatient(patientId);
      if (permissions.can_patient_add_meds === false) {
        return json(403, { error: "Your caregiver has disabled adding medications." });
      }

      return await setMedicationActive(patientId, payload.id ?? "", payload.action === "restore_medication");
    }

    if (payload.action === "list_appointments") {
      const [appointments, permissions] = await Promise.all([
        listAppointments(patientId),
        permissionsForPatient(patientId),
      ]);

      return json(200, { appointments, permissions });
    }

    if (payload.action === "save_appointment") {
      const permissions = await permissionsForPatient(patientId);
      if (permissions.can_patient_manage_calendar === false) {
        return json(403, { error: "Your caregiver has disabled managing appointments." });
      }

      return await saveAppointment(patientId, payload.appointment ?? {});
    }

    if (payload.action === "delete_appointment") {
      const permissions = await permissionsForPatient(patientId);
      if (permissions.can_patient_manage_calendar === false) {
        return json(403, { error: "Your caregiver has disabled managing appointments." });
      }

      return await deleteAppointment(patientId, payload.id ?? "");
    }

    const [medications, permissions] = await Promise.all([
      listMedications(patientId),
      permissionsForPatient(patientId),
    ]);

    return json(200, { medications, permissions });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Patient medication request failed.";
    return json(500, { error: message });
  }
});
