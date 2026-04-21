import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import { corsHeaders, safeParseJSON } from "../_shared/drug-utils.ts";

const interactionPrompt = `
You are a clinical pharmacy safety engine. You will receive a list of drug-drug interactions from the NIH RxNav database.
Your job is to:
1. Categorize each interaction as "HIGH", "MEDIUM", or "LOW" severity.
2. HIGH: Potential for life-threatening effects or severe organ damage. Avoid this combination.
3. MEDIUM: Notable clinical effect. Monitor closely and consult a doctor.
4. LOW: Minor interaction. Be aware but generally safe to continue.
5. Provide a SHORT (max 15 words) patient-friendly explanation in the requested language.

Return a JSON array of objects:
[
  {
    "severity": "HIGH" | "MEDIUM" | "LOW",
    "description": "Patient friendly alert..."
  }
]
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
  if (!OPENAI_API_KEY) {
    return new Response(JSON.stringify({ error: "Missing OpenAI Key" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { rxcuis, lang = "English" } = await req.json();
    if (!rxcuis || !Array.isArray(rxcuis) || rxcuis.length < 2) {
      return new Response(JSON.stringify({ interactions: [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Fetch Interactions from RxNav
    const url = `https://rxnav.nlm.nih.gov/REST/interaction/list.json?rxcuis=${rxcuis.join("+")}`;
    const resp = await fetch(url);
    const rawData = await resp.json();

    // 2. Extract descriptions
    const interactionDescriptions: string[] = [];
    const groups = rawData.fullInteractionTypeGroup ?? [];
    for (const group of groups) {
      for (const type of group.fullInteractionType ?? []) {
        for (const pair of type.interactionPair ?? []) {
          interactionDescriptions.push(pair.description);
        }
      }
    }

    if (interactionDescriptions.length === 0) {
      return new Response(JSON.stringify({ interactions: [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. Map to severity with OpenAI
    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    const chat = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: interactionPrompt },
        { 
          role: "user", 
          content: `Language: ${lang}\nInteractions found:\n${interactionDescriptions.join("\n- ")}` 
        },
      ],
    });

    const raw = chat.choices?.[0]?.message?.content ?? "";
    const interactions = safeParseJSON(raw);

    return new Response(JSON.stringify({ interactions }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Interaction crash:", e);
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
