import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type FoodRule = "before_food" | "after_food" | "with_food" | "none";

export interface DrugSummary {
  title: string;
  strengths: string[];
  food_rule: FoodRule;
  active_ingredients?: string[];
  min_interval_hours: number | null;
  interactions_to_avoid: string[];
  common_side_effects: string[];
  how_to_take: string[];
  what_for: string[];
  safety_warnings: string[];
}

export interface DrugIntelResponse extends DrugSummary {
  id?: string;
  rxcui: string | null;
  sources: {
    name: string;
    url?: string;
    fetched_at: string;
  }[];
  is_ai_generated: boolean;
  model?: string;
}

export interface DrugCandidate {
  name: string;
  strength: string | null;
  dosage_form: string | null;
  confidence: number;
  detected_text: string | null;
}

export interface ImageToDrugResponse {
  candidates: DrugCandidate[];
  is_high_confidence: boolean;
  requires_confirmation: boolean;
  model: string;
  analysis_id: string;
}

export const imageAnalysisSystemPrompt = `
You are a medical vision assistant. Your task is to identify medication from the provided image.
Return a list of potential candidates (max 3) ordered by confidence descending.

STRICT RULES:
1. "name" MUST be the brand or generic name.
2. "strength" (e.g., "200mg") and "dosage_form" (e.g., "Tablet") should be extracted if visible.
3. "confidence" is a float between 0.0 and 1.0.
4. "detected_text" should contain the raw text that led to this identification.
5. If the image is blurry or ambiguous, provide multiple candidates with lower confidence.
6. Return ONLY valid JSON matching the requested schema.

Schema keys:
- candidates: array of { name, strength, dosage_form, confidence, detected_text }
`;

export function validateImageCandidates(data: any): data is { candidates: DrugCandidate[] } {
  if (!data || !Array.isArray(data.candidates)) return false;
  for (const c of data.candidates) {
    if (typeof c.name !== "string") return false;
    if (typeof c.confidence !== "number" || c.confidence < 0 || c.confidence > 1) return false;
  }
  return true;
}

export type WarningType = "DUPLICATE_INGREDIENT" | "DRUG_INTERACTION" | "ALLERGY_CONFLICT" | "CONDITION_CONFLICT";
export type Severity = "contraindicated" | "major" | "moderate" | "minor" | "unknown";

export interface SafetyWarning {
  type: WarningType;
  severity: Severity;
  affected_medication_ids?: string[];
  meds: string[];
  ingredients: string[];
  description: string;
  management: string | null;
  source: string;
  is_deterministic: boolean;
  requires_acknowledgement: boolean;
  can_continue: boolean;
}

export interface SafetyCheckResponse {
  warnings: SafetyWarning[];
  source_trace: string[];
}

export interface ParsedSchedule {
  dose_amount: number | null;
  dose_unit: "tablet" | "capsule" | "ml" | "drop" | "puff" | "unknown" | null;
  frequency_per_day: number | null;
  interval_hours: number | null;
  times_of_day: string[];
  food_rule: "before_food" | "after_food" | "with_food" | "none";
  as_needed: boolean;
  raw_text: string;
  language: "ar" | "en" | "unknown";
  confidence: number;
  needs_confirmation: boolean;
}

export function validateParsedSchedule(data: any): data is ParsedSchedule {
  if (!data || typeof data !== "object") return false;
  
  const validUnits = ["tablet", "capsule", "ml", "drop", "puff", "unknown", null];
  if (!validUnits.includes(data.dose_unit)) return false;

  const validFoodRules = ["before_food", "after_food", "with_food", "none"];
  if (!validFoodRules.includes(data.food_rule)) return false;

  const validLanguages = ["ar", "en", "unknown"];
  if (!validLanguages.includes(data.language)) return false;

  if (typeof data.as_needed !== "boolean") return false;
  if (typeof data.confidence !== "number") return false;
  if (typeof data.needs_confirmation !== "boolean") return false;

  return true;
}

