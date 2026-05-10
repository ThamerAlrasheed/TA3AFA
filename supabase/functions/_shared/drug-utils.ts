import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type FoodRule = "before_food" | "after_food" | "with_food" | "none";

export interface DrugSummary {
  title: string;
  strengths: string[];
  food_rule: FoodRule;
  active_ingredients?: string[];
  min_interval_hours: number | null;
  interactions_to_avoid: string[];
  common_side_effects: string[];
  how_to_take: string[];
  what_for: string[];
  safety_warnings: string[];
}

export interface DrugIntelResponse extends DrugSummary {
  id?: string;
  rxcui: string | null;
  sources: {
    name: string;
    url?: string;
    fetched_at: string;
  }[];
  is_ai_generated: boolean;
  model?: string;
}

export interface DrugCandidate {
  name: string;
  strength: string | null;
  dosage_form: string | null;
  confidence: number;
  detected_text: string | null;
}

export interface ImageToDrugResponse {
  candidates: DrugCandidate[];
  is_high_confidence: boolean;
  requires_confirmation: boolean;
  model: string;
  analysis_id: string;
}

export const imageAnalysisSystemPrompt = `
You are a medical vision assistant. Your task is to identify medication from the provided image.
Return a list of potential candidates (max 3) ordered by confidence descending.

STRICT RULES:
1. "name" MUST be the brand or generic name.
2. "strength" (e.g., "200mg") and "dosage_form" (e.g., "Tablet") should be extracted if visible.
3. "confidence" is a float between 0.0 and 1.0.
4. "detected_text" should contain the raw text that led to this identification.
5. If the image is blurry or ambiguous, provide multiple candidates with lower confidence.
6. Return ONLY valid JSON matching the requested schema.

Schema keys:
- candidates: array of { name, strength, dosage_form, confidence, detected_text }
`;

export function validateImageCandidates(data: any): data is { candidates: DrugCandidate[] } {
  if (!data || !Array.isArray(data.candidates)) return false;
  for (const c of data.candidates) {
    if (typeof c.name !== "string") return false;
    if (typeof c.confidence !== "number" || c.confidence < 0 || c.confidence > 1) return false;
  }
  return true;
}

export type WarningType = "DUPLICATE_INGREDIENT" | "DRUG_INTERACTION" | "ALLERGY_CONFLICT" | "CONDITION_CONFLICT";
export type Severity = "contraindicated" | "major" | "moderate" | "minor" | "unknown";

export interface SafetyWarning {
  type: WarningType;
  severity: Severity;
  affected_medication_ids?: string[];
  meds: string[];
  ingredients: string[];
  description: string;
  management: string | null;
  source: string;
  is_deterministic: boolean;
  requires_acknowledgement: boolean;
  can_continue: boolean;
}

export interface SafetyCheckResponse {
  warnings: SafetyWarning[];
  source_trace: string[];
}

export interface ParsedSchedule {
  dose_amount: number | null;
  dose_unit: "tablet" | "capsule" | "ml" | "drop" | "puff" | "unknown" | null;
  frequency_per_day: number | null;
  interval_hours: number | null;
  times_of_day: string[];
  food_rule: "before_food" | "after_food" | "with_food" | "none";
  as_needed: boolean;
  raw_text: string;
  language: "ar" | "en" | "unknown";
  confidence: number;
  needs_confirmation: boolean;
}

export function validateParsedSchedule(data: any): data is ParsedSchedule {
  if (!data || typeof data !== "object") return false;
  
  const validUnits = ["tablet", "capsule", "ml", "drop", "puff", "unknown", null];
  if (!validUnits.includes(data.dose_unit)) return false;

  const validFoodRules = ["before_food", "after_food", "with_food", "none"];
  if (!validFoodRules.includes(data.food_rule)) return false;

  const validLanguages = ["ar", "en", "unknown"];
  if (!validLanguages.includes(data.language)) return false;

  if (typeof data.as_needed !== "boolean") return false;
  if (typeof data.confidence !== "number") return false;
  if (typeof data.needs_confirmation !== "boolean") return false;

  return true;
}

