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
    return errorResponse("configuration_error", "Image analysis service is not configured.", 503);
  }

  try {
    const { image } = await req.json();
    if (typeof image !== "string" || image.trim().length < 256) {
      return errorResponse("invalid_image", "A valid image is required.", 400);
    }

    const normalizedImage = image.trim();

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
                  url: normalizedImage.startsWith("data:") ? normalizedImage : `data:image/jpeg;base64,${normalizedImage}`,
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

          if (sorted.length === 0) {
            console.warn(`Image analysis returned no candidates (Attempt ${attempts})`);
            continue;
          }

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
      return errorResponse("analysis_failed", "Unable to analyze image.", 502);
    }

    // IMPORTANT: No saveMedicationToDB here. 
    // The client must confirm the candidate before any DB write happens.

    return jsonResponse({ success: true, source: "ai_image_analysis", ...result });

  } catch (e) {
    console.error("image-to-drug error:", e);
    const message = e instanceof Error ? e.message : "Unknown error";
    return errorResponse("analysis_failed", "Unable to analyze image.", 500, { detail: message });
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(error: string, message: string, status = 500, metadata: Record<string, unknown> = {}) {
  return jsonResponse({
    success: false,
    error,
    message,
    ...metadata,
  }, status);
}