// Simple curated map for allergy classes
// Map keys are normalized lower-case search terms (e.g., from patient_allergies)
// All keys are the output of normalizeDrugTerm() — lowercase, spaces only, no punctuation.
const _NSAID_MEMBERS = ["ibuprofen", "naproxen", "aspirin", "celecoxib", "diclofenac", "advil", "motrin", "brufen", "nurofen", "aleve", "voltaren", "naprosyn"];
const _PENICILLIN_MEMBERS = ["amoxicillin", "ampicillin", "penicillin", "dicloxacillin", "piperacillin", "augmentin", "amoxil", "clavulanate"];
const _CEPHALOSPORIN_MEMBERS = ["cephalexin", "cefuroxime", "ceftriaxone", "cefazolin", "cefixime", "cefprozil", "cefdinir"];
const _MACROLIDE_MEMBERS = ["azithromycin", "clarithromycin", "erythromycin"];
const _TETRACYCLINE_MEMBERS = ["doxycycline", "minocycline", "tetracycline"];
const _FLUOROQUINOLONE_MEMBERS = ["ciprofloxacin", "levofloxacin", "moxifloxacin", "ofloxacin", "norfloxacin"];
const _SULFONAMIDE_MEMBERS = ["sulfamethoxazole", "sulfasalazine", "bactrim", "septra", "trimethoprim", "co trimoxazole"];
const _STATIN_MEMBERS = ["atorvastatin", "simvastatin", "rosuvastatin", "pravastatin", "lovastatin", "fluvastatin"];
const _OPIOID_MEMBERS = ["morphine", "codeine", "tramadol", "oxycodone", "hydrocodone", "fentanyl", "hydromorphone"];
const _ACE_INHIBITOR_MEMBERS = ["lisinopril", "enalapril", "ramipril", "captopril", "benazepril", "perindopril"];

