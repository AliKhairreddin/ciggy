export const APPLE_EPOCH_MS = Date.UTC(2001, 0, 1);
export const LIMITS = Object.freeze({ fileBytes: 10 * 1024 * 1024, datasetBytes: 128 * 1024 * 1024, fileSamples: 18000, totalSamples: 1000000 });
export const LABELS = Object.freeze(['smoking', 'eating', 'drinking', 'other', 'unknown']);
export const SOURCES = Object.freeze(['liveDeviceMotion', 'recordedAccelerometer']);

// A recent page replaces its covered prefix, including deleted/missing entries.
// Older saved metadata survives until a deliberate full reconciliation.
export function mergeRemotePage(existing, recent, { hasMore, fromMs, toMs, nowMs = Date.now() }) {
  if (!hasMore) return recent;
  const last = recent.at(-1);
  if (!last) throw new Error('An incomplete recording page was returned. Saved data is kept.');
  const boundary = Date.parse(last.startedAt), ids = new Set(recent.map(row => row.id));
  return [...recent, ...existing.filter(row => {
    const start = Date.parse(row.startedAt), end = Date.parse(row.endedAt);
    return !ids.has(row.id) && end >= fromMs && start <= toMs && Date.parse(row.expiresAt) > nowMs &&
      start <= boundary;
  })];
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function appleSecondsToMs(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('A recording contains an invalid time.');
  const result = APPLE_EPOCH_MS + value * 1000;
  if (!Number.isFinite(result) || Math.abs(result) > 8640000000000000) throw new Error('A recording time is outside the supported range.');
  return result;
}
export function msToAppleSeconds(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Choose a valid time.');
  return (value - APPLE_EPOCH_MS) / 1000;
}
export function cleanAlias(value) {
  const alias = typeof value === 'string' ? value.trim() : '';
  if (!alias || alias.length > 80) throw new Error('Enter a participant name between 1 and 80 characters.');
  return alias;
}
function vector(value, name, allowNull = false) {
  if (allowNull && value == null) return null;
  if (!value || !['x', 'y', 'z'].every(axis => typeof value[axis] === 'number' && Number.isFinite(value[axis])) || !Number.isFinite(Math.hypot(value.x, value.y, value.z))) {
    throw new Error(`A recording contains invalid ${name}.`);
  }
  return { x: value.x, y: value.y, z: value.z };
}
export function validateRecording(value) {
  if (!value || value.formatVersion !== 1 || !UUID.test(value.id)) throw new Error('Choose a Ciggy motion recording (format version 1).');
  if (!['smokingGesture', 'eating', 'drinking', 'other', 'unlabelled'].includes(value.label)) throw new Error('The recording has an unsupported activity label.');
  const startedAt = appleSecondsToMs(value.startedAt);
  if (!Array.isArray(value.samples) || value.samples.length === 0 || value.samples.length > LIMITS.fileSamples) {
    throw new Error(`Each recording needs between 1 and ${LIMITS.fileSamples.toLocaleString()} motion samples.`);
  }
  let previous = -Infinity;
  const samples = value.samples.map(sample => {
    const at = appleSecondsToMs(sample.timestamp);
    if (at <= previous || at < startedAt - 1000) throw new Error('Recording samples must have increasing times after the recording starts.');
    if (!SOURCES.includes(sample.source ?? 'liveDeviceMotion')) throw new Error('The recording has an unsupported motion source.');
    previous = at;
    const gravity = vector(sample.gravity, 'gravity readings');
    if (Math.hypot(gravity.x, gravity.y, gravity.z) <= .01) throw new Error('The recording contains an invalid wrist orientation.');
    return {
      timestamp: sample.timestamp, gravity,
      userAcceleration: vector(sample.userAcceleration, 'movement readings'),
      rotationRate: vector(sample.rotationRate, 'rotation readings', true),
      source: sample.source ?? 'liveDeviceMotion'
    };
  });
  if (value.endedAt != null && appleSecondsToMs(value.endedAt) < previous) throw new Error('The recording ends before its last sample.');
  return {
    id: value.id.toLowerCase(), formatVersion: 1, label: value.label,
    startedAt: value.startedAt, endedAt: value.endedAt ?? samples.at(-1).timestamp, samples
  };
}
export function parseImport(text, fileName, participant) {
  const bytes = new TextEncoder().encode(text).byteLength;
  if (bytes > LIMITS.datasetBytes) throw new Error('This labeled export is larger than 128 MB. Export smaller time ranges.');
  let value;
  try { value = JSON.parse(text); } catch { throw new Error('This file could not be read. Choose a JSON export from Ciggy.'); }
  if (value?.kind === 'ciggy-labeled-motion' && value.formatVersion === 1) {
    if (value.dateEncoding !== 'secondsSince2001' || !Array.isArray(value.sessions) || value.sessions.length > 1000) throw new Error('This labeled export has an unsupported format.');
    let total = 0;
    return value.sessions.map(session => {
      const recording = validateRecording(session.recording);
      total += recording.samples.length;
      if (total > LIMITS.totalSamples) throw new Error('This export contains too many samples. Import a smaller selection.');
      if (!Array.isArray(session.annotations) || session.annotations.length > 10000) throw new Error('This export contains too many activity labels.');
      return {
        id: recording.id, recording, participant: cleanAlias(session.participant), fileName,
        importedAt: new Date().toISOString(),
        annotations: session.annotations.map(annotation => validateAnnotation(annotation, recording))
      };
    });
  }
  if (bytes > LIMITS.fileBytes) throw new Error('This recording is larger than 10 MB. Export smaller time ranges.');
  const recording = validateRecording(value);
  return [{ id: recording.id, recording, participant: cleanAlias(participant), fileName, importedAt: new Date().toISOString(), annotations: [] }];
}
export function validateAnnotation(value, recording) {
  const first = recording.samples[0].timestamp, last = recording.samples.at(-1).timestamp;
  if (!value || !UUID.test(value.id) || typeof value.recordingID !== 'string' || value.recordingID.toLowerCase() !== recording.id.toLowerCase() || !LABELS.includes(value.label)) throw new Error('An activity label is invalid.');
  if (typeof value.start !== 'number' || typeof value.end !== 'number' || !Number.isFinite(value.start) || !Number.isFinite(value.end) ||
      value.start >= value.end || value.start < first || value.end > last) throw new Error('Choose an activity range inside this recording.');
  if (typeof value.notes !== 'string' || value.notes.length > 2000) throw new Error('Notes must be under 2,000 characters.');
  return { id: value.id.toLowerCase(), recordingID: recording.id, start: value.start, end: value.end, label: value.label, notes: value.notes.trim() };
}
export function mergeSessions(existing, incoming) {
  const map = new Map(existing.map(session => [session.id, session]));
  let total = existing.reduce((sum, session) => sum + session.recording.samples.length, 0), added = 0, duplicate = 0;
  for (const session of incoming) {
    if (map.has(session.id)) { duplicate++; continue; }
    total += session.recording.samples.length;
    if (total > LIMITS.totalSamples) throw new Error('Your workspace has reached one million samples. Export a backup and remove older recordings first.');
    map.set(session.id, session); added++;
  }
  return { sessions: [...map.values()], added, duplicate };
}
export function coverageRanges(samples, gapSeconds = 1) {
  if (!samples.length) return [];
  const ranges = [], first = samples[0].timestamp;
  let start = first, end = first;
  for (const sample of samples.slice(1)) {
    if (sample.timestamp - end > gapSeconds) { ranges.push({ start, end }); start = sample.timestamp; }
    end = sample.timestamp;
  }
  ranges.push({ start, end });
  return ranges;
}
export function coveredDuration(sessions, fromMs, toMs) {
  const participants = new Map();
  for (const session of sessions) {
    const ranges = participants.get(session.participant) ?? [];
    for (const range of coverageRanges(session.recording.samples)) {
      const start = Math.max(fromMs, appleSecondsToMs(range.start)), end = Math.min(toMs, appleSecondsToMs(range.end));
      if (start < end) ranges.push({ start, end });
    }
    participants.set(session.participant, ranges);
  }
  let duration = 0;
  for (const ranges of participants.values()) {
    let previous = null;
    for (const range of ranges.sort((a, b) => a.start - b.start)) {
      if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
      else { if (previous) duration += previous.end - previous.start; previous = { ...range }; }
    }
    if (previous) duration += previous.end - previous.start;
  }
  return duration;
}
export function sliceSession(session, fromMs, toMs, source = '') {
  const samples = session.recording.samples.filter(sample => {
    const at = appleSecondsToMs(sample.timestamp);
    return at >= fromMs && at <= toMs && (!source || sample.source === source);
  });
  if (!samples.length) return null;
  const lower = samples[0].timestamp, upper = samples.at(-1).timestamp;
  return {
    ...session, recording: { ...session.recording, startedAt: lower, endedAt: upper, samples },
    annotations: session.annotations.filter(annotation => annotation.end > lower && annotation.start < upper)
      .map(annotation => ({ ...annotation, start: Math.max(lower, annotation.start), end: Math.min(upper, annotation.end) }))
      .filter(annotation => annotation.start < annotation.end)
  };
}
export function makeExport(sessions, { fromMs = -8640000000000000, toMs = 8640000000000000, source = '' } = {}) {
  return { kind: 'ciggy-labeled-motion', formatVersion: 1, dateEncoding: 'secondsSince2001',
    exportedAt: new Date().toISOString(), sessions: sessions.map(session => sliceSession(session, fromMs, toMs, source)).filter(Boolean) };
}
export function magnitude(value) { return value ? Math.hypot(value.x, value.y, value.z) : null; }
