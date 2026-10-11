#!/usr/bin/env node
// npm run issue-enrollment-code [-- --hours 24] [-- --label "Cafe Name"] [-- --env production]
//
// Generates a single-use enrollment code, stores ONLY its SHA-256 and prints
// the code once. Give it to the café owner, who types it into CaféDesk Online
// on the POS host (Settings → Connected devices → Cloud relay).
//
// Without --env the code goes to the LOCAL D1 (wrangler dev / tests). With
// --env <name> it goes to the REMOTE D1 of that deployed environment (the
// owner decided to deploy on 2026-10-11). A bare --remote is refused: always
// name the environment.
//
// Needs Node >= 22.18 (loads the shared TypeScript module directly).

import {
  generateEnrollmentCode,
  hashEnrollmentCode,
  normalizeEnrollmentCode,
} from "../src/protocol/enrollment_code.ts";
import { argValue, migrateLocal, refuseRemote, wrangler } from "./wrangler-local.mjs";

const argv = process.argv.slice(2);
const envName = argValue(argv, "--env");
if (envName === undefined) refuseRemote(argv);
else if (!/^[a-z][a-z0-9-]{0,31}$/.test(envName)) {
  console.error("--env must be a Wrangler environment name from wrangler.jsonc, e.g. production");
  process.exit(2);
}

const hours = Number(argValue(argv, "--hours") ?? "24");
if (!Number.isInteger(hours) || hours < 1 || hours > 24 * 14) {
  console.error("--hours must be a whole number between 1 and 336");
  process.exit(2);
}
const label = argValue(argv, "--label") ?? "";
if (!/^[A-Za-z0-9 _.-]{0,64}$/.test(label)) {
  console.error("--label may contain letters, digits, spaces, '_', '.', '-' (max 64)");
  process.exit(2);
}

const code = generateEnrollmentCode();
const hash = await hashEnrollmentCode(normalizeEnrollmentCode(code));
const now = Date.now();
const expiresAt = now + hours * 3_600_000;

// Values are a hex digest, integers and a pattern-checked label: safe to inline
// (wrangler d1 execute --command cannot bind parameters).
const insert = `INSERT INTO enrollment_codes (code_hash, label, created_at, expires_at) VALUES ('${hash}', '${label}', ${now}, ${expiresAt})`;
if (envName === undefined) {
  migrateLocal();
  wrangler(["d1", "execute", "DB", "--local", "--command", insert]);
} else {
  wrangler(["d1", "execute", "DB", "--env", envName, "--remote", "--command", insert]);
}
const where = envName === undefined ? "the LOCAL D1" : `the REMOTE D1 of "${envName}"`;

console.log("");
console.log("Enrollment code (shown once, single use):");
console.log("");
console.log(`    ${code}`);
console.log("");
console.log(`Valid until ${new Date(expiresAt).toISOString()} (${hours} h). Stored in ${where} as a SHA-256 hash only.`);