export const ALLERGY_CLASS_MAP: Record<string, string[]> = {
  // NSAIDs — all brand/generic aliases and class labels
  "ibuprofen":                          _NSAID_MEMBERS,
  "advil":                              _NSAID_MEMBERS,
  "motrin":                             _NSAID_MEMBERS,
  "brufen":                             _NSAID_MEMBERS,
  "nurofen":                            _NSAID_MEMBERS,
  "naproxen":                           _NSAID_MEMBERS,
  "aleve":                              _NSAID_MEMBERS,
  "aspirin":                            _NSAID_MEMBERS,
  "diclofenac":                         _NSAID_MEMBERS,
  "voltaren":                           _NSAID_MEMBERS,
  "celecoxib":                          _NSAID_MEMBERS,
  "nsaid":                              _NSAID_MEMBERS,
  "nsaids":                             _NSAID_MEMBERS,
  "nonsteroidal anti inflammatory":     _NSAID_MEMBERS,
  "nonsteroidal anti inflammatory drug":_NSAID_MEMBERS,
  "non steroidal anti inflammatory":    _NSAID_MEMBERS,
  "anti inflammatory":                  _NSAID_MEMBERS,

  // Penicillins
  "penicillin":                         _PENICILLIN_MEMBERS,
  "penicillins":                        _PENICILLIN_MEMBERS,
  "amoxicillin":                        _PENICILLIN_MEMBERS,
  "augmentin":                          _PENICILLIN_MEMBERS,
  "amoxil":                             _PENICILLIN_MEMBERS,
  "ampicillin":                         _PENICILLIN_MEMBERS,

  // Cephalosporins
  "cephalosporin":                      _CEPHALOSPORIN_MEMBERS,
  "cephalosporins":                     _CEPHALOSPORIN_MEMBERS,
  "cephalexin":                         _CEPHALOSPORIN_MEMBERS,
  "cefuroxime":                         _CEPHALOSPORIN_MEMBERS,
  "ceftriaxone":                        _CEPHALOSPORIN_MEMBERS,

  // Macrolides
  "macrolide":                          _MACROLIDE_MEMBERS,
  "macrolides":                         _MACROLIDE_MEMBERS,
  "azithromycin":                       _MACROLIDE_MEMBERS,
  "clarithromycin":                     _MACROLIDE_MEMBERS,
  "erythromycin":                       _MACROLIDE_MEMBERS,

  // Tetracyclines
  "tetracycline":                       _TETRACYCLINE_MEMBERS,
  "tetracyclines":                      _TETRACYCLINE_MEMBERS,
  "doxycycline":                        _TETRACYCLINE_MEMBERS,
  "minocycline":                        _TETRACYCLINE_MEMBERS,

  // Fluoroquinolones / Quinolones
  "fluoroquinolone":                    _FLUOROQUINOLONE_MEMBERS,
  "fluoroquinolones":                   _FLUOROQUINOLONE_MEMBERS,
  "quinolone":                          _FLUOROQUINOLONE_MEMBERS,
  "quinolones":                         _FLUOROQUINOLONE_MEMBERS,
  "ciprofloxacin":                      _FLUOROQUINOLONE_MEMBERS,
  "levofloxacin":                       _FLUOROQUINOLONE_MEMBERS,
  "moxifloxacin":                       _FLUOROQUINOLONE_MEMBERS,

  // Sulfonamides
  "sulfa":                              _SULFONAMIDE_MEMBERS,
  "sulfas":                             _SULFONAMIDE_MEMBERS,
  "sulfonamide":                        _SULFONAMIDE_MEMBERS,
  "sulfonamides":                       _SULFONAMIDE_MEMBERS,
  "sulfonamide antibiotic":             _SULFONAMIDE_MEMBERS,
  "sulfamethoxazole":                   _SULFONAMIDE_MEMBERS,
  "bactrim":                            _SULFONAMIDE_MEMBERS,
  "septra":                             _SULFONAMIDE_MEMBERS,

  // Statins
  "statin":                             _STATIN_MEMBERS,
  "statins":                            _STATIN_MEMBERS,
  "atorvastatin":                       _STATIN_MEMBERS,
  "simvastatin":                        _STATIN_MEMBERS,
  "rosuvastatin":                       _STATIN_MEMBERS,

  // Opioids
  "opioid":                             _OPIOID_MEMBERS,
  "opioids":                            _OPIOID_MEMBERS,
  "morphine":                           _OPIOID_MEMBERS,
  "codeine":                            _OPIOID_MEMBERS,
  "tramadol":                           _OPIOID_MEMBERS,
  "oxycodone":                          _OPIOID_MEMBERS,

  // ACE inhibitors
  "ace inhibitor":                      _ACE_INHIBITOR_MEMBERS,
  "ace inhibitors":                     _ACE_INHIBITOR_MEMBERS,
  "lisinopril":                         _ACE_INHIBITOR_MEMBERS,
  "enalapril":                          _ACE_INHIBITOR_MEMBERS,
  "ramipril":                           _ACE_INHIBITOR_MEMBERS,
};

