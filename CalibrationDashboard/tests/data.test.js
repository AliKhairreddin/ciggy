import test from 'node:test';
import assert from 'node:assert/strict';
import { APPLE_EPOCH_MS, LIMITS, appleSecondsToMs, msToAppleSeconds, validateRecording, validateAnnotation,
  parseImport, mergeSessions, coverageRanges, coveredDuration, makeExport, sliceSession, cleanAlias, mergeRemotePage } from '../public/data.js';

test('recent metadata refresh preserves older history and reconciles its covered prefix', () => {
  const row = (id, hour, extra = {}) => ({ id, startedAt: `2026-10-23T${hour}:00:00Z`, endedAt: `2026-10-23T${hour}:05:00Z`, expiresAt: '2026-11-01T00:00:00Z', ...extra });
  const old = [row('a', '12'), row('b', '11'), row('c', '10'), row('d', '09')];
  const recent = [row('e', '13'), row('b', '11', { labelRevision: 2 })];
  const options = { hasMore: true, fromMs: Date.parse('2026-10-23T09:30:00Z'), toMs: Date.parse('2026-10-23T14:00:00Z'), nowMs: Date.parse('2026-10-23T14:00:00Z') };
  const merged = mergeRemotePage(old, recent, options);
  assert.deepEqual(merged.map(row => row.id), ['e', 'b', 'c']);
  assert.equal(merged[1].labelRevision, 2);
  assert.deepEqual(mergeRemotePage(old, [], { ...options, hasMore: false }), []);
  assert.throws(() => mergeRemotePage(old, [], options), /incomplete/);
});

const id = '11335577-2244-6688-aabb-ccddeeff0011';
const labelID = '22335577-2244-6688-aabb-ccddeeff0011';
const timestamp = 814123456.123456;
const vector = { x: 0, y: 0, z: -1 };
function recording(overrides = {}) {
  return { id, formatVersion: 1, startedAt: timestamp, endedAt: timestamp + 3, label: 'unlabelled', samples: [0, .02, .04, 3].map(offset => ({ timestamp: timestamp + offset,
    gravity: { ...vector }, userAcceleration: { x: .1, y: .2, z: .3 }, rotationRate: null, source: 'recordedAccelerometer' })), ...overrides };
}
function session() { const raw = validateRecording(recording()); return { id, recording: raw, participant: 'Ali', annotations: [], importedAt: '2026-10-23T00:00:00Z' }; }
function annotation(overrides = {}) { return { id: labelID, recordingID: id, start: timestamp, end: timestamp + .04, label: 'smoking', notes: 'Coffee break', ...overrides }; }

