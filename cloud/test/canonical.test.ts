// Shared canonical JSON / hash vectors (protocol/vectors/canonical_hash.json):
// the Dart suite checks the same file.
import { describe, expect, it } from "vitest";
import vectors from "../../protocol/vectors/canonical_hash.json";
import {
  b64urlDecode,
  b64urlEncode,
  CanonicalJsonError,
  canonicalHash,
  canonicalJson,
  sha256hex,
} from "../src/protocol/canonical";

interface Vector {
  name: string;
  input: unknown;
  canonical: string;
  sha256: string;
}

describe("canonical JSON vectors", () => {
  const cases = vectors as Vector[];

  it("has at least 12 cases", () => {
    expect(cases.length).toBeGreaterThanOrEqual(12);
  });

  for (const vector of cases) {
    it(`reproduces: ${vector.name}`, async () => {
      expect(canonicalJson(vector.input)).toBe(vector.canonical);
      expect(await sha256hex(vector.canonical)).toBe(vector.sha256);
      expect(await canonicalHash(vector.input)).toBe(vector.sha256);
    });
  }

  it("matches JSON.stringify escaping for every BMP code unit except lone surrogates", () => {
    for (let code = 0; code < 0x10000; code++) {
      if (code >= 0xd800 && code <= 0xdfff) continue;
      const s = String.fromCharCode(code);
      expect(canonicalJson(s)).toBe(JSON.stringify(s));
    }
  });
});

describe("canonical JSON rejects what the protocol forbids", () => {
  it.each([
    ["a fraction", { amount: 1.5 }],
    ["an unsafe integer", 2 ** 53],
    ["NaN", Number.NaN],
    ["a lone lead surrogate", "\ud83d"],
    ["a lone trail surrogate in a key", { "\ude00": 1 }],
    ["undefined", undefined],
  ])("rejects %s", (_name, value) => {
    expect(() => canonicalJson(value)).toThrow(CanonicalJsonError);
  });

  it("keeps a valid surrogate pair", () => {
    expect(canonicalJson("😀")).toBe('"😀"');
  });
});

describe("base64url", () => {
  it("round-trips without padding and rejects non-canonical text", () => {
    const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
    const text = b64urlEncode(bytes);
    expect(text).not.toContain("=");
    expect(Array.from(b64urlDecode(text)!)).toEqual(Array.from(bytes));
    expect(b64urlDecode("a+b/")).toBeNull();
    expect(Array.from(b64urlDecode("AQ")!)).toEqual([1]);
    expect(b64urlDecode("AB")).toBeNull(); // stray bits after the last byte
  });
});
