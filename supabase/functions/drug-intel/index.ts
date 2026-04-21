import "https://deno.land/x/xhr@0.1.0/mod.ts";
import OpenAI from "https://esm.sh/openai@4.58.1";
import {
  corsHeaders,
  systemPrompt,
  safeParseJSON,
  cleanDrugData,
  DrugIntel,
  getMedicationFromDB,
  saveMedicationToDB,
  normalizeToRxCUI,
  fetchMedlinePlus,
  fetchOpenFDA,
} from "../_shared/drug-utils.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
  if (!OPENAI_API_KEY) {
    console.error("Missing OPENAI_API_KEY");
    return new Response(JSON.stringify({ error: "Missing OPENAI_API_KEY" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    console.log("Request body:", body);
    const { name, lang = "English" } = body;
    
    if (!name) {
      return new Response(JSON.stringify({ error: "Missing 'name'" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Normalize to RxCUI
    const rxcui = await normalizeToRxCUI(name);
    console.log(`Resolved RxCUI for "${name}": ${rxcui}`);

    // 2. Check Cache (by RxCUI if possible, else by name)
    try {
      const cached = await getMedicationFromDB({ rxcui: rxcui ?? undefined, name });
      if (cached) {
        // Check for staleness (6 months = 180 days)
        const lastUpdated = new Date(cached.last_updated);
        const diffDays = (new Date().getTime() - lastUpdated.getTime()) / (1000 * 3600 * 24);
        
        if (diffDays < 180) {
          console.log(`Cache hit (fresh): ${name}`);
          return new Response(JSON.stringify(cached), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        console.log(`Cache hit (stale - ${Math.round(diffDays)} days): ${name}. Refreshing...`);
      }
    } catch (err) {
      console.error("Cache lookup failed:", err);
    }

    // 3. Fetch Context from NIH/FDA (if RxCUI available)
    let context = "";
    if (rxcui) {
      const [medline, fda] = await Promise.all([
        fetchMedlinePlus(rxcui),
        fetchOpenFDA(rxcui)
      ]);
      context = `RXCUI: ${rxcui}\n\nMEDLINEPLUS DATA:\n${medline ?? "N/A"}\n\nOPENFDA DATA:\n${fda ?? "N/A"}`;
    } else {
      context = "No official data found for this name. Use general medical knowledge cautiously.";
    }

    // 4. Synthesize with OpenAI (GPT as Editor)
    console.log(`Synthesizing for: ${name} (Language: ${lang})`);
    const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
    const chat = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { 
          role: "user", 
          content: `Requested name: ${name}\nLanguage: ${lang}\n\nCONTEXT DATA:\n${context}\n\nReturn the JSON now.` 
        },
      ],
    });

    const raw = chat.choices?.[0]?.message?.content ?? "";
    console.log("Raw OpenAI response length:", raw.length);
    
    const data = safeParseJSON<Partial<DrugIntel & { rxcui?: string }>>(raw);
    const clean = cleanDrugData({ ...data, rxcui: rxcui ?? undefined }, name);
    
    // 5. Save to Cache and get the database ID
    let finalId: string | undefined = undefined;
    try {
      const savedId = await saveMedicationToDB(clean);
      if (savedId) {
        finalId = savedId;
        console.log(`Saved to cache successfully, ID: ${finalId}`);
      }
    } catch (err) {
      console.error("Failed to save to cache:", err);
    }

    return new Response(JSON.stringify({ ...clean, id: finalId }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("drug-intel crash:", e);
    return new Response(JSON.stringify({ 
      error: e.message ?? "Unknown error",
      stack: e.stack 
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
