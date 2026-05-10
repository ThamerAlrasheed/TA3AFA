import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type AuditAction = 
  | "care_code_created"
  | "care_code_failed"
  | "care_code_locked"
  | "care_code_redeemed"
  | "patient_device_linked"
  | "safety_warning_generated"
  | "safety_warning_ignored"
  | "patient_device_revoked"
  | "allergy_added"
  | "allergy_updated"
  | "allergy_deactivated"
  | "condition_added"
  | "condition_updated"
  | "condition_deactivated";

export async function logAudit(
  supabase: SupabaseClient,
  params: {
    patient_id?: string;
    actor_user_id?: string;
    actor_role: 'regular' | 'caregiver' | 'patient' | 'system' | 'service';
    action: AuditAction;
    entity_table: string;
    entity_id?: string;
    metadata?: Record<string, unknown>;
    req?: Request;
  }
) {
  const { patient_id, actor_user_id, actor_role, action, entity_table, entity_id, metadata, req } = params;
  
  const ip_address = req?.headers.get("x-real-ip") || req?.headers.get("x-forwarded-for");
  const user_agent = req?.headers.get("user-agent");

  const { error } = await supabase.from("audit_logs").insert({
    patient_id,
    actor_user_id,
    actor_role,
    action,
    entity_table,
    entity_id,
    ip_address,
    user_agent,
    metadata: metadata || {},
  });

  if (error) {
    console.error(`Failed to log audit event ${action}:`, error);
  }
}

export async function hashCareCode(code: string, pepper: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(code + pepper);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function getPepper(): string {
  const pepper = Deno.env.get("CARE_CODE_PEPPER");
  if (!pepper) {
    throw new Error("Missing CARE_CODE_PEPPER environment variable.");
  }
  return pepper;
}
