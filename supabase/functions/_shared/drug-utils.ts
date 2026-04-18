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
