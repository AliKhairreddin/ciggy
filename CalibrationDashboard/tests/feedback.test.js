import { test } from 'node:test';
import assert from 'node:assert/strict';
import { coverageEvidence, makeFeedbackExport } from '../src/lib/feedback.js';
import { reviewQuery } from '../public/review-link.js';
import { initialFilters, periodBounds } from '../src/lib/period.js';
import { msToAppleSeconds } from '../public/data.js';

const start = Date.parse('2025-10-09T17:45:00Z'), end = start + 300000;
const participantID = '00000000-0000-4000-8000-000000000001';
const feedback = { id: '00000000-0000-4000-8000-000000000002', participantID, start, end, missedCount: 2, reason: 'unknown', notes: 'Synthetic observation.' };
function session(person = participantID) {
  const timestamps = [start + 60000, start + 60500, start + 61000, start + 180000, start + 180500];
  return { participantID: person, participant: 'Synthetic tester', annotations: [],
    recording: { id: '00000000-0000-4000-8000-000000000003', formatVersion: 1, startedAt: msToAppleSeconds(start), endedAt: msToAppleSeconds(end),
      samples: timestamps.map(at => ({ timestamp: msToAppleSeconds(at), source: 'recordedAccelerometer', gravity: { x: 0, y: 0, z: -1 }, userAcceleration: { x: 0, y: 0, z: 0 }, rotationRate: null })) } };
}
test('feedback can export a whole missing interval without fabricating raw data or a cause', () => {
  const result = makeFeedbackExport(feedback, []);
  assert.equal(result.coverage.status, 'no-uploaded-motion');
  assert.deepEqual(result.coverage.unavailableRangesUnixMs, [[start, end]]);
  assert.equal(result.motion.sessions.length, 0);
  assert.equal(result.feedback.countCorrectionApplied, false);
  assert.match(result.coverage.explanation, /do not prove/);
});
test('evidence excludes other testers and preserves actual samples, source and gaps', () => {
  const result = makeFeedbackExport(feedback, [session(), session('someone-else')], { delivery: [{ participantID }, { participantID: 'someone-else' }] });
  assert.equal(result.motion.sessions.length, 1);
  assert.equal(result.motion.sessions[0].recording.samples.length, 5);
  assert.equal(result.motion.sessions[0].recording.samples[0].rotationRate, null);
  assert.equal(result.coverage.availableRangesUnixMs.length, 2);
  assert.equal(result.coverage.unavailableRangesUnixMs.length, 3);
  assert.equal(result.delivery.length, 1);
});
test('partial overview loading never claims a confirmed empty interval', () => {
  const result = coverageEvidence([], start, end, false);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.unavailableRangesUnixMs, null);
});
test('deep links keep exact period and tester, strip redirects and reject invalid ranges', () => {
  const input = `?from=${new Date(start).toISOString()}&to=${new Date(end).toISOString()}&participant=${participantID}&review=${feedback.id}&returnTo=https://invalid.example`;
  const query = reviewQuery(input);
  assert.equal(new URLSearchParams(query).has('returnTo'), false);
  const filters = initialFilters(query);
  assert.equal(filters.participant, participantID);
  assert.deepEqual(periodBounds(filters), [start, end]);
  assert.equal(reviewQuery('?from=bad&to=bad'), '');
  assert.equal(reviewQuery(`?from=${end}&to=${start}`), '');
});