export const INGREDIENT_ALIAS_MAP: Record<string, string> = {
  // NSAIDs — all map to canonical ingredient name
  ibuprofen:      "ibuprofen",
  advil:          "ibuprofen",
  motrin:         "ibuprofen",
  brufen:         "ibuprofen",
  nurofen:        "ibuprofen",
  naproxen:       "naproxen",
  aleve:          "naproxen",
  naprosyn:       "naproxen",
  diclofenac:     "diclofenac",
  voltaren:       "diclofenac",
  cataflam:       "diclofenac",
  celecoxib:      "celecoxib",
  celebrex:       "celecoxib",
  aspirin:        "aspirin",
  asa:            "aspirin",
  // Acetaminophen / Paracetamol
  acetaminophen:  "acetaminophen",
  paracetamol:    "acetaminophen",
  tylenol:        "acetaminophen",
  panadol:        "acetaminophen",
  calpol:         "acetaminophen",
  // Penicillins
  amoxicillin:    "amoxicillin",
  amoxil:         "amoxicillin",
  augmentin:      "amoxicillin",
  ampicillin:     "ampicillin",
  penicillin:     "penicillin",
  piperacillin:   "piperacillin",
  // Cephalosporins
  cephalexin:     "cephalexin",
  cefuroxime:     "cefuroxime",
  ceftriaxone:    "ceftriaxone",
  cefazolin:      "cefazolin",
  cefixime:       "cefixime",
  // Macrolides
  azithromycin:   "azithromycin",
  zithromax:      "azithromycin",
  clarithromycin: "clarithromycin",
  erythromycin:   "erythromycin",
  // Tetracyclines
  doxycycline:    "doxycycline",
  minocycline:    "minocycline",
  tetracycline:   "tetracycline",
  // Fluoroquinolones
  ciprofloxacin:  "ciprofloxacin",
  cipro:          "ciprofloxacin",
  levofloxacin:   "levofloxacin",
  levaquin:       "levofloxacin",
  moxifloxacin:   "moxifloxacin",
  ofloxacin:      "ofloxacin",
  // Sulfonamides
  sulfamethoxazole: "sulfamethoxazole",
  trimethoprim:     "trimethoprim",
  bactrim:          "sulfamethoxazole",
  septra:           "sulfamethoxazole",
  // Statins
  atorvastatin:   "atorvastatin",
  lipitor:        "atorvastatin",
  simvastatin:    "simvastatin",
  zocor:          "simvastatin",
  rosuvastatin:   "rosuvastatin",
  crestor:        "rosuvastatin",
  // Opioids
  morphine:       "morphine",
  codeine:        "codeine",
  tramadol:       "tramadol",
  oxycodone:      "oxycodone",
  hydrocodone:    "hydrocodone",
  fentanyl:       "fentanyl",
  // ACE inhibitors
  lisinopril:     "lisinopril",
  zestril:        "lisinopril",
  enalapril:      "enalapril",
  vasotec:        "enalapril",
  ramipril:       "ramipril",
  altace:         "ramipril",
  // Metformin
  metformin:      "metformin",
  glucophage:     "metformin",
};