// Simple curated map for allergy classes
// Map keys are normalized lower-case search terms (e.g., from patient_allergies)
export const ALLERGY_CLASS_MAP: Record<string, string[]> = {
  "penicillin": ["amoxicillin", "ampicillin", "penicillin", "dicloxacillin", "piperacillin", "augmentin", "clavulanate"],
  "penicillins": ["amoxicillin", "ampicillin", "penicillin", "dicloxacillin", "piperacillin", "augmentin", "clavulanate"],
  "ibuprofen": ["ibuprofen", "advil", "motrin", "brufen", "nurofen"],
  "advil": ["ibuprofen", "advil", "motrin", "brufen", "nurofen"],
  "motrin": ["ibuprofen", "advil", "motrin", "brufen", "nurofen"],
  "brufen": ["ibuprofen", "advil", "motrin", "brufen", "nurofen"],
  "nurofen": ["ibuprofen", "advil", "motrin", "brufen", "nurofen"],
  "nsaid": ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve"],
  "nsaids": ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve"],
  "nonsteroidal anti inflammatory": ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve"],
  "nonsteroidal anti inflammatory drug": ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve"],
  "non steroidal anti inflammatory": ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve"],
  "sulfa": ["sulfamethoxazole", "sulfasalazine", "bactrim", "septra"],
};

export const INGREDIENT_ALIAS_MAP: Record<string, string> = {
  ibuprofen: "ibuprofen",
  advil: "ibuprofen",
  motrin: "ibuprofen",
  brufen: "ibuprofen",
  nurofen: "ibuprofen",
  acetaminophen: "acetaminophen",
  paracetamol: "acetaminophen",
  tylenol: "acetaminophen",
  panadol: "acetaminophen",
  amoxil: "amoxicillin",
  amoxicillin: "amoxicillin",
  augmentin: "amoxicillin",
  aleve: "naproxen",
  naproxen: "naproxen",
  aspirin: "aspirin",
};

