// Runs the project's own Wrangler against the LOCAL D1 only (no shell, no
// network account). Shared by the operator scripts in this folder.
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const wranglerBin = join(root, "node_modules", "wrangler", "bin", "wrangler.js");

export function refuseRemote(argv) {
  if (argv.includes("--remote")) {
    console.error(
      "Refusing --remote: changing the deployed D1 needs the owner's explicit decision.\n" +
        "See docs/CLOUDFLARE_SETUP.md, \"Deployment runbook\" (wrangler d1 execute DB --remote …).",
    );
    process.exit(2);
  }
}

/** Runs `wrangler <args>` in cloud/ and returns stdout; exits on failure. */
export function wrangler(args, { quiet = false } = {}) {
  const result = spawnSync(process.execPath, [wranglerBin, ...args], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, CI: "1", WRANGLER_SEND_METRICS: "false" },
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0) {
    if (!quiet) process.stderr.write(result.stderr || result.stdout || "");
    console.error(`wrangler ${args[0]} ${args[1] ?? ""} failed (exit ${result.status})`);
    process.exit(1);
  }
  return result.stdout;
}

/** Applies pending migrations to the local D1 (idempotent). */
export function migrateLocal() {
  wrangler(["d1", "migrations", "apply", "DB", "--local"]);
}

/** Runs one SQL statement on the local D1 and returns its result rows. */
export function queryLocal(sql) {
  const out = wrangler(["d1", "execute", "DB", "--local", "--json", "--command", sql]);
  const parsed = JSON.parse(out.slice(out.indexOf("[")));
  return parsed.flatMap((r) => r.results ?? []);
}

export function argValue(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

export { root };
