import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";
import { 
  corsHeaders, 
  SafetyCheckResponse, 
  SafetyWarning, 
  WarningType, 
  Severity,
  inferKnownIngredients,
  resolveAllergyClassMembers,
  normalizeDrugTerm
} from "../_shared/drug-utils.ts";
import { logAudit } from "../_shared/audit-helpers.ts";

const MODEL = "gpt-4o-mini";

interface MedicationInput {
  id?: string | null;
  name: string;
  rxcui: string | null;
  ingredients: string[];
}

interface SafetyRequest {
  patient_id?: string;
  device_token?: string;
  medications: MedicationInput[];
  lang: string;
  // Legacy support fields if any
  rxcuis?: string[];
}

const safetyPrompt = `
You are a medical translator and editor. You will receive a clinical drug interaction or safety warning.
Your task is to:
1. Translate the warning into the requested language.
2. Simplify the text into a patient-friendly explanation of max 15 words.
3. DO NOT change the severity.
4. DO NOT add medical advice not present in the source.

Return a JSON object:
{
  "description": "Simplified translated text",
  "management": "Simplified translated management/advice if available, else null"
}
`;

async function patientIdForDeviceToken(admin: any, deviceToken: string) {
  const { data, error } = await admin
    .from("device_sessions")
    .select(`
      user_id,
      patient_devices!device_session_id(revoked_at)
    `)
    .eq("device_token", deviceToken)
    .limit(1)
    .maybeSingle();

  if (error || !data) return undefined;
  
  const devices = data.patient_devices as any[];
  if (devices && devices.some((d: any) => d.revoked_at !== null)) {
    return undefined;
  }

  return data.user_id as string | undefined;
}

async function patientIdForCaregiver(supabaseUrl: string, supabaseAnonKey: string, admin: any, req: Request, targetPatientId: string) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return undefined;

  const client = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: authData, error: authError } = await client.auth.getUser();
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

const normalizeTerm = normalizeDrugTerm;

