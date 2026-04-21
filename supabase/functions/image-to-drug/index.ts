import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import {
  corsHeaders,
  systemPrompt,
  safeParseJSON,
  cleanDrugData,
  DrugIntel,
  saveMedicationToDB,
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
    const { image } = await req.json();
    if (!image) {
      return new Response(JSON.stringify({ error: "Missing 'image' (base64 string)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    const chat = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        {
          role: "user",
          content: [
            { type: "text", text: "Identify the medication in this image and return the details in the requested JSON format." },
            {
              type: "image_url",
              image_url: {
                url: image.startsWith("data:") ? image : `data:image/jpeg;base64,${image}`,
              },
            },
          ],
        },
      ],
    });

    const raw = chat.choices?.[0]?.message?.content ?? "";
    const data = safeParseJSON<Partial<DrugIntel>>(raw);
    const clean = cleanDrugData(data, "Unknown Medication");

    // 2. Save to Cache
    await saveMedicationToDB(clean);

    return new Response(JSON.stringify(clean), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("image-to-drug error:", e);
    return new Response(JSON.stringify({ error: e.message ?? "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