export function normalizeDrugTerm(value: string | null | undefined) {
  return (value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function inferKnownIngredients(name: string, ingredients: string[] = []) {
  const explicitIngredients = ingredients.map(normalizeDrugTerm).filter(Boolean);
  const terms = [name, ...ingredients].map(normalizeDrugTerm).filter(Boolean);
  const inferred = new Set<string>();

  for (const term of terms) {
    for (const [alias, ingredient] of Object.entries(INGREDIENT_ALIAS_MAP)) {
      if (term === alias || term.includes(alias)) {
        inferred.add(ingredient);
      }
    }

    if (explicitIngredients.includes(term) && !isDrugClassLabel(term)) {
      inferred.add(term);
    }
  }

  return [...inferred];
}

function isDrugClassLabel(term: string) {
  return term.includes(" epc") ||
    term.includes("nonsteroidal anti inflammatory drug") ||
    term.includes("non steroidal anti inflammatory drug");
}

/**
 * Resolve the class members for an allergy term.
 * 1. Exact key lookup in ALLERGY_CLASS_MAP.
 * 2. Substring lookup: find a class key (≥4 chars) that is contained
 *    within the term — handles cases like "nsaids class" matching "nsaids",
 *    or "sulfa antibiotics" matching "sulfa".
 */
export function resolveAllergyClassMembers(term: string): string[] {
  const exact = ALLERGY_CLASS_MAP[term];
  if (exact) return exact;
  for (const [key, members] of Object.entries(ALLERGY_CLASS_MAP)) {
    if (key.length >= 4 && (term.includes(key) || key.includes(term))) {
      return members;
    }
  }
  return [];
}

export const drugSummarySchema = {
  type: "object",
  properties: {
    title: { type: "string" },
    strengths: { type: "array", items: { type: "string" } },
    food_rule: { enum: ["before_food", "after_food", "with_food", "none"] },
    min_interval_hours: { type: ["number", "null"] },
    interactions_to_avoid: { type: "array", items: { type: "string" } },
    common_side_effects: { type: "array", items: { type: "string" } },
    how_to_take: { type: "array", items: { type: "string" } },
    what_for: { type: "array", items: { type: "string" } },
    safety_warnings: { type: "array", items: { type: "string" } },
  },
  required: [
    "title",
    "strengths",
    "food_rule",
    "min_interval_hours",
    "interactions_to_avoid",
    "common_side_effects",
    "how_to_take",
    "what_for",
    "safety_warnings"
  ],
};

export const hardenedSystemPrompt = `
You are a clinical pharmacy editor. Your task is to synthesize raw data from NIH/FDA into a clean, patient-friendly JSON.

STRICT RULES:
1. "title" MUST be the brand or generic name provided.
2. USE ONLY the provided source data.
3. If a field (e.g. food_rule, interactions) is not mentioned in the source data, return an empty array or null (for numbers) or "none" (for food_rule).
4. DO NOT invent safety warnings or medical advice not found in the source.
5. BULLET POINTS must be 10 words or less and patient-friendly.
6. Remove FDA section numbers/headings, reference IDs, hyperlink errors, table references, and broken numbering.
7. Never return raw strings like "1 INDICATIONS AND USAGE", "6 ADVERSE REACTIONS", or "Error! Hyperlink reference not valid."
8. Translation: If requested, provide high-quality medical translation for the strings.
9. Format: Return ONLY valid JSON matching the requested schema.

Schema keys:
- title, strengths, food_rule, min_interval_hours, interactions_to_avoid, common_side_effects, how_to_take, what_for, safety_warnings
`;

// --- Validation ---

export function validateDrugSummary(data: any): data is DrugSummary {
  const keys = drugSummarySchema.required as (keyof DrugSummary)[];
  for (const key of keys) {
    if (!(key in data)) return false;
  }
  
  if (!["before_food", "after_food", "with_food", "none"].includes(data.food_rule)) return false;
  
  const arrayKeys: (keyof DrugSummary)[] = [
    "strengths", "interactions_to_avoid", "common_side_effects", 
    "how_to_take", "what_for", "safety_warnings"
  ];
  
  for (const key of arrayKeys) {
    if (!Array.isArray(data[key])) return false;
  }

  return true;
}

// --- Patient-facing normalization ---

const SECTION_HEADINGS = [
  "BOXED WARNING",
  "INDICATIONS AND USAGE",
  "DOSAGE AND ADMINISTRATION",
  "DOSAGE FORMS AND STRENGTHS",
  "CONTRAINDICATIONS",
  "WARNINGS AND PRECAUTIONS",
  "WARNINGS",
  "PRECAUTIONS",
  "ADVERSE REACTIONS",
  "DRUG INTERACTIONS",
  "USE IN SPECIFIC POPULATIONS",
  "OVERDOSAGE",
  "DESCRIPTION",
  "CLINICAL PHARMACOLOGY",
  "NONCLINICAL TOXICOLOGY",
  "CLINICAL STUDIES",
  "HOW SUPPLIED/STORAGE AND HANDLING",
  "PATIENT COUNSELING INFORMATION",
  "INFORMATION FOR PATIENTS",
  "MEDICATION GUIDE",
].map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));

const SECTION_HEADING_RE = new RegExp(
  `(^|[\\n.;])\\s*(?:\\d+(?:\\.\\d+)?\\s+)?(?:${SECTION_HEADINGS.join("|")})\\b\\s*[:.\\-–—]?\\s*`,
  "gim",
);

