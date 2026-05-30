export function normalizeCareCode(value: unknown): string {
  const raw = String(value ?? "").trim();
  let normalized = "";

  for (const character of raw) {
    if (/^[0-9]$/.test(character)) {
      normalized += character;
    }
    if (normalized.length === 6) break;
  }

  return normalized;
}

export function generateCanonicalCareCode(): string {
  return Math.floor(Math.random() * 1_000_000)
    .toString()
    .padStart(6, "0");
}

export async function careCodeFingerprint(code: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(code));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 8);
}
