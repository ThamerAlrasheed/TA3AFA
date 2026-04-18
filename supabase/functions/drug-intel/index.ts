import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import {
  corsHeaders,
  systemPrompt,
  safeParseJSON,
  cleanDrugData,
  DrugIntel,
} from "../_shared/drug-utils.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
  if (!OPENAI_API_KEY) {
    return new Response(JSON.stringify({ error: "Missing OPENAI_API_KEY" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { name } = await req.json();
    if (!name) {
      return new Response(JSON.stringify({ error: "Missing 'name'" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    const chat = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: `Medication name: ${name}\nReturn the JSON now.` },
      ],
    });

    const raw = chat.choices?.[0]?.message?.content ?? "";
    const data = safeParseJSON<Partial<DrugIntel>>(raw);
    const clean = cleanDrugData(data, name);

    return new Response(JSON.stringify(clean), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("drug-intel error:", e);
    return new Response(JSON.stringify({ error: e.message ?? "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