export function sanitizePatientText(input: unknown, maxCharacters = 1200): string {
  let text = Array.isArray(input) ? input.filter(Boolean).join("\n\n") : String(input ?? "");
  text = text
    .replace(/<[^>]+>/g, " ")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .replace(/[•·‣]/g, "\n• ")
    .replace(/\berror!\s*hyperlink reference not valid\.?/gi, " ")
    .replace(/\breference id:\s*[a-z0-9-]+/gi, " ")
    .replace(/\bsee\s+(?:warnings and precautions|adverse reactions|drug interactions|clinical studies|full prescribing information)\s*\([^)]+\)/gi, " ")
    .replace(SECTION_HEADING_RE, "$1")
    .replace(/(^|\n)\s*(?:[-*•]\s*)?(?:\d+\s*\)\]\s*|\(?\d+(?:\.\d+)?\)?[\].)]\s*)/gm, "$1")
    .replace(/(^|\n)\s*[-*•]+\s*/gm, "$1")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{2,}/g, "\n")
    .trim();

  text = text.replace(/^[:;,\-.–—\s]+/, "").trim();
  if (!isUsefulPatientText(text)) return "";
  if (text.length <= maxCharacters) return text;

  const clipped = text.slice(0, maxCharacters);
  const sentenceEnd = Math.max(clipped.lastIndexOf("."), clipped.lastIndexOf(";"), clipped.lastIndexOf(":"));
  if (sentenceEnd > 80) return clipped.slice(0, sentenceEnd + 1).trim();
  return `${clipped.slice(0, clipped.lastIndexOf(" ")).trim()}...`;
}

export function sanitizePatientList(values: unknown, max = 5): string[] {
  const rawValues = Array.isArray(values) ? values : [values];
  const seen = new Set<string>();
  const out: string[] = [];

  for (const raw of rawValues) {
    const prepared = String(raw ?? "")
      .replace(/\s+(?=\d+\s*\)\])/g, "\n")
      .replace(/\s+(?=\(?\d+\)?[\].)]\s+[A-Z])/g, "\n")
      .replace(/[-*]\s*•/g, "\n•")
      .replace(/[•·‣]/g, "\n• ");

    const parts = prepared
      .split(/\n|;/)
      .flatMap((part) => part.length > 220 ? part.replace(/\.\s+/g, ".\n").split("\n") : [part]);

    for (const part of parts) {
      const clean = sanitizePatientText(part, 180);
      if (!clean || isSourceBoilerplate(clean)) continue;
      const key = canonicalTextKey(clean);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(clean);
      if (out.length >= max) return out;
    }
  }

  return out;
}

export function normalizeStrengths(values: unknown): string[] {
  const rawValues = Array.isArray(values) ? values : [values];
  const seen = new Set<string>();
  const out: string[] = [];

  for (const raw of rawValues) {
    const fragments = String(raw ?? "")
      .replace(/;/g, ",")
      .replace(/\sand\s/gi, ", ")
      .split(",")
      .map((part) => part.trim())
      .filter(Boolean);

    for (const fragment of fragments.length ? fragments : [String(raw ?? "")]) {
      const normalized = normalizeStrength(fragment);
      if (!normalized) continue;
      const key = normalized.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(normalized);
    }
  }

  return out;
}

export function normalizeDrugSummary(summary: DrugSummary): DrugSummary {
  return {
    ...summary,
    title: sanitizePatientText(summary.title, 120) || summary.title,
    strengths: normalizeStrengths(summary.strengths),
    active_ingredients: sanitizePatientList(summary.active_ingredients ?? [], 12),
    interactions_to_avoid: sanitizePatientList(summary.interactions_to_avoid, 4),
    common_side_effects: sanitizePatientList(summary.common_side_effects, 5),
    how_to_take: sanitizePatientList(summary.how_to_take, 5),
    what_for: sanitizePatientList(summary.what_for, 4),
    safety_warnings: sanitizePatientList(summary.safety_warnings, 5),
  };
}