test('Apple dates are seconds since 2001, not Unix seconds', () => {
  assert.equal(appleSecondsToMs(0), Date.UTC(2001, 0, 1));
  assert.equal(appleSecondsToMs(timestamp), APPLE_EPOCH_MS + timestamp * 1000);
  assert.ok(Math.abs(msToAppleSeconds(appleSecondsToMs(timestamp)) - timestamp) < .000001);
});
test('malformed and unsupported dates fail without guessing units', () => {
  for (const value of [NaN, Infinity, '2026-10-23', undefined, 1e30]) assert.throws(() => appleSecondsToMs(value));
  assert.throws(() => msToAppleSeconds(NaN));
});
test('original sensor timestamp precision survives import and export', () => {
  const parsed = parseImport(JSON.stringify(recording()), 'motion.json', 'Ali')[0];
  assert.equal(parsed.recording.samples[0].timestamp, timestamp);
  const exported = makeExport([parsed]);
  assert.equal(exported.sessions[0].recording.samples[0].timestamp, timestamp);
  const imported = parseImport(JSON.stringify(exported), 'labels.json', 'ignored');
  assert.equal(imported[0].recording.samples[0].timestamp, timestamp);
});
test('background samples preserve absent gyroscope data', () => {
  const imported = validateRecording(recording());
  assert.equal(imported.samples[0].rotationRate, null);
  assert.equal(imported.samples[0].source, 'recordedAccelerometer');
});
test('valid live samples retain their gyroscope source', () => {
  const raw = recording(); raw.samples.forEach(sample => { sample.source = 'liveDeviceMotion'; sample.rotationRate = { x: .12, y: .23, z: .34 }; });
  const imported = validateRecording(raw);
  assert.deepEqual(imported.samples[0].rotationRate, { x: .12, y: .23, z: .34 });
});
test('malformed files and unsupported versions are rejected atomically', () => {
  assert.throws(() => parseImport('{bad', 'bad.json', 'Ali'));
  assert.throws(() => validateRecording(recording({ formatVersion: 2 })));
  assert.throws(() => validateRecording(recording({ id: '../../private' })));
  assert.throws(() => validateRecording(recording({ label: 'invented' })));
  assert.throws(() => validateRecording(recording({ samples: [] })));
});
test('reversed timestamps, invalid vectors and unknown sources are rejected', () => {
  const unordered = recording(); unordered.samples.reverse(); assert.throws(() => validateRecording(unordered));
  const duplicate = recording(); duplicate.samples[1].timestamp = duplicate.samples[0].timestamp; assert.throws(() => validateRecording(duplicate));
  const invalid = recording(); invalid.samples[2].gravity.x = NaN; assert.throws(() => validateRecording(invalid));
  const source = recording(); source.samples[1].source = 'guessedGyroscope'; assert.throws(() => validateRecording(source));
});
test('recordings larger than sample and byte limits are rejected', () => {
  assert.throws(() => validateRecording(recording({ samples: new Array(LIMITS.fileSamples + 1).fill(null) })));
  assert.throws(() => parseImport(' '.repeat(LIMITS.fileBytes + 1), 'huge.json', 'Ali'));
});
test('UUID deduplication preserves existing activity labels', () => {
  const existing = session(); existing.annotations = [annotation()];
  const result = mergeSessions([existing], [session()]);
  assert.equal(result.added, 0); assert.equal(result.duplicate, 1);
  assert.equal(result.sessions.length, 1); assert.equal(result.sessions[0].annotations.length, 1);
});
test('activity labels validate recording ownership and exact time range', () => {
  const raw = recording(); assert.equal(validateAnnotation(annotation(), raw).label, 'smoking');
  for (const value of [annotation({ start: timestamp - 1 }), annotation({ end: timestamp + 4 }), annotation({ start: timestamp + .1, end: timestamp }),
    annotation({ label: 'automatic' }), annotation({ recordingID: labelID }), annotation({ recordingID: undefined }), annotation({ notes: 'x'.repeat(2001) })]) {
    assert.throws(() => validateAnnotation(value, raw));
  }
});
test('coverage gaps are not counted as recorded movement', () => {
  const ranges = coverageRanges(recording().samples);
  assert.equal(ranges.length, 2);
  assert.equal(ranges[0].start, timestamp); assert.equal(ranges[0].end, timestamp + .04);
  assert.equal(ranges[1].start, timestamp + 3);
});
test('time slicing clips labels and preserves sample precision', () => {
  const value = session(); value.annotations = [annotation({ start: timestamp, end: timestamp + 3 })];
  const clipped = sliceSession(value, appleSecondsToMs(timestamp + .02), appleSecondsToMs(timestamp + .04));
  assert.equal(clipped.recording.samples.length, 2);
  assert.equal(clipped.annotations[0].start, timestamp + .02);
  assert.equal(clipped.annotations[0].end, timestamp + .04);
  assert.equal(sliceSession(value, appleSecondsToMs(timestamp + 5), appleSecondsToMs(timestamp + 6)), null);
});
test('coverage combines overlapping sources per person and clips to the chosen date window', () => {
  const ali = session(), secondSource = session(), friend = { ...session(), participant: 'Friend' };
  const lower = appleSecondsToMs(timestamp), upper = appleSecondsToMs(timestamp + .02);
  assert.equal(coveredDuration([ali, secondSource], lower, upper), upper - lower);
  assert.equal(coveredDuration([ali, secondSource, friend], lower, upper), 2 * (upper - lower));
});
test('labeled exports round-trip participant, labels, sources, and encoding', () => {
  const value = session(); value.annotations = [annotation()];
  const exported = makeExport([value]);
  assert.equal(exported.dateEncoding, 'secondsSince2001');
  const imported = parseImport(JSON.stringify(exported), 'backup.json', 'another');
  assert.equal(imported[0].participant, 'Ali'); assert.deepEqual(imported[0].annotations, value.annotations);
  assert.equal(imported[0].recording.samples[0].source, 'recordedAccelerometer');
});
test('participant aliases are bounded plain values', () => {
  assert.equal(cleanAlias(' Friend '), 'Friend');
  assert.throws(() => cleanAlias(' ')); assert.throws(() => cleanAlias('x'.repeat(81)));
});
