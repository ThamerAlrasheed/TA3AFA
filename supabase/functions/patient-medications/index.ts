import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type PatientMedicationRequest = {
  action?: string;
  device_token?: string;
  target_patient_id?: string;
  medication?: Record<string, unknown>;
  appointment?: Record<string, unknown>;
  id?: string;
};

type PatientContext = {
  patientId: string;
  actorUserId: string | null;
  actorRole: "regular" | "caregiver" | "patient";
  relation: Record<string, unknown> | null;
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

  let body: PatientMedicationRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = String(body.action ?? "");
  const authorization = req.headers.get("Authorization") ?? "";
  const authClient = createClient(supabaseURL, anonKey, {
    global: { headers: authorization ? { Authorization: authorization } : {} },
  });
  const serviceClient = createClient(supabaseURL, serviceRoleKey);

  try {
    const context = await resolvePatientContext(serviceClient, authClient, body);

    switch (action) {
      case "list":
        return json({
          medications: await listMedications(serviceClient, context.patientId),
          permissions: permissionsFor(context),
        });
      case "save":
        await assertMedicationPermission(context);
        return json({
          medication: await saveMedication(serviceClient, context, body.medication),
          permissions: permissionsFor(context),
        });
      case "delete_medication":
        await assertMedicationPermission(context);
        await deleteMedication(serviceClient, context.patientId, requireID(body.id));
        return json({ ok: true });
      case "archive_medication":
      case "restore_medication":
        await assertMedicationPermission(context);
        await setMedicationActive(serviceClient, context.patientId, requireID(body.id), action === "restore_medication");
        return json({ ok: true });
      case "list_appointments":
        await assertCalendarPermission(context);
        return json({
          appointments: await listAppointments(serviceClient, context.patientId),
          permissions: permissionsFor(context),
        });
      case "create_appointment":
      case "save_appointment":
      case "update_appointment":
        await assertCalendarPermission(context);
        return json({
          appointment: await saveAppointment(serviceClient, context, body.appointment, action),
          appointments: await listAppointments(serviceClient, context.patientId),
          permissions: permissionsFor(context),
        });
      case "delete_appointment":
        await assertCalendarPermission(context);
        await deleteAppointment(serviceClient, context.patientId, requireID(body.id));
        return json({ ok: true });
      default:
        return json({ error: "Unsupported action." }, 400);
    }
  } catch (error) {
    const status = error instanceof FunctionError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Request failed.";
    console.error("patient-medications failure", { action, status, message });
    return json({ error: message }, status);
  }
});

async function resolvePatientContext(serviceClient: ReturnType<typeof createClient>, authClient: ReturnType<typeof createClient>, body: PatientMedicationRequest): Promise<PatientContext> {
  if (body.device_token) {
    const token = String(body.device_token);
    const { data: session, error } = await serviceClient
      .from("device_sessions")
      .select("id,user_id")
      .eq("device_token", token)
      .maybeSingle();

    if (error) throw new FunctionError(500, "Could not validate device session.");
    if (!session?.user_id) throw new FunctionError(401, "Patient session is invalid or expired.");

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

    const relation = await loadPatientPermissionRelation(serviceClient, String(session.user_id));

    return {
      patientId: String(session.user_id),
      actorUserId: String(session.user_id),
      actorRole: "patient",
      relation,
    };
  }

  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user?.id) {
    throw new FunctionError(401, "Authentication required.");
  }

  const authUserId = userData.user.id;
  const requestedPatientId = body.target_patient_id ? String(body.target_patient_id) : authUserId;
  if (requestedPatientId === authUserId) {
    return {
      patientId: authUserId,
      actorUserId: authUserId,
      actorRole: "regular",
      relation: null,
    };
  }

  const { data: relation, error } = await serviceClient
    .from("caregiver_relations")
    .select("caregiver_id,patient_id,status,can_patient_add_meds,can_patient_manage_calendar,notify_patient_meds,notify_patient_appointments")
    .eq("caregiver_id", authUserId)
    .eq("patient_id", requestedPatientId)
    .eq("status", "active")
    .maybeSingle();

  if (error) throw new FunctionError(500, "Could not validate caregiver relationship.");
  if (!relation) throw new FunctionError(403, "You do not have access to this patient.");

  return {
    patientId: requestedPatientId,
    actorUserId: authUserId,
    actorRole: "caregiver",
    relation,
  };
}

