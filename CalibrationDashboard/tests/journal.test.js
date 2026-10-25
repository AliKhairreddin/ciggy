import { test } from "node:test";
import assert from "node:assert/strict";
import { createJournal } from "../src/lib/journal.js";

test("period changes preserve saved data on failed or incomplete responses, and local filters make no requests", async () => {
  const original = globalThis.fetch;
  let failure = false,
    incomplete = false,
    count = 0,
    summaryCount = 0;
  const row = {
    id: "synthetic",
    participant: "Sample",
    participantID: "sample",
    labelRevision: 0,
    startedAt: new Date(Date.now() - 60000).toISOString(),
    endedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 86400000).toISOString(),
  };
  globalThis.fetch = async (path) => {
    count++;
    if (path === "/api/session") return Response.json({ retentionDays: 14 });
    if (path === "/api/delivery") return Response.json({ participants: [] });
    if (path.endsWith("/overview")) {
      summaryCount++;
      return Response.json({ ...row, overview: { ranges: [], bins: [] } });
    }
    if (failure)
      return Response.json({ error: "Unavailable" }, { status: 503 });
    return Response.json({
      recordings: incomplete ? [] : [row],
      nextCursor: incomplete ? "repeated" : null,
    });
  };
  try {
    const journal = createJournal();
    await journal.initialize();
    const saved = journal.getSnapshot(),
      before = count;
    await journal.refresh(
      { ...saved.filters, participant: "sample" },
      { localFilter: true },
    );
    assert.equal(count, before);
    assert.equal(journal.getSnapshot().sessions[0].id, "synthetic");
    failure = true;
    assert.equal(
      await journal.refresh({ ...saved.filters, period: "7d" }),
      false,
    );
    assert.equal(journal.getSnapshot().filters.period, "48h");
    assert.deepEqual(journal.getSnapshot().range, saved.range);
    assert.equal(journal.getSnapshot().sessions.length, 1);
    failure = false;
    incomplete = true;
    assert.equal(
      await journal.refresh({ ...saved.filters, period: "7d" }),
      false,
    );
    assert.equal(journal.getSnapshot().sessions.length, 1);
    incomplete = false;
    assert.equal(
      await journal.refresh({ ...saved.filters, period: "7d" }),
      true,
    );
    assert.equal(journal.getSnapshot().filters.period, "7d");
    assert.equal(summaryCount, 1, "unchanged summaries are reused");
  } finally {
    globalThis.fetch = original;
  }
});
