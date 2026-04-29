import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export type DrugIntel = {
  id?: string;
  title: string;
  strengths: string[];
  food_rule: "before_food" | "after_food" | "none";
  min_interval_hours: number | null;
  interactions_to_avoid: string[];
  common_side_effects: string[];
  how_to_take: string[];
  what_for: string[];
};

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const systemPrompt = `
You are a clinical pharmacy editor. You will be provided with raw technical data from NIH/FDA.
Your task is to synthesize this into a clean, professional JSON.

STRICT FORMATTING RULES:
1. "title" MUST be the brand name requested.
2. "strengths" must list common available strengths (e.g. ["5 mg", "10 mg"]).
3. BULLET POINTS ("how_to_take", "what_for", "common_side_effects", "interactions_to_avoid"):
   - Every single bullet point MUST be 10 words or less.
   - Use simple, patient-friendly language.
   - REMOVE all technical jargon, legal disclaimers, and clinical citations (e.g. "Due to pharmacologic effects...").
   - NO long paragraphs.
4. If a "lang" parameter is provided (e.g., "Arabic"), translate into high-quality medical Arabic.
5. If data is missing, use general knowledge but keep it conservative.

JSON keys:
- title, strengths, food_rule, min_interval_hours, interactions_to_avoid, common_side_effects, how_to_take, what_for
`;

export function safeParseJSON<T = unknown>(s: string): T {
  try {
    return JSON.parse(s) as T;
  } catch {
    const start = s.indexOf("{");
    const end = s.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(s.slice(start, end + 1)) as T;
    }
    throw new Error("Model did not return valid JSON.");
  }
}

// --- NIH / FDA API Helpers ---

export async function normalizeToRxCUI(name: string): Promise<string | null> {
  try {
    const resp = await fetch(`https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(name)}`);
    const data = await resp.json();
    return data.idGroup?.rxnormId?.[0] ?? null;
  } catch { return null; }
}

export async function fetchMedlinePlus(rxcui: string): Promise<string | null> {
  try {
    const url = `https://connect.medlineplus.gov/service?mainSearchCriteria.v.cs=2.16.840.1.113883.6.88&mainSearchCriteria.v.c=${rxcui}&knowledgeResponseType=application/json`;
    const resp = await fetch(url);
    const data = await resp.json();
    const entries = data.feed?.entry ?? [];
    return entries.map((e: any) => e.summary?._value || "").join("\n\n") || null;
  } catch { return null; }
}

export async function fetchOpenFDA(rxcui: string): Promise<string | null> {
  try {
    const url = `https://api.fda.gov/drug/label.json?search=openfda.rxcui.exact:"${rxcui}"&limit=1`;
    const resp = await fetch(url);
    if (!resp.ok) return null;
    const data = await resp.json();
    const result = data.results?.[0];
    if (!result) return null;
    
    // Combine useful technical fields
    return [
      result.description,
      result.dosage_and_administration,
      result.indications_and_usage,
      result.adverse_reactions
    ].filter(Boolean).join("\n\n");
  } catch { return null; }
}

// --- Database Helpers ---

export function cleanDrugData(data: Partial<DrugIntel & { rxcui?: string }>, fallbackName: string): DrugIntel & { rxcui?: string } {
  return {
    id: data.id,
    title: (data.title != null && String(data.title).trim() !== "") ? String(data.title).trim() : fallbackName,
    rxcui: data.rxcui,
    strengths: Array.isArray(data.strengths) ? data.strengths.map(String) : [],
    food_rule: (["before_food", "after_food", "none"] as const).includes(data.food_rule as any)
      ? (data.food_rule as DrugIntel["food_rule"])
      : "none",
    min_interval_hours:
      typeof data.min_interval_hours === "number" && Number.isFinite(data.min_interval_hours)
        ? data.min_interval_hours
        : null,
    interactions_to_avoid: Array.isArray(data.interactions_to_avoid) ? data.interactions_to_avoid.map(String) : [],
    common_side_effects: Array.isArray(data.common_side_effects) ? data.common_side_effects.map(String) : [],
    how_to_take: Array.isArray(data.how_to_take) ? data.how_to_take.map(String) : [],
    what_for: Array.isArray(data.what_for) ? data.what_for.map(String) : [],
  };
}

export async function getMedicationFromDB(query: { name?: string, rxcui?: string }): Promise<DrugIntel & { rxcui: string, last_updated: string } | null> {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return null;

  const supabase = createClient(url, key);
  let builder = supabase.from("medications").select("*");
  
  if (query.rxcui) {
    builder = builder.eq("rxcui", query.rxcui);
  } else if (query.name) {
    builder = builder.ilike("name", query.name);
  } else {
    return null;
  }

  const { data, error } = await builder.limit(1);
  if (error || !data || data.length === 0) return null;
  const row = data[0];

  return {
    id: row.id,
    title: row.name,
    rxcui: row.rxcui,
    last_updated: row.last_updated,
    strengths: row.strengths ?? [],
    food_rule: row.food_rule as DrugIntel["food_rule"],
    min_interval_hours: row.min_interval_hours,
    interactions_to_avoid: row.interactions_to_avoid ?? [],
    common_side_effects: row.common_side_effects ?? [],
    how_to_take: row.how_to_take ?? [],
    what_for: row.what_for ?? [],
  };
}

export async function saveMedicationToDB(data: DrugIntel & { rxcui?: string }): Promise<string | null> {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return null;

  const supabase = createClient(url, key);
  const { data: result, error } = await supabase
    .from("medications")
    .upsert({
      name: data.title,
      rxcui: data.rxcui,
      strengths: data.strengths,
      food_rule: data.food_rule,
      min_interval_hours: data.min_interval_hours,
      interactions_to_avoid: data.interactions_to_avoid,
      common_side_effects: data.common_side_effects,
      how_to_take: data.how_to_take,
      what_for: data.what_for,
      last_updated: new Date().toISOString(),
    }, { onConflict: "name" })
    .select("id")
    .single();

  if (error) {
    console.error("Error saving medication:", error);
    return null;
  }
  return result?.id ?? null;
}