export function normalizeDrugTerm(value: string | null | undefined) {
  return (value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function inferKnownIngredients(name: string, ingredients: string[] = []) {
  const explicitIngredients = ingredients.map(normalizeDrugTerm).filter(Boolean);
  const terms = [name, ...ingredients].map(normalizeDrugTerm).filter(Boolean);
  const inferred = new Set<string>();

  for (const term of terms) {
    for (const [alias, ingredient] of Object.entries(INGREDIENT_ALIAS_MAP)) {
      if (term === alias || term.includes(alias)) {
        inferred.add(ingredient);
      }
    }

    if (explicitIngredients.includes(term) && !isDrugClassLabel(term)) {
      inferred.add(term);
    }
  }

  return [...inferred];
}

function isDrugClassLabel(term: string) {
  return term.includes(" epc") ||
    term.includes("nonsteroidal anti inflammatory drug") ||
    term.includes("non steroidal anti inflammatory drug");
}

export const drugSummarySchema = {
  type: "object",
  properties: {
    title: { type: "string" },
    strengths: { type: "array", items: { type: "string" } },
    food_rule: { enum: ["before_food", "after_food", "with_food", "none"] },
    min_interval_hours: { type: ["number", "null"] },
    interactions_to_avoid: { type: "array", items: { type: "string" } },
    common_side_effects: { type: "array", items: { type: "string" } },
    how_to_take: { type: "array", items: { type: "string" } },
    what_for: { type: "array", items: { type: "string" } },
    safety_warnings: { type: "array", items: { type: "string" } },
  },
  required: [
    "title",
    "strengths",
    "food_rule",
    "min_interval_hours",
    "interactions_to_avoid",
    "common_side_effects",
    "how_to_take",
    "what_for",
    "safety_warnings"
  ],
};

export const hardenedSystemPrompt = `
You are a clinical pharmacy editor. Your task is to synthesize raw data from NIH/FDA into a clean, patient-friendly JSON.

STRICT RULES:
1. "title" MUST be the brand or generic name provided.
2. USE ONLY the provided source data.
3. If a field (e.g. food_rule, interactions) is not mentioned in the source data, return an empty array or null (for numbers) or "none" (for food_rule).
4. DO NOT invent safety warnings or medical advice not found in the source.
5. BULLET POINTS must be 10 words or less and patient-friendly.
6. Translation: If requested, provide high-quality medical translation for the strings.
7. Format: Return ONLY valid JSON matching the requested schema.

Schema keys:
- title, strengths, food_rule, min_interval_hours, interactions_to_avoid, common_side_effects, how_to_take, what_for, safety_warnings
`;

// --- Validation ---

export function validateDrugSummary(data: any): data is DrugSummary {
  const keys = drugSummarySchema.required as (keyof DrugSummary)[];
  for (const key of keys) {
    if (!(key in data)) return false;
  }
  
  if (!["before_food", "after_food", "with_food", "none"].includes(data.food_rule)) return false;
  
  const arrayKeys: (keyof DrugSummary)[] = [
    "strengths", "interactions_to_avoid", "common_side_effects", 
    "how_to_take", "what_for", "safety_warnings"
  ];
  
  for (const key of arrayKeys) {
    if (!Array.isArray(data[key])) return false;
  }

  return true;
}

// --- Source Fetching ---

export async function normalizeToRxCUI(name: string): Promise<string | null> {
  try {
    const resp = await fetch(`https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(name)}`);
    const data = await resp.json();
    return data.idGroup?.rxnormId?.[0] ?? null;
  } catch { return null; }
}

export async function fetchMedlinePlus(rxcui: string) {
  try {
    const url = `https://connect.medlineplus.gov/service?mainSearchCriteria.v.cs=2.16.840.1.113883.6.88&mainSearchCriteria.v.c=${rxcui}&knowledgeResponseType=application/json`;
    const resp = await fetch(url);
    const data = await resp.json();
    const entries = data.feed?.entry ?? [];
    const text = entries.map((e: any) => e.summary?._value || "").join("\n\n");
    return text ? { text, url } : null;
  } catch { return null; }
}

export async function fetchOpenFDA(rxcui: string) {
  try {
    const url = `https://api.fda.gov/drug/label.json?search=openfda.rxcui.exact:"${rxcui}"&limit=1`;
    const resp = await fetch(url);
    if (!resp.ok) return null;
    const data = await resp.json();
    const result = data.results?.[0];
    if (!result) return null;
    
    const text = [
      result.description,
      result.dosage_and_administration,
      result.indications_and_usage,
      result.adverse_reactions,
      result.warnings,
      result.precautions
    ].filter(Boolean).join("\n\n");
    
    return { text, url };
  } catch { return null; }
}

// --- Caching Helpers ---

export async function getSourceCache(
  supabase: SupabaseClient,
  source: string,
  queryKey: string
) {
  const { data, error } = await supabase
    .from("drug_source_cache")
    .select("*")
    .eq("source", source)
    .eq("query_key", queryKey)
    .eq("cache_scope", "public")
    .gt("expires_at", new Date().toISOString())
    .limit(1)
    .maybeSingle();

  if (error) console.error(`Source cache lookup error (${source}):`, error);
  return data;
}

export async function saveSourceCache(
  supabase: SupabaseClient,
  params: {
    source: string;
    query_type: string;
    query_key: string;
    response: any;
    expires_in_days?: number;
  }
) {
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + (params.expires_in_days || 30));

  const { data, error } = await supabase
    .from("drug_source_cache")
    .insert({
      source: params.source,
      query_type: params.query_type,
      query_key: params.query_key,
      response: params.response,
      expires_at: expiresAt.toISOString(),
      cache_scope: "public"
    })
    .select("id")
    .single();

  if (error) console.error(`Source cache save error (${params.source}):`, error);
  return data?.id;
}

export async function getAISummaryCache(
  supabase: SupabaseClient,
  drugKey: string,
  locale: string,
  promptVersion: string
) {
  const { data, error } = await supabase
    .from("drug_ai_summary_cache")
    .select("*")
    .eq("drug_key", drugKey)
    .eq("locale", locale)
    .eq("prompt_version", promptVersion)
    .eq("cache_scope", "public")
    .gt("expires_at", new Date().toISOString())
    .limit(1)
    .maybeSingle();

  if (error) console.error("Summary cache lookup error:", error);
  return data;
}

export async function saveAISummaryCache(
  supabase: SupabaseClient,
  params: {
    drug_key: string;
    locale: string;
    model: string;
    prompt_version: string;
    summary: DrugSummary;
    source_cache_ids: string[];
    expires_in_days?: number;
  }
) {
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + (params.expires_in_days || 30));

  const { data, error } = await supabase
    .from("drug_ai_summary_cache")
    .insert({
      drug_key: params.drug_key,
      locale: params.locale,
      model: params.model,
      prompt_version: params.prompt_version,
      summary: params.summary,
      source_cache_ids: params.source_cache_ids,
      expires_at: expiresAt.toISOString(),
      cache_scope: "public"
    })
    .select("id")
    .single();

  if (error) console.error("Summary cache save error:", error);
  return data?.id;
}
