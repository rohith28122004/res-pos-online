// Rebuilds one restaurant's report projections from its immutable event ledger.
// Clearing and replaying run in a single D1 batch (one transaction), so a
// report never sees a half-rebuilt state. Replaying is idempotent: running it
// any number of times yields the same rows as incremental ingest did.

import { CLEAR_PROJECTION_STATEMENTS, PROJECTION_STATEMENTS } from "./sql";

export async function rebuildProjections(db: D1Database, restaurantId: string): Promise<{ epochs: number }> {
  const epochs = await db
    .prepare(
      `SELECT epoch, start_sequence, next_sequence FROM epochs
        WHERE restaurant_id = ?1 ORDER BY epoch`,
    )
    .bind(restaurantId)
    .all<{ epoch: number; start_sequence: number; next_sequence: number }>();
  const statements: D1PreparedStatement[] = CLEAR_PROJECTION_STATEMENTS.map((sql) => db.prepare(sql).bind(restaurantId));
  for (const { epoch, start_sequence, next_sequence } of epochs.results) {
    if (next_sequence <= start_sequence) continue;
    for (const sql of PROJECTION_STATEMENTS) {
      statements.push(db.prepare(sql).bind(restaurantId, epoch, start_sequence, next_sequence - 1));
    }
  }
  await db.batch(statements);
  return { epochs: epochs.results.length };
}
