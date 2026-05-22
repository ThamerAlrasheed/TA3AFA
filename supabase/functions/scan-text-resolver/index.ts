const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ResolverRequest = {
  scanSessionId?: string;
  ocrText?: string;
  extractedFields?: Record<string, unknown>;
  databaseCandidates?: Array<Record<string, unknown>>;
  userLocale?: string;
};

type ResolverResponse = {
  bestMatchMedicationId: string | null;
  confidence: "high" | "medium" | "low";
  reason: string;
  missingOrUncertainFields: string[];
  requiresUserConfirmation: boolean;
  needsFallback: boolean;
  fallbackReason: string | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Authentication required" }, 401);
  }

  let body: ResolverRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const candidates = Array.isArray(body.databaseCandidates) ? body.databaseCandidates : [];
  const scanSessionId = String(body.scanSessionId ?? "");
  const ocrText = String(body.ocrText ?? "");

  if (!scanSessionId || !body.extractedFields) {
    return json({ error: "scanSessionId and extractedFields are required" }, 400);
  }

  if (candidates.length === 0) {
    const response: ResolverResponse = {
      bestMatchMedicationId: null,
      confidence: "low",
      reason: "No database candidates were provided for resolution.",
      missingOrUncertainFields: ["databaseCandidates"],
      requiresUserConfirmation: true,
      needsFallback: true,
      fallbackReason: "No database candidate matched the scan text.",
    };
    console.log(JSON.stringify({
      scanSessionId,
      candidateCount: 0,
      confidence: response.confidence,
      fallbackNeeded: response.needsFallback,
    }));
    return json(response);
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return json({ error: "OPENAI_API_KEY is not configured" }, 500);
  }

  const system = [
    "You classify OCR-extracted medication package text against provided medication database candidates.",
    "You must not invent medications.",
    "You must not provide medical advice.",
    "You must not decide whether a medication is safe, appropriate, or acceptable for a patient.",
    "Use only OCR text, extracted fields, and database candidates.",
    "Always require user confirmation.",
    "Return strict JSON only.",
  ].join(" ");

  const user = JSON.stringify({
    ocrText: safeTruncate(ocrText, 4000),
    extractedFields: body.extractedFields,
    databaseCandidates: candidates,
    userLocale: body.userLocale ?? "en",
    responseSchema: {
      bestMatchMedicationId: "string|null",
      confidence: "high|medium|low",
      reason: "string",
      missingOrUncertainFields: ["string"],
      requiresUserConfirmation: true,
      needsFallback: "boolean",
      fallbackReason: "string|null",
    },
  });

  try {
    const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_SCAN_TEXT_MODEL") ?? "gpt-4.1-mini",
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
      }),
    });

    if (!aiResponse.ok) {
      const errorText = await aiResponse.text();
      console.error("scan-text-resolver OpenAI error", aiResponse.status, safeTruncate(errorText, 300));
      return json({ error: "Resolver failed" }, 502);
    }

    const completion = await aiResponse.json();
    const content = completion?.choices?.[0]?.message?.content ?? "{}";
    const parsed = sanitizeResponse(JSON.parse(content), candidates);

    console.log(JSON.stringify({
      scanSessionId,
      candidateCount: candidates.length,
      confidence: parsed.confidence,
      fallbackNeeded: parsed.needsFallback,
    }));

    return json(parsed);
  } catch (error) {
    console.error("scan-text-resolver failure", String(error));
    return json({ error: "Resolver failed" }, 502);
  }
});

function sanitizeResponse(value: Record<string, unknown>, candidates: Array<Record<string, unknown>>): ResolverResponse {
  const candidateIds = new Set(
    candidates
      .map((candidate) => String(candidate.medicationId ?? candidate.medication_id ?? ""))
      .filter(Boolean),
  );
  const requestedId = typeof value.bestMatchMedicationId === "string" ? value.bestMatchMedicationId : null;
  const bestMatchMedicationId = requestedId && candidateIds.has(requestedId) ? requestedId : null;
  const confidence = value.confidence === "high" || value.confidence === "medium" ? value.confidence : "low";
  const missing = Array.isArray(value.missingOrUncertainFields)
    ? value.missingOrUncertainFields.map(String).slice(0, 8)
    : [];

  return {
    bestMatchMedicationId,
    confidence,
    reason: safeTruncate(String(value.reason ?? "Candidate resolution requires user confirmation."), 500),
    missingOrUncertainFields: missing,
    requiresUserConfirmation: true,
    needsFallback: Boolean(value.needsFallback) || bestMatchMedicationId === null && confidence === "low",
    fallbackReason: value.fallbackReason == null ? null : safeTruncate(String(value.fallbackReason), 300),
  };
}

function safeTruncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
