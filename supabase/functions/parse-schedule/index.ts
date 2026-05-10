import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import { corsHeaders, ParsedSchedule, validateParsedSchedule } from "../_shared/drug-utils.ts";

const MODEL = "gpt-4o-mini";

const systemPrompt = `
You are a medical instruction parser. Your task is to convert medication instructions in English or Arabic into a structured JSON schedule.

STRICT RULES:
1. Return ONLY the JSON object matching the requested schema.
2. "dose_unit" MUST be one of: "tablet", "capsule", "ml", "drop", "puff", "unknown", or null.
3. "food_rule" MUST be one of: "before_food", "after_food", "with_food", "none".
4. "language" MUST be "ar" or "en".
5. If a value is unknown or missing, use null or empty array.
6. "confidence" is a float between 0.0 and 1.0.
7. "needs_confirmation" MUST be true if confidence < 0.85 or instructions are ambiguous.

Schema:
{
  "dose_amount": number | null,
  "dose_unit": string | null,
  "frequency_per_day": number | null,
  "interval_hours": number | null,
  "times_of_day": string[],
  "food_rule": string,
  "as_needed": boolean,
  "raw_text": string,
  "language": string,
  "confidence": number,
  "needs_confirmation": boolean
}
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { text, lang } = await req.json();
    if (!text) {
      return jsonResponse({ error: "Missing 'text'" }, 400);
    }

    const trimmedText = text.trim();
    
    // 1. Deterministic Regex Phase
    const regexResult = tryRegexParse(trimmedText);
    if (regexResult && regexResult.confidence >= 0.8) {
      return jsonResponse(regexResult);
    }

    // 2. AI Fallback Phase
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) {
       // If no key, return whatever regex found or low confidence
       return jsonResponse(regexResult || createFallbackResponse(trimmedText));
    }

    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    let result: ParsedSchedule | null = null;
    let attempts = 0;

    while (attempts < 2 && !result) {
      attempts++;
      const chat = await openai.chat.completions.create({
        model: MODEL,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `Parse this instruction: "${trimmedText}" (Target Language: ${lang || "Bilingual"})` },
        ],
      });

      const raw = chat.choices[0]?.message?.content ?? "{}";
      try {
        const parsed = JSON.parse(raw);
        if (validateParsedSchedule(parsed)) {
          result = parsed;
        }
      } catch (err) {
        console.error(`AI Parse attempt ${attempts} failed:`, err);
      }
    }

    if (result) {
      return jsonResponse(result);
    }

    return jsonResponse(regexResult || createFallbackResponse(trimmedText));

  } catch (e) {
    console.error("parse-schedule error:", e);
    return jsonResponse({ error: "Internal error parsing schedule." }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function createFallbackResponse(text: string): ParsedSchedule {
  return {
    dose_amount: null,
    dose_unit: null,
    frequency_per_day: null,
    interval_hours: null,
    times_of_day: [],
    food_rule: "none",
    as_needed: false,
    raw_text: text,
    language: "unknown",
    confidence: 0.1,
    needs_confirmation: true
  };
}

function tryRegexParse(text: string): ParsedSchedule | null {
  const lower = text.toLowerCase();
  let res = createFallbackResponse(text);
  let foundCount = 0;

  // --- Frequency / Interval (English) ---
  if (/\bq6h\b/i.test(lower) || /every 6 hours/i.test(lower)) { res.interval_hours = 6; res.frequency_per_day = 4; foundCount++; }
  else if (/\bq8h\b/i.test(lower) || /every 8 hours/i.test(lower)) { res.interval_hours = 8; res.frequency_per_day = 3; foundCount++; }
  else if (/\bq12h\b/i.test(lower) || /every 12 hours/i.test(lower)) { res.interval_hours = 12; res.frequency_per_day = 2; foundCount++; }
  else if (/once daily/i.test(lower)) { res.frequency_per_day = 1; foundCount++; }
  else if (/twice daily/i.test(lower)) { res.frequency_per_day = 2; foundCount++; }
  else if (/three times daily/i.test(lower)) { res.frequency_per_day = 3; foundCount++; }

  // --- Frequency / Interval (Arabic) ---
  if (/كل\s+[٦6]\s+ساعات/i.test(text)) { res.interval_hours = 6; res.frequency_per_day = 4; foundCount++; res.language = "ar"; }
  else if (/كل\s+[٨8]\s+ساعات/i.test(text)) { res.interval_hours = 8; res.frequency_per_day = 3; foundCount++; res.language = "ar"; }
  else if (/كل\s+[١1][٢2]\s+ساعة/i.test(text)) { res.interval_hours = 12; res.frequency_per_day = 2; foundCount++; res.language = "ar"; }
  else if (/مرة\s+يومياً/i.test(text)) { res.frequency_per_day = 1; foundCount++; res.language = "ar"; }
  else if (/مرتين\s+يومياً/i.test(text)) { res.frequency_per_day = 2; foundCount++; res.language = "ar"; }
  else if (/ثلاث\s+مرات\s+يومياً/i.test(text)) { res.frequency_per_day = 3; foundCount++; res.language = "ar"; }

  // --- Food Rule ---
  if (/before food/i.test(lower) || /قبل الأكل/i.test(text)) { res.food_rule = "before_food"; foundCount++; }
  else if (/after food/i.test(lower) || /بعد الأكل/i.test(text) || /بعد الغداء/i.test(text) || /بعد العشاء/i.test(text)) { res.food_rule = "after_food"; foundCount++; }
  else if (/with food/i.test(lower) || /مع الأكل/i.test(text)) { res.food_rule = "with_food"; foundCount++; }

  // --- Context ---
  if (/as needed/i.test(lower) || /\bprn\b/i.test(lower) || /عند الحاجة/i.test(text)) { res.as_needed = true; foundCount++; }
  if (/bedtime/i.test(lower) || /before bed/i.test(lower) || /قبل النوم/i.test(text)) { res.times_of_day.push("bedtime"); foundCount++; }

  // --- Language detect if not set ---
  if (res.language === "unknown") {
    if (/[a-zA-Z]/.test(text)) res.language = "en";
    else if (/[\u0600-\u06FF]/.test(text)) res.language = "ar";
  }

  if (foundCount > 0) {
    res.confidence = foundCount >= 2 ? 0.95 : 0.8;
    res.needs_confirmation = res.confidence < 0.85;
    return res;
  }

  return null;
}
