import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

test("dashboard HTML receives a fresh style nonce without allowing inline scripts", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const result = await build({
    stdin: {
      contents: `
    import { createApp } from './server/index.ts';
    const app = createApp(async () => 'reviewer@example.test');
    export default { fetch(request, env, ctx) {
      return app.fetch(request, { ...env, ASSETS: { fetch: async () => new Response('<!doctype html><html><head><title>Test</title></head><body></body></html>', { headers: { 'Content-Type': 'text/html' } }) } }, ctx);
    } };`,
      resolveDir: root,
      loader: "ts",
    },
    bundle: true,
    write: false,
    platform: "neutral",
    format: "esm",
    target: "es2023",
  });
  const platform = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: result.outputFiles[0].text,
      compatibilityDate: "2026-10-23",
    }),
  );
  try {
    const nonces = [];
    for (let index = 0; index < 2; index++) {
      const response = await platform.dispatchFetch("https://example.test/");
      assert.equal(response.status, 200);
      const html = await response.text(),
        csp = response.headers.get("content-security-policy");
      const nonce = html.match(/name="csp-style-nonce" content="([^"]+)"/)?.[1];
      assert.ok(nonce);
      assert.equal(Buffer.from(nonce, "base64").length, 16);
      assert.ok(csp.includes(`style-src 'self' 'nonce-${nonce}'`));
      assert.ok(csp.includes("script-src 'self';"));
      assert.ok(!csp.includes("unsafe-inline"));
      assert.equal(response.headers.get("cache-control"), "no-store");
      nonces.push(nonce);
    }
    assert.notEqual(nonces[0], nonces[1]);
  } finally {
    await platform.dispose();
  }
});
