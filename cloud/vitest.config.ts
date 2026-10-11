import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Tests run inside workerd with local D1, R2 and Durable Object bindings taken
// from wrangler.jsonc. Nothing touches a Cloudflare account.
export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          // Test-only: the D1 migrations, applied by test/apply-migrations.ts.
          TEST_MIGRATIONS: await readD1Migrations("./migrations"),
          // Test-only: a small backup limit so the 413 path is cheap to exercise.
          MAX_BACKUP_BYTES: "1048576",
        },
      },
    })),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
    // WebSockets to Durable Objects are not supported with per-file storage
    // isolation (Workers Vitest known issues): one worker, shared storage.
    // Every test creates its own restaurants, so tests stay independent.
    maxWorkers: 1,
    isolate: false,
    testTimeout: 30_000,
  },
});
