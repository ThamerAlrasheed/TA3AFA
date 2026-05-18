import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";
import {
  corsHeaders,
  hardenedSystemPrompt,
  validateDrugSummary,
  DrugSummary,
  DrugIntelResponse,
  normalizeToRxCUI,
  fetchMedlinePlus,
  fetchOpenFDA,
  getSourceCache,
  saveSourceCache,
  getAISummaryCache,
  saveAISummaryCache,
  normalizeDrugSummary,
  sanitizePatientText,
} from "../_shared/drug-utils.ts";

const PROMPT_VERSION = "v4-normalized";
const MODEL = "gpt-4o-mini";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

  if (!OPENAI_API_KEY) {
    return jsonResponse({ error: "Missing OPENAI_API_KEY" }, 500);
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const { name, lang = "English" } = await req.json();
    if (!name) return jsonResponse({ error: "Missing 'name'" }, 400);

    const trimmedName = name.trim();

    // 1. Identity Phase: RxNorm
    const rxcui = await normalizeToRxCUI(trimmedName);
    if (!rxcui) {
      return jsonResponse({ 
        error: "Medication not found in official clinical databases.",
        details: "We only provide information for verified medications. Please check the spelling."
      }, 404);
    }

    // 2. Summary Cache Phase (Public)
    const cachedSummary = await getAISummaryCache(admin, rxcui, lang, PROMPT_VERSION);
    if (cachedSummary) {
      console.log(`Summary cache hit for RxCUI: ${rxcui}`);
      
      // Reconstruct original source trace from linked source cache rows
      let sources: DrugIntelResponse["sources"] = [];
      if (cachedSummary.source_cache_ids && cachedSummary.source_cache_ids.length > 0) {
        const { data: sourceRows } = await admin
          .from("drug_source_cache")
          .select("source, response, fetched_at")
          .in("id", cachedSummary.source_cache_ids);
        
        if (sourceRows) {
          sources = sourceRows.map(s => ({
            name: s.source,
            url: s.response.url,
            fetched_at: s.fetched_at
          }));
        }
      }

      if (sources.length === 0) {
        sources.push({ name: "Internal Cache", fetched_at: cachedSummary.generated_at });
      }

      const normalizedCachedSummary = normalizeDrugSummary(cachedSummary.summary);
      return jsonResponse({
        ...normalizedCachedSummary,
        rxcui,
        is_ai_generated: true,
        model: cachedSummary.model,
        sources
      });
    }

    // 3. Source Collection Phase
    const sourceCacheIds: string[] = [];
    const sources: DrugIntelResponse["sources"] = [];
    let combinedContext = "";

    const fetchSource = async (
      sourceName: string, 
      queryType: string, 
      fetchFn: (rxcui: string) => Promise<{text: string, url: string} | null>
    ) => {
      const cached = await getSourceCache(admin, sourceName, rxcui);
      if (cached) {
        sourceCacheIds.push(cached.id);
        sources.push({ name: sourceName, url: cached.response.url, fetched_at: cached.fetched_at });
        return sanitizePatientText(cached.response.text);
      }

      const fresh = await fetchFn(rxcui);
      if (fresh) {
        const cleanFresh = {
          ...fresh,
          text: sanitizePatientText(fresh.text),
          normalized_version: "patient-label-v1"
        };
        const id = await saveSourceCache(admin, {
          source: sourceName,
          query_type: queryType,
          query_key: rxcui,
          response: cleanFresh
        });
        if (id) sourceCacheIds.push(id);
        sources.push({ name: sourceName, url: cleanFresh.url, fetched_at: new Date().toISOString() });
        return cleanFresh.text;
      }
      return "";
    };

    const [openFDAText, medlineText] = await Promise.all([
      fetchSource("openFDA", "label_search", fetchOpenFDA),
      fetchSource("MedlinePlus", "knowledge_search", fetchMedlinePlus)
    ]);

    combinedContext = `
RXCUI: ${rxcui}
OFFICIAL LABEL DATA (openFDA):
${openFDAText || "NOT FOUND"}

PATIENT EDUCATION DATA (MedlinePlus):
${medlineText || "NOT FOUND"}
`.trim();

    if (!openFDAText && !medlineText) {
      return jsonResponse({
        error: "Insufficient data found in official sources.",
        rxcui,
        sources
      }, 404);
    }

    // 4. Synthesis Phase (AI as Editor)
    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    
    let summary: DrugSummary | null = null;
    let attempts = 0;

    while (attempts < 2 && !summary) {
      attempts++;
      const chat = await openai.chat.completions.create({
        model: MODEL,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: hardenedSystemPrompt },
          { 
            role: "user", 
            content: `Medication: ${trimmedName}\nTarget Language: ${lang}\n\nSOURCES:\n${combinedContext}` 
          },
        ],
      });

      const raw = chat.choices?.[0]?.message?.content ?? "{}";
      try {
        const parsed = JSON.parse(raw);
        if (validateDrugSummary(parsed)) {
          summary = normalizeDrugSummary(parsed);
        } else {
          console.warn(`Validation failed for ${trimmedName} (Attempt ${attempts})`);
        }
      } catch (err) {
        console.error(`JSON parse failed for ${trimmedName} (Attempt ${attempts}):`, err);
      }
    }

    if (!summary) {
      return jsonResponse({ error: "Failed to generate a valid medical summary from sources." }, 500);
    }

    // 5. Save Summary Cache
    await saveAISummaryCache(admin, {
      drug_key: rxcui,
      locale: lang,
      model: MODEL,
      prompt_version: PROMPT_VERSION,
      summary,
      source_cache_ids: sourceCacheIds
    });

    // 6. Return Hardened Response
    const response: DrugIntelResponse = {
      ...summary,
      rxcui,
      sources,
      is_ai_generated: true,
      model: MODEL
    };

    return jsonResponse(response);

  } catch (e) {
    console.error("drug-intel crash:", e);
    return jsonResponse({ error: "An internal error occurred." }, 500);
  }
});

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
