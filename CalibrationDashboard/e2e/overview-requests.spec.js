import { expect, test } from "@playwright/test";
import { build } from "esbuild";
import { convertV4MiniflareOptions, Miniflare } from "miniflare";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { applyMigrations } from "../tests-server/migrations.js";
import { recording } from "./recording.js";

test("opening the shared timeline reads summaries and exporting reads the raw recording", async ({ page }) => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const bundle = await build({
    stdin: {
      contents: `import { createApp } from "./server/index.ts";
        export default createApp(async () => "reviewer@example.test");`,
      resolveDir: root,
    },
    bundle: true, write: false, format: "esm", platform: "neutral", target: "es2023",
  });
  const origin = "https://journal.example.test";
  const platform = new Miniflare(convertV4MiniflareOptions({
    modules: true,
    script: bundle.outputFiles[0].text,
    host: "127.0.0.1", port: 0,
    compatibilityDate: "2026-10-23",
    bindings: { APP_ORIGIN: origin },
    d1Databases: ["DB"], r2Buckets: ["RECORDINGS"],
    assets: {
      directory: root + "dist",
      binding: "ASSETS",
      run_worker_first: true,
      routerConfig: { has_user_worker: true },
    },
  }));
  try {
    await applyMigrations(await platform.getD1Database("DB"));
    const raw = recording(crypto.randomUUID(), new Date(Date.now() - 60000).toISOString());
    const response = await platform.dispatchFetch(origin + "/api/import", {
      method: "POST",
      headers: { origin, "content-type": "application/json" },
      body: JSON.stringify({ participant: "Timeline fixture", recording: raw, annotations: [] }),
    });
    expect(response.status).toBe(201);
    const { id } = await response.json();
    const rawPath = "/api/recordings/" + id;
    const reads = [];
    page.on("request", request => {
      if (new URL(request.url()).pathname === rawPath) reads.push(request.method());
    });
    const overview = page.waitForResponse(r => new URL(r.url()).pathname === rawPath + "/overview");
    await page.goto((await platform.ready).href);
    expect((await overview).status()).toBe(200);
    await expect(page.getByRole("button", { name: "Save activity label" })).toBeEnabled();
    expect(reads, "Browse the overview without downloading the raw recording").toEqual([]);

    const download = page.waitForEvent("download");
    await page.getByRole("button", { name: /^Export (?:labeled )?data/i }).click();
    const result = JSON.parse(await readFile(await (await download).path(), "utf8"));
    expect(reads).toEqual(["GET"]);
    expect(result.sessions).toHaveLength(1);
    expect(result.sessions[0].recording.id).toBe(raw.id);
    expect(result.sessions[0].recording.samples.map(s => s.timestamp)).toEqual(
      raw.samples.map(s => s.timestamp),
    );
  } finally {
    await platform.dispose();
  }
});