async function loadPatientPermissionRelation(serviceClient: ReturnType<typeof createClient>, patientId: string): Promise<Record<string, unknown> | null> {
  const { data, error } = await serviceClient
    .from("caregiver_relations")
    .select("caregiver_id,patient_id,status,can_patient_add_meds,can_patient_manage_calendar,notify_patient_meds,notify_patient_appointments")
    .eq("patient_id", patientId)
    .eq("status", "active")
    .limit(1)
    .maybeSingle();

  if (error) throw new FunctionError(500, "Could not validate patient permissions.");
  return data;
}

async function assertMedicationPermission(context: PatientContext) {
  if (context.actorRole === "patient" || context.actorRole === "caregiver") {
    if (context.relation && context.relation.can_patient_add_meds === false) {
      throw new FunctionError(403, "Medication management is not allowed for this patient.");
    }
  }
}

async function assertCalendarPermission(context: PatientContext) {
  if (context.relation && context.relation.can_patient_manage_calendar === false) {
    throw new FunctionError(403, "Appointment management is not allowed for this patient.");
  }
}

function permissionsFor(context: PatientContext) {
  return {
    can_patient_add_meds: context.relation?.can_patient_add_meds ?? true,
    can_patient_manage_calendar: context.relation?.can_patient_manage_calendar ?? true,
    notify_patient_meds: context.relation?.notify_patient_meds ?? true,
    notify_patient_appointments: context.relation?.notify_patient_appointments ?? true,
  };
}

async function listMedications(serviceClient: ReturnType<typeof createClient>, patientId: string) {
  const { data, error } = await serviceClient
    .from("user_medications")
    .select("*, medications(name, food_rule, rxcui, active_ingredients)")
    .eq("user_id", patientId)
    .eq("is_active", true);

  if (error) throw new FunctionError(500, "Could not load medications.");
  return data ?? [];
}

async function saveMedication(serviceClient: ReturnType<typeof createClient>, context: PatientContext, medication: Record<string, unknown> | undefined) {
  if (!medication) throw new FunctionError(400, "Medication payload is required.");
  const row = {
    ...medication,
    id: String(medication.id ?? crypto.randomUUID()),
    user_id: context.patientId,
  };

  let { data, error } = await serviceClient
    .from("user_medications")
    .upsert(row)
    .select()
    .single();

  if (error && isMedicationPayloadCompatibilityError(error)) {
    console.error("patient-medications full save payload failed; retrying compatible payload", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    const compatibleRow = compatibleMedicationRow(medication, context.patientId, String(row.id), true);
    const retry = await serviceClient
      .from("user_medications")
      .upsert(compatibleRow)
      .select()
      .single();

    data = retry.data;
    error = retry.error;
  }

  if (error && isMedicationPayloadCompatibilityError(error)) {
    console.error("patient-medications compatible save payload failed; retrying base payload", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    const baseRow = compatibleMedicationRow(medication, context.patientId, String(row.id), false);
    const retry = await serviceClient
      .from("user_medications")
      .upsert(baseRow)
      .select()
      .single();

    data = retry.data;
    error = retry.error;
  }

  if (error) {
    console.error("patient-medications save failed", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });
    throw new FunctionError(500, "Could not save medication.");
  }
  return data;
}

function compatibleMedicationRow(
  medication: Record<string, unknown>,
  patientId: string,
  id: string,
  includeDisplayFields: boolean,
) {
  const row: Record<string, unknown> = {
    id,
    user_id: patientId,
    medication_id: medication.medication_id,
    name: medication.medication_name ?? medication.name ?? "Medication",
    dosage: medication.dosage ?? "",
    frequency_per_day: medication.frequency_per_day ?? medication.times_per_day ?? 1,
    frequency_hours: medication.frequency_hours,
    food_rule: medication.food_rule,
    dosage_times: medication.dosage_times,
    is_prn: medication.is_prn ?? false,
    is_manual_schedule: medication.is_manual_schedule ?? true,
    start_date: medication.start_date,
    end_date: medication.end_date,
    notes: medication.notes,
    is_active: medication.is_active ?? true,
  };

  if (includeDisplayFields) {
    row.visual_shape = medication.visual_shape;
    row.visual_color = medication.visual_color;
    row.visual_background_color = medication.visual_background_color;
    row.medication_form = medication.medication_form;
    row.schedule_mode = medication.schedule_mode;
    row.times_per_day = medication.times_per_day;
    row.selected_weekdays = medication.selected_weekdays;
    row.interval_days = medication.interval_days;
    row.reminders_enabled = medication.reminders_enabled;
    row.caregiver_reminders_enabled = medication.caregiver_reminders_enabled;
  }

  return Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined));
}