function normalizeStrength(raw: string): string | null {
  let value = raw
    .trim()
    .replace(/(^|[^0-9])\.(\d+)/g, "$10.$2")
    .replace(/[µμ]g/g, "mcg")
    .replace(/\[iU\]/gi, "IU")
    .replace(/\bmicrograms?\b/gi, "mcg")
    .replace(/\bmilligrams?\b/gi, "mg")
    .replace(/\bmilliliters?\b/gi, "mL")
    .replace(/\bml\b/gi, "mL")
    .replace(/\biu\b/gi, "IU")
    .replace(/\bper\b/gi, "/")
    .replace(/\s+/g, " ");

  if (!value || /\[[^\]]+\]/.test(value) || /hp_|arb'u/i.test(value)) return null;

  value = value
    .replace(/\s*\/\s*1\s*(mL)\b/g, "/mL")
    .replace(/\s*\/\s*1\s*$/g, "")
    .replace(/\s*\/\s*/g, "/")
    .replace(/(\d)(mg|mcg|g|mL|IU)\b/g, "$1 $2")
    .trim();

  const match = value.match(/^([0-9]+(?:\.[0-9]+)?)\s*(mg|mcg|g|mL|IU)(?:\/([0-9]+(?:\.[0-9]+)?)?\s*(mg|mcg|g|mL|IU|unit|units))?$/i);
  if (match) {
    const amount = formatStrengthNumber(Number(match[1]));
    const unit = displayStrengthUnit(match[2]);
    const denominatorAmount = match[3] ? Number(match[3]) : null;
    const denominatorUnit = match[4] ? displayStrengthUnit(match[4]) : null;
    if (!denominatorUnit) return `${amount} ${unit}`;
    if (denominatorUnit === "unit" || denominatorUnit === "units") return `${amount} ${unit}`;
    if (denominatorAmount && denominatorAmount !== 1) {
      return `${amount} ${unit}/${formatStrengthNumber(denominatorAmount)} ${denominatorUnit}`;
    }
    return `${amount} ${unit}/${denominatorUnit}`;
  }

  if (!/\d+(?:\.\d+)?\s*(mg|mcg|g|mL|IU)\b/i.test(value) &&
      !/\b(tablet|tablets|capsule|capsules|gummy|gummies|drop|drops|puff|puffs|spray|sprays)\b/i.test(value)) {
    return null;
  }

  return value;
}

function isUsefulPatientText(value: string): boolean {
  const lower = value.toLowerCase();
  if (value.length < 3) return false;
  if (lower.includes("error! hyperlink reference not valid")) return false;
  if (/^reference id:/.test(lower)) return false;
  if (/^(?:\d+|\d+\.\d+)$/.test(lower)) return false;
  if (/^(?:table|figure)\s+\d+/.test(lower)) return false;
  return true;
}

function isSourceBoilerplate(value: string): boolean {
  const lower = value.toLowerCase();
  return [
    /^the following clinically significant adverse reactions/,
    /^because clinical trials are conducted/,
    /^the data described below reflect/,
    /^to report suspected adverse reactions/,
    /^see full prescribing information/,
    /^see warnings and precautions/,
    /^these highlights do not include all the information/,
  ].some((pattern) => pattern.test(lower));
}

function canonicalTextKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function displayStrengthUnit(unit: string): string {
  switch (unit.toLowerCase()) {
    case "ml": return "mL";
    case "iu": return "IU";
    default: return unit.toLowerCase();
  }
}

function formatStrengthNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : String(Number(value.toFixed(4)));
}

// --- Source Fetching ---

export async function normalizeToRxCUI(name: string): Promise<string | null> {
  try {
    const resp = await fetch(`https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(name)}`);
    const data = await resp.json();
    return data.idGroup?.rxnormId?.[0] ?? null;
  } catch { return null; }
}

