#!/usr/bin/env node
// npm run rebuild-projections [-- --restaurant <restaurantId>]
//
// Clears the report projections of the LOCAL D1 and replays them from the
// immutable event ledger, using exactly the SQL that event ingest uses
// (src/projections/sql.ts). Idempotent: running it again changes nothing.
// The Worker-side equivalent is rebuildProjections() in
// src/projections/rebuild.ts (covered by test/reports.test.ts).
//
// --remote is refused: rebuilding the deployed database needs the owner's
// explicit decision (see docs/CLOUDFLARE_SETUP.md).
//
// Needs Node >= 22.18 (loads the shared TypeScript module directly).

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  CLEAR_PROJECTION_STATEMENTS,
  PROJECTION_STATEMENTS,
  inlineParameters,
} from "../src/projections/sql.ts";
import { argValue, migrateLocal, queryLocal, refuseRemote, wrangler } from "./wrangler-local.mjs";

const argv = process.argv.slice(2);
refuseRemote(argv);
const only = argValue(argv, "--restaurant");
if (only !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(only)) {
  console.error("--restaurant must be a restaurant id");
  process.exit(2);
}

migrateLocal();
const restaurants = queryLocal("SELECT id FROM restaurants ORDER BY id")
  .map((r) => r.id)
  .filter((id) => only === undefined || id === only);
if (only !== undefined && restaurants.length === 0) {
  console.error(`No restaurant ${only} in the local D1`);
  process.exit(1);
}
const epochs = queryLocal(
  "SELECT restaurant_id, epoch, start_sequence, next_sequence FROM epochs ORDER BY restaurant_id, epoch",
);

const statements = [];
let replayed = 0;
for (const restaurantId of restaurants) {
  for (const sql of CLEAR_PROJECTION_STATEMENTS) statements.push(inlineParameters(sql, [restaurantId]));
  for (const e of epochs.filter((x) => x.restaurant_id === restaurantId)) {
    if (e.next_sequence <= e.start_sequence) continue;
    replayed += e.next_sequence - e.start_sequence;
    for (const sql of PROJECTION_STATEMENTS) {
      statements.push(inlineParameters(sql, [restaurantId, e.epoch, e.start_sequence, e.next_sequence - 1]));
    }
  }
}

if (statements.length === 0) {
  console.log("No restaurants in the local D1; nothing to rebuild.");
  process.exit(0);
}
const dir = mkdtempSync(join(tmpdir(), "cafedesk-rebuild-"));
const file = join(dir, "rebuild.sql");
try {
  writeFileSync(file, statements.map((s) => `${s};`).join("\n"), "utf8");
  wrangler(["d1", "execute", "DB", "--local", "--file", file]);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
console.log(`Rebuilt projections of ${restaurants.length} restaurant(s) from ${replayed} ledger event(s) (local D1).`);
