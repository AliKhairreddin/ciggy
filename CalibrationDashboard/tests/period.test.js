import { test } from "node:test";
import assert from "node:assert/strict";
import {
  periodBounds,
  filterSessions,
  constrainView,
  timeInput,
  HOUR,
} from "../src/lib/period.js";
import { makeExport, msToAppleSeconds } from "../public/data.js";

test("custom ranges preserve the exact local dates and hours, including cross-midnight periods", () => {
  const filters = {
    period: "custom",
    start: "2025-06-10T23:30:00",
    end: "2025-06-11T01:15:00",
  };
  const range = periodBounds(filters);
  assert.equal(range[1] - range[0], 1.75 * HOUR);
  assert.equal(timeInput(range[0]), "2025-06-10T23:30:00.000");
  for (const end of ["", filters.start, "2025-06-09T12:00"])
    assert.throws(() => periodBounds({ ...filters, end }));
  assert.throws(() => periodBounds({ period: "day", day: "2025-02-30" }));
});

test("local calendar days follow daylight saving rather than assuming 24 hours", () => {
  const previous = process.env.TZ;
  process.env.TZ = "America/Toronto";
  try {
    assert.equal(
      periodBounds({ period: "day", day: "2025-03-09" }).reduce(
        (a, b) => b - a,
      ),
      23 * HOUR,
    );
    assert.equal(
      periodBounds({ period: "day", day: "2025-11-02" }).reduce(
        (a, b) => b - a,
      ),
      25 * HOUR,
    );
    const now = new Date("2025-11-03T12:00:00").getTime();
    const yesterday = periodBounds({ period: "yesterday" }, { now });
    assert.equal(yesterday[1] - yesterday[0], 25 * HOUR);
  } finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
});

test("period filtering includes overlapping files and respects participant and source", () => {
  const row = (id, start, end, participantID = "a") => ({
    id,
    participantID,
    sources: ["recordedAccelerometer"],
    startedAt: new Date(start).toISOString(),
    endedAt: new Date(end).toISOString(),
  });
  const sessions = [
    row("overlap", 1000, 3000),
    row("outside", 5000, 6000),
    row("other", 2000, 4000, "b"),
  ];
  assert.deepEqual(
    filterSessions(
      sessions,
      { participant: "a", source: "recordedAccelerometer" },
      [2000, 4000],
    ).map((row) => row.id),
    ["overlap"],
  );
  assert.deepEqual(filterSessions(sessions, {}, [7000, 8000]), []);
  assert.deepEqual(constrainView([0, 10000], [2000, 4000]), [2000, 4000]);
  assert.deepEqual(constrainView([3500, 4500], [2000, 4000]), [3000, 4000]);
});

test("exports clip samples and labels to the applied period and recording type", () => {
  const start = new Date("2025-06-10T12:00:00Z").getTime();
  const session = {
    id: "synthetic",
    annotations: [
      { start: msToAppleSeconds(start), end: msToAppleSeconds(start + 4000) },
    ],
    recording: {
      samples: [0, 1000, 2000, 3000, 4000].map((offset, index) => ({
        timestamp: msToAppleSeconds(start + offset),
        source: index === 2 ? "liveDeviceMotion" : "recordedAccelerometer",
      })),
    },
  };
  const result = makeExport([session], {
    fromMs: start + 1000,
    toMs: start + 3000,
    source: "recordedAccelerometer",
  });
  assert.deepEqual(
    result.sessions[0].recording.samples.map((sample) => sample.timestamp),
    [msToAppleSeconds(start + 1000), msToAppleSeconds(start + 3000)],
  );
  assert.equal(
    result.sessions[0].annotations[0].start,
    msToAppleSeconds(start + 1000),
  );
  assert.equal(
    result.sessions[0].annotations[0].end,
    msToAppleSeconds(start + 3000),
  );
  assert.deepEqual(
    makeExport([session], { fromMs: start + 5000, toMs: start + 6000 })
      .sessions,
    [],
  );
});
