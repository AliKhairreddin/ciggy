import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deliverySummary } from '../public/delivery.js';
test('delivery explanations distinguish stages and do not treat stale or empty reports as proof', () => {
  const now = 1790000000000;
  const report = { observedAt: now, phonePendingCount: 0, phoneScheduledCount: 0, watch: { queuedTransferCount: 0, pendingWindowCount: 0 } };
  assert.match(deliverySummary(null, now), /Waiting/);
  assert.match(deliverySummary(report, now), /does not prove/);
  assert.match(deliverySummary({ ...report, watch: { queuedTransferCount: 1 } }, now), /Watch.*waiting/);
  assert.match(deliverySummary({ ...report, watch: { pendingWindowCount: 2 } }, now), /awaiting preparation/);
  assert.match(deliverySummary({ ...report, phonePendingCount: 2 }, now), /reached iPhone/);
  assert.match(deliverySummary({ ...report, phonePendingCount: 2, phoneScheduledCount: 2 }, now), /queued with Apple/);
  assert.match(deliverySummary({ ...report, phonePendingCount: 2 }, now + 91 * 60000), /over 90 minutes old/);
  assert.match(deliverySummary({ ...report, watch: { checkedAt: now - 91 * 60000, queuedTransferCount: 2 } }, now), /current queue is unknown/);
});
