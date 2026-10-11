// Bulk statements: many rows in one D1 statement through json_each(?), so an
// ingest batch is a small, fixed number of statements no matter how many events
// it carries (D1 limits bound parameters per statement and queries per Worker
// invocation; see docs/CLOUDFLARE_SETUP.md).

/** Upper bound for one JSON parameter (D1 allows up to 2,000,000 bytes per value). */
const MAX_PARAM_BYTES = 900_000;

/**
 * Splits `rows` into JSON array texts of at most MAX_PARAM_BYTES each and
 * returns one prepared statement per chunk. `sql` reads the rows with
 * `json_each(?<n>)`, where ?<n> is the position after `fixed`.
 */
export function bulkStatements(
  db: D1Database,
  sql: string,
  fixed: ReadonlyArray<string | number | null>,
  rows: readonly unknown[],
): D1PreparedStatement[] {
  const statements: D1PreparedStatement[] = [];
  let chunk: string[] = [];
  let size = 2;
  const flush = () => {
    if (chunk.length === 0) return;
    statements.push(db.prepare(sql).bind(...fixed, `[${chunk.join(",")}]`));
    chunk = [];
    size = 2;
  };
  for (const row of rows) {
    const text = JSON.stringify(row);
    const bytes = new TextEncoder().encode(text).byteLength + 1;
    if (size + bytes > MAX_PARAM_BYTES) flush();
    chunk.push(text);
    size += bytes;
  }
  flush();
  return statements;
}
