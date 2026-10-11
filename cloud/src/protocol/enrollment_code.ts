// Operator enrollment codes: 16 Crockford base32 characters (80 random bits),
// shown as XXXX-XXXX-XXXX-XXXX. Only sha256hex(normalized code) is stored.
//
// Self-contained (no imports, erasable TypeScript only): the Worker and the
// operator script scripts/issue-enrollment-code.mjs both load this file.

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 16;

/** A new random code, grouped for reading aloud / typing. */
export function generateEnrollmentCode(): string {
  // 32 symbols → rejection-free: each random byte's low 5 bits pick a symbol.
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  let code = "";
  for (const byte of bytes) code += ALPHABET[byte & 31];
  return code.match(/.{4}/g)!.join("-");
}

/**
 * Upper-cases, drops spaces and hyphens and applies Crockford's look-alike
 * rules (O→0, I/L→1). Returns null when the result is not a well-formed code.
 */
export function normalizeEnrollmentCode(input: string): string | null {
  const code = input
    .toUpperCase()
    .replace(/[\s-]/g, "")
    .replace(/O/g, "0")
    .replace(/[IL]/g, "1");
  if (code.length !== CODE_LENGTH) return null;
  for (const ch of code) if (!ALPHABET.includes(ch)) return null;
  return code;
}

/** sha256hex of the normalized code — what D1 stores. */
export async function hashEnrollmentCode(normalized: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`cafedesk-enroll:${normalized}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
