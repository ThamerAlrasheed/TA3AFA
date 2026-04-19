import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export type DrugIntel = {
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
You are a pharmacy assistant. Return ONLY strict JSON (no prose) for the requested medication.
Keys:
- title: string
- strengths: array like ["5 mg","10 mg"]
- food_rule: "before_food" | "after_food" | "none"
- min_interval_hours: integer hours or null
- interactions_to_avoid: array of short strings
- common_side_effects: array of short strings
- how_to_take: array of short bullets
- what_for: array of short bullets
Do not include any keys other than those above.
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

export function cleanDrugData(data: Partial<DrugIntel>, fallbackName: string): DrugIntel {
  return {
    title: (data.title != null && String(data.title).trim() !== "") ? String(data.title).trim() : fallbackName,
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

// Caching Helpers
export async function getMedicationFromDB(name: string): Promise<DrugIntel | null> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  const { data, error } = await supabase
    .from("medications")
    .select("*")
    .ilike("name", name)
    .limit(1)
    .single();

  if (error || !data) return null;

  return {
    title: data.name,
    strengths: data.strengths ?? [],
    food_rule: data.food_rule as DrugIntel["food_rule"],
    min_interval_hours: data.min_interval_hours,
    interactions_to_avoid: data.interactions_to_avoid ?? [],
    common_side_effects: data.common_side_effects ?? [],
    how_to_take: data.how_to_take ?? [],
    what_for: data.what_for ?? [],
  };
}

export async function saveMedicationToDB(data: DrugIntel): Promise<void> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  await supabase
    .from("medications")
    .upsert({
      name: data.title,
      strengths: data.strengths,
      food_rule: data.food_rule,
      min_interval_hours: data.min_interval_hours,
      interactions_to_avoid: data.interactions_to_avoid,
      common_side_effects: data.common_side_effects,
      how_to_take: data.how_to_take,
      what_for: data.what_for,
    }, { onConflict: "name" })
    .execute();
}