function inferredIngredients(med: MedicationInput) {
  return inferKnownIngredients(med.name, med.ingredients ?? []);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const payload: SafetyRequest = await req.json();
    const { medications = [], lang = "English", device_token, patient_id: targetPid } = payload;
    const sourceTrace: string[] = [];

    if (device_token && targetPid) {
      return jsonResponse({ error: "Provide either device_token or patient_id, not both" }, 400);
    }

    const patientId = device_token 
      ? await patientIdForDeviceToken(admin, device_token)
      : (targetPid ? await patientIdForCaregiver(SUPABASE_URL, SUPABASE_ANON_KEY, admin, req, targetPid) : undefined);

    if ((targetPid || device_token) && !patientId) {
      return jsonResponse({ error: "Unauthorized patient context" }, 401);
    }

    // Backward compatibility for old rxcuis[] only input
    let processedMeds = medications;
    if (processedMeds.length === 0 && payload.rxcuis && payload.rxcuis.length > 0) {
      processedMeds = payload.rxcuis.map(rxcui => ({
        name: `Drug (${rxcui})`,
        rxcui,
        ingredients: []
      }));
    }

    processedMeds = processedMeds.map((med) => ({
      id: med.id ?? null,
      name: med.name,
      rxcui: med.rxcui ?? null,
      ingredients: inferredIngredients({ ...med, ingredients: med.ingredients ?? [] }),
    }));

    if (processedMeds.length < 1) {
      return jsonResponse({ warnings: [], source_trace: [] });
    }

    const warnings: SafetyWarning[] = [];

    // --- 1. Duplicate Ingredient Detection (Deterministic) ---
    sourceTrace.push("duplicate_detection");
    const ingredientMap: Record<string, { id?: string | null; name: string }[]> = {};
    processedMeds.forEach(med => {
      med.ingredients.forEach(ing => {
        const norm = normalizeTerm(ing);
        if (!norm) return;
        if (!ingredientMap[norm]) ingredientMap[norm] = [];
        const alreadyTracked = ingredientMap[norm].some(hit => {
          if (med.id && hit.id) return hit.id === med.id;
          return hit.name === med.name;
        });
        if (!alreadyTracked) ingredientMap[norm].push({ id: med.id, name: med.name });
      });
    });

    for (const [ingredient, affectedMeds] of Object.entries(ingredientMap)) {
      if (affectedMeds.length > 1) {
        warnings.push({
          type: "DUPLICATE_INGREDIENT",
          severity: "major",
          affected_medication_ids: affectedMeds.map(med => med.id).filter(Boolean) as string[],
          meds: affectedMeds.map(med => med.name),
          ingredients: [ingredient],
          description: `Multiple medications contain ${ingredient}.`,
          management: "Confirm with your doctor before taking both.",
          source: "system_deterministic",
          is_deterministic: true,
          requires_acknowledgement: true,
          can_continue: true
        });
      }
    }

    // --- 2. Allergy & Condition Checks (Deterministic) ---
    if (patientId) {
      sourceTrace.push("patient_allergies");
      const [allergiesRes, conditionsRes] = await Promise.all([
        admin.from("patient_allergies").select("name, normalized_name, severity").eq("patient_id", patientId).eq("is_active", true),
        admin.from("patient_conditions").select("name, normalized_name").eq("patient_id", patientId).eq("status", "active").eq("is_active", true)
      ]);

      const patientAllergies = (allergiesRes.data || [])
        .map((a: any) => ({
          name: a.name as string,
          normalizedName: (a.normalized_name || a.name) as string,
          severity: a.severity as string | undefined,
        }))
        .filter((a: any) => normalizeTerm(a.normalizedName));
      const patientConditions = (conditionsRes.data || []).map((c: any) => c.normalized_name || c.name);
      sourceTrace.push(patientConditions.length > 0 ? "patient_conditions_present_no_engine" : "patient_conditions_checked_no_engine");

      if (patientAllergies.length > 0) {
        processedMeds.forEach(med => {
          // Normalize med terms (name and ingredients)
          const medTerms = [med.name, ...med.ingredients]
            .map(normalizeTerm)
            .filter(Boolean);
          
          patientAllergies.forEach(allergy => {
            const allergyNorm = normalizeTerm(allergy.normalizedName);
            const allergyTerms = new Set([
              allergyNorm,
              normalizeTerm(allergy.name),
              ...inferKnownIngredients(allergy.normalizedName, []),
              ...inferKnownIngredients(allergy.name, []),
            ].filter(Boolean));
            
            // Check direct and inferred active-ingredient matches.
            const directMatch = medTerms.some(term =>
              [...allergyTerms].some(allergyTerm =>
                term.includes(allergyTerm) || allergyTerm.includes(term)
              )
            );
            
            // Check class map match (e.g. penicillins, NSAIDs).
            // resolveAllergyClassMembers does exact key lookup first, then
            // substring lookup so "nsaids class" still finds the "nsaids" key.
            const classMembers = [...allergyTerms].flatMap(term => resolveAllergyClassMembers(term));
            const classMatch = classMembers.some(member => 
              medTerms.some(term => term.includes(member) || member.includes(term))
            );

            if (directMatch || classMatch) {
              warnings.push({
                type: "ALLERGY_CONFLICT",
                severity: "contraindicated",
                affected_medication_ids: med.id ? [med.id] : [],
                meds: [med.name],
                ingredients: med.ingredients,
                description: `Matches known allergy: ${allergy.name}`,
                management: "DO NOT TAKE without medical supervision.",
                source: "patient_allergies",
                is_deterministic: true,
                requires_acknowledgement: true,
                can_continue: false
              });
            }
          });
        });
      }
    }

    // --- 3. Interaction Lookup (DB + RxNav Fallback) ---
    const rxcuis = processedMeds.map(m => m.rxcui).filter(Boolean) as string[];
    if (rxcuis.length >= 2) {
      sourceTrace.push("interaction_rules");
      let dbPairChecks = 0;
      // Primary: interaction_rules table
      // (Simplified pair check for now, can be optimized to a single query)
      for (let i = 0; i < rxcuis.length; i++) {
        for (let j = i + 1; j < rxcuis.length; j++) {
          dbPairChecks++;
          const { data: rule } = await admin
            .from("interaction_rules")
            .select("*")
            .or(`and(primary_drug_key.eq.${rxcuis[i]},interacting_drug_key.eq.${rxcuis[j]}),and(primary_drug_key.eq.${rxcuis[j]},interacting_drug_key.eq.${rxcuis[i]})`)
            .eq("is_active", true)
            .maybeSingle();

          if (rule) {
            warnings.push({
              type: "DRUG_INTERACTION",
              severity: rule.severity as Severity,
              affected_medication_ids: [processedMeds[i].id, processedMeds[j].id].filter(Boolean) as string[],
              meds: [processedMeds[i].name, processedMeds[j].name],
              ingredients: [],
              description: rule.clinical_effect || "Potentially harmful interaction detected.",
              management: rule.management,
              source: "interaction_rules",
              is_deterministic: true,
              requires_acknowledgement: rule.severity === 'major' || rule.severity === 'contraindicated',
              can_continue: rule.severity !== 'contraindicated'
            });
          }
        }
      }

      // Fallback: RxNav (If not enough DB rules found)
      if (warnings.filter(w => w.source === "interaction_rules").length < dbPairChecks) {
        sourceTrace.push("RxNav");
        try {
          const rxNavUrl = `https://rxnav.nlm.nih.gov/REST/interaction/list.json?rxcuis=${rxcuis.join("+")}`;
          const rxNavResp = await fetch(rxNavUrl);
          const rxNavData = await rxNavResp.json();
          
          const groups = rxNavData.fullInteractionTypeGroup ?? [];
          for (const group of groups) {
            for (const type of group.fullInteractionType ?? []) {
              for (const pair of type.interactionPair ?? []) {
                // Find matching med names for this pair
                const rxcuiA = pair.interactionConcept[0].minConceptItem.rxcui;
                const rxcuiB = pair.interactionConcept[1].minConceptItem.rxcui;
                const medA = processedMeds.find(m => m.rxcui === rxcuiA)?.name || "Drug A";
                const medB = processedMeds.find(m => m.rxcui === rxcuiB)?.name || "Drug B";

                // Map RxNav severity (it's often descriptive, so we default to 'moderate' if not major)
                const rxSeverity: Severity = pair.severity === 'high' ? 'major' : 'moderate';

                warnings.push({
                  type: "DRUG_INTERACTION",
                  severity: rxSeverity,
                  affected_medication_ids: [
                    processedMeds.find(m => m.rxcui === rxcuiA)?.id,
                    processedMeds.find(m => m.rxcui === rxcuiB)?.id
                  ].filter(Boolean) as string[],
                  meds: [medA, medB],
                  ingredients: [],
                  description: pair.description,
                  management: "Consult pharmacist for details.",
                  source: "RxNav",
                  is_deterministic: false,
                  requires_acknowledgement: true,
                  can_continue: true
                });
              }
            }
          }
        } catch (err) {
          console.error("RxNav fallback failed:", err);
        }
      }
    } else {
      sourceTrace.push("interaction_rules_skipped_insufficient_rxcui");
    }

    // --- 4. AI Translation & Simplification Phase ---
    if (OPENAI_API_KEY && warnings.length > 0) {
      const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
      
      for (const warning of warnings) {
        // Skip if already simple and matching language
        if (lang === "English" && warning.description.split(" ").length < 15 && warning.is_deterministic) continue;

        try {
          const chat = await openai.chat.completions.create({
            model: MODEL,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: safetyPrompt },
              { 
                role: "user", 
                content: `Language: ${lang}\nSeverity: ${warning.severity}\nWarning: ${warning.description}\nManagement: ${warning.management || "N/A"}` 
              },
            ],
          });

          const res = JSON.parse(chat.choices[0].message.content || "{}");
          if (res.description) warning.description = res.description;
          if (res.management) warning.management = res.management;
        } catch (err) {
          console.error("AI simplification failed:", err);
        }
      }
    }

    // --- 5. Audit Logging ---
    for (const warning of warnings) {
      await logAudit(admin, {
        patient_id: patientId,
        actor_role: "service",
        action: "safety_warning_generated",
        entity_table: "interaction_rules",
        metadata: {
          warning_type: warning.type,
          severity: warning.severity,
          meds: warning.meds
        },
        req
      });
    }

    return jsonResponse({
      warnings,
      source_trace: [...new Set(sourceTrace)]
    });

  } catch (e) {
    console.error("Safety Engine crash:", e);
    return jsonResponse({ error: "Internal safety check error." }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