export async function fetchMedlinePlus(rxcui: string) {
  try {
    const url = `https://connect.medlineplus.gov/service?mainSearchCriteria.v.cs=2.16.840.1.113883.6.88&mainSearchCriteria.v.c=${rxcui}&knowledgeResponseType=application/json`;
    const resp = await fetch(url);
    const data = await resp.json();
    const entries = data.feed?.entry ?? [];
    const text = entries.map((e: any) => e.summary?._value || "").join("\n\n");
    return text ? { text, url } : null;
  } catch { return null; }
}

export async function fetchOpenFDA(rxcui: string) {
  try {
    const url = `https://api.fda.gov/drug/label.json?search=openfda.rxcui.exact:"${rxcui}"&limit=1`;
    const resp = await fetch(url);
    if (!resp.ok) return null;
    const data = await resp.json();
    const result = data.results?.[0];
    if (!result) return null;
    
    const text = sanitizePatientText([
      result.description,
      result.dosage_and_administration,
      result.indications_and_usage,
      result.adverse_reactions,
      result.warnings,
      result.precautions
    ].flatMap((value) => Array.isArray(value) ? value : value ? [value] : []));
    
    return text ? { text, url, normalized_version: "patient-label-v1" } : null;
  } catch { return null; }
}

// --- Caching Helpers ---

export async function getSourceCache(
  supabase: SupabaseClient,
  source: string,
  queryKey: string
) {
  const { data, error } = await supabase
    .from("drug_source_cache")
    .select("*")
    .eq("source", source)
    .eq("query_key", queryKey)
    .eq("cache_scope", "public")
    .gt("expires_at", new Date().toISOString())
    .limit(1)
    .maybeSingle();

  if (error) console.error(`Source cache lookup error (${source}):`, error);
  return data;
}

export async function saveSourceCache(
  supabase: SupabaseClient,
  params: {
    source: string;
    query_type: string;
    query_key: string;
    response: any;
    expires_in_days?: number;
  }
) {
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + (params.expires_in_days || 30));

  const { data, error } = await supabase
    .from("drug_source_cache")
    .insert({
      source: params.source,
      query_type: params.query_type,
      query_key: params.query_key,
      response: params.response,
      expires_at: expiresAt.toISOString(),
      cache_scope: "public"
    })
    .select("id")
    .single();

  if (error) console.error(`Source cache save error (${params.source}):`, error);
  return data?.id;
}

export async function getAISummaryCache(
  supabase: SupabaseClient,
  drugKey: string,
  locale: string,
  promptVersion: string
) {
  const { data, error } = await supabase
    .from("drug_ai_summary_cache")
    .select("*")
    .eq("drug_key", drugKey)
    .eq("locale", locale)
    .eq("prompt_version", promptVersion)
    .eq("cache_scope", "public")
    .gt("expires_at", new Date().toISOString())
    .limit(1)
    .maybeSingle();

  if (error) console.error("Summary cache lookup error:", error);
  return data;
}

export async function saveAISummaryCache(
  supabase: SupabaseClient,
  params: {
    drug_key: string;
    locale: string;
    model: string;
    prompt_version: string;
    summary: DrugSummary;
    source_cache_ids: string[];
    expires_in_days?: number;
  }
) {
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + (params.expires_in_days || 30));

  const { data, error } = await supabase
    .from("drug_ai_summary_cache")
    .insert({
      drug_key: params.drug_key,
      locale: params.locale,
      model: params.model,
      prompt_version: params.prompt_version,
      summary: normalizeDrugSummary(params.summary),
      source_cache_ids: params.source_cache_ids,
      expires_at: expiresAt.toISOString(),
      cache_scope: "public"
    })
    .select("id")
    .single();

  if (error) console.error("Summary cache save error:", error);
  return data?.id;
}