function isMedicationPayloadCompatibilityError(error: { code?: string; message?: string; details?: string; hint?: string }) {
  const text = [
    error.code,
    error.message,
    error.details,
    error.hint,
  ].filter(Boolean).join(" ").toLowerCase();

  return text.includes("schema cache")
    || text.includes("could not find")
    || text.includes("column")
    || text.includes("pgrst204")
    || text.includes("42703")
    || text.includes("invalid input value for enum")
    || text.includes("food_rule_enum");
}

async function deleteMedication(serviceClient: ReturnType<typeof createClient>, patientId: string, id: string) {
  const { error } = await serviceClient
    .from("user_medications")
    .delete()
    .eq("id", id)
    .eq("user_id", patientId);

  if (error) throw new FunctionError(500, "Could not delete medication.");
}

async function setMedicationActive(serviceClient: ReturnType<typeof createClient>, patientId: string, id: string, isActive: boolean) {
  const { error } = await serviceClient
    .from("user_medications")
    .update({ is_active: isActive })
    .eq("id", id)
    .eq("user_id", patientId);

  if (error) throw new FunctionError(500, "Could not update medication.");
}

async function listAppointments(serviceClient: ReturnType<typeof createClient>, patientId: string) {
  const { data, error } = await serviceClient
    .from("appointments")
    .select("id,title,doctor_name,appointment_type,appointment_time,location,notes,is_completed")
    .eq("user_id", patientId)
    .order("appointment_time");

  if (error) throw new FunctionError(500, "Could not load appointments.");
  return data ?? [];
}

async function saveAppointment(serviceClient: ReturnType<typeof createClient>, context: PatientContext, appointment: Record<string, unknown> | undefined, action: string) {
  if (!appointment) throw new FunctionError(400, "Appointment payload is required.");

  const appointmentId = appointment.id ? String(appointment.id) : crypto.randomUUID();
  if (action === "create_appointment" && appointment.id) {
    throw new FunctionError(400, "New appointments must not include an id.");
  }

  if (appointment.id) {
    const { data: existing, error: existingError } = await serviceClient
      .from("appointments")
      .select("id")
      .eq("id", appointmentId)
      .eq("user_id", context.patientId)
      .maybeSingle();

    if (existingError) throw new FunctionError(500, "Could not validate appointment ownership.");
    if (!existing) throw new FunctionError(404, "Appointment not found.");
  }

  const row: Record<string, unknown> = {
    id: appointmentId,
    user_id: context.patientId,
    title: String(appointment.title ?? "").trim(),
    doctor_name: appointment.doctor_name == null ? null : String(appointment.doctor_name),
    appointment_type: String(appointment.appointment_type ?? appointment.doctor_name ?? "doctor"),
    appointment_time: String(appointment.appointment_time ?? ""),
    location: appointment.location == null ? null : String(appointment.location).trim() || null,
    notes: appointment.notes == null ? null : String(appointment.notes).trim() || null,
  };

  if (appointment.is_completed !== undefined) {
    row.is_completed = Boolean(appointment.is_completed);
  }

  if (!row.title || !row.appointment_time) {
    throw new FunctionError(400, "Appointment title and time are required.");
  }

  const { data, error } = await serviceClient
    .from("appointments")
    .upsert(row)
    .select("id,title,doctor_name,appointment_type,appointment_time,location,notes,is_completed")
    .single();

  if (error) throw new FunctionError(500, "Could not save appointment.");
  return data;
}

async function deleteAppointment(serviceClient: ReturnType<typeof createClient>, patientId: string, id: string) {
  const { error } = await serviceClient
    .from("appointments")
    .delete()
    .eq("id", id)
    .eq("user_id", patientId);

  if (error) throw new FunctionError(500, "Could not delete appointment.");
}

function requireID(id: string | undefined): string {
  const value = String(id ?? "");
  if (!value) throw new FunctionError(400, "id is required.");
  return value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

class FunctionError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}
