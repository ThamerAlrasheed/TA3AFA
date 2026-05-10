import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import {
  corsHeaders,
  imageAnalysisSystemPrompt,
  validateImageCandidates,
  ImageToDrugResponse,
} from "../_shared/drug-utils.ts";

const MODEL = "gpt-4o-mini";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
  if (!OPENAI_API_KEY) {
    return jsonResponse({ error: "Missing OPENAI_API_KEY" }, 500);
  }

  try {
    const { image } = await req.json();
    if (!image) {
      return jsonResponse({ error: "Missing 'image' (base64 string)" }, 400);
    }

    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    
    let result: ImageToDrugResponse | null = null;
    let attempts = 0;

    while (attempts < 2 && !result) {
      attempts++;
      const chat = await openai.chat.completions.create({
        model: MODEL,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: imageAnalysisSystemPrompt },
          {
            role: "user",
            content: [
              { type: "text", text: "Identify the medication in this image." },
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

      const raw = chat.choices?.[0]?.message?.content ?? "{}";
      try {
        const parsed = JSON.parse(raw);
        if (validateImageCandidates(parsed)) {
          // Sort and limit
          const sorted = parsed.candidates
            .sort((a, b) => b.confidence - a.confidence)
            .slice(0, 3);

          const topConfidence = sorted[0]?.confidence || 0;
          result = {
            candidates: sorted,
            is_high_confidence: topConfidence > 0.9 && sorted.length === 1,
            requires_confirmation: true,
            model: MODEL,
            analysis_id: crypto.randomUUID()
          };
        } else {
          console.warn(`Image validation failed (Attempt ${attempts})`);
        }
      } catch (err) {
        console.error(`Image identification JSON parse failed (Attempt ${attempts}):`, err);
      }
    }

    if (!result) {
      return jsonResponse({ error: "Failed to identify medication from image." }, 500);
    }

    // IMPORTANT: No saveMedicationToDB here. 
    // The client must confirm the candidate before any DB write happens.

    return jsonResponse(result);

  } catch (e) {
    console.error("image-to-drug error:", e);
    return jsonResponse({ error: e.message ?? "Unknown error" }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
