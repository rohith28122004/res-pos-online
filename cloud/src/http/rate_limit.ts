// Fixed-window attempt counter in D1 (used for enrollment).

import { ApiError } from "./errors";

const STALE_AFTER_MS = 24 * 60 * 60 * 1000;

/** The client address Cloudflare saw (set by the edge; not client-controllable in production). */
export function clientAddress(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? "unknown";
}

/**
 * Counts one attempt for `bucket` and throws RATE_LIMITED when the window's
 * count goes over `limit`. Counting happens before the attempt is evaluated, so
 * failed and successful attempts are both limited.
 */
export async function hitRateLimit(
  db: D1Database,
  bucket: string,
  limit: number,
  windowMs: number,
  now: number,
): Promise<void> {
  const windowStart = now - (now % windowMs);
  const [, counted] = await db.batch<{ count: number }>([
    db.prepare("DELETE FROM rate_limits WHERE window_start < ?1").bind(now - STALE_AFTER_MS),
    db
      .prepare(
        `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 1)
         ON CONFLICT (bucket) DO UPDATE SET
           count = CASE WHEN rate_limits.window_start = excluded.window_start THEN rate_limits.count + 1 ELSE 1 END,
           window_start = excluded.window_start
         RETURNING count`,
      )
      .bind(bucket, windowStart),
  ]);
  const count = counted?.results[0]?.count ?? 1;
  if (count > limit) {
    throw new ApiError("RATE_LIMITED", "Too many attempts; wait a minute and try again", {
      retryAfterMs: windowStart + windowMs - now,
    });
  }
}
