export const RETENTION_DAYS = 14;
export const MAX_BODY_BYTES = 5 * 1024 * 1024;
export const APPLE_EPOCH_MS = Date.UTC(2001, 0, 1);
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACTIVITY_LABELS = new Set(['smokingGesture', 'eating', 'drinking', 'other', 'unlabelled']);
const ANNOTATION_LABELS = new Set(['smoking', 'eating', 'drinking', 'other', 'unknown']);
const SOURCES = new Set(['liveDeviceMotion', 'recordedAccelerometer']);

export class APIError extends Error {
  constructor(public status: number, message: string, public retryAfter?: number) { super(message); }
}
export type Vector = { x: number; y: number; z: number };
export type Sample = {
  timestamp: number; gravity: Vector; userAcceleration: Vector;
  rotationRate?: Vector; source: 'liveDeviceMotion' | 'recordedAccelerometer';
};
export type Recording = {
  id: string; formatVersion: 1; label: string; startedAt: number; endedAt: number; samples: Sample[];
};
export type Annotation = { id: string; recordingID: string; start: number; end: number; label: string; notes: string };

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new APIError(400, 'Expected a JSON object.');
  return value as Record<string, unknown>;
}
function number(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new APIError(400, 'A motion sample contains an invalid number.');
  return value;
}
function vector(value: unknown, maximum: number): Vector {
  const item = object(value);
  const result = { x: number(item.x), y: number(item.y), z: number(item.z) };
  if (Math.hypot(result.x, result.y, result.z) > maximum) throw new APIError(400, 'A motion vector is outside the supported sensor range.');
  return result;
}
export function cleanAlias(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 80 || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new APIError(400, 'Use a participant alias between 1 and 80 characters.');
  }
  return value.trim();
}
export function appleDateISO(seconds: number): string { return new Date(APPLE_EPOCH_MS + seconds * 1000).toISOString(); }

/** Validates the existing Swift JSONEncoder format; all dates are seconds since 2001. */
export function validateRecording(value: unknown, now = Date.now(), maximumAgeDays = RETENTION_DAYS): Recording {
  const item = object(value);
  if (item.formatVersion !== 1 || typeof item.id !== 'string' || !UUID.test(item.id) ||
      typeof item.label !== 'string' || !ACTIVITY_LABELS.has(item.label)) {
    throw new APIError(400, 'Choose a Ciggy motion recording in format version 1.');
  }
  const startedAt = number(item.startedAt);
  const startedMs = APPLE_EPOCH_MS + startedAt * 1000;
  if (!Number.isFinite(startedMs) || startedMs < now - maximumAgeDays * 86400000 || startedMs > now + 300000) {
    throw new APIError(400, 'Upload recordings from the last 14 days with a correct device clock.');
  }
  if (!Array.isArray(item.samples) || item.samples.length < 1 || item.samples.length > 18000) {
    throw new APIError(400, 'A recording must contain between 1 and 18,000 samples.');
  }
  let previous = -Infinity;
  const samples = item.samples.map((value): Sample => {
    const sample = object(value);
    const timestamp = number(sample.timestamp);
    const source = sample.source ?? 'liveDeviceMotion';
    if (typeof source !== 'string' || !SOURCES.has(source)) throw new APIError(400, 'Unsupported motion source.');
    if (timestamp <= previous || timestamp < startedAt - 1 || timestamp > startedAt + 601 ||
        APPLE_EPOCH_MS + timestamp * 1000 > now + 300000) {
      throw new APIError(400, 'Samples must have increasing times inside a recording of at most ten minutes.');
    }
    previous = timestamp;
    const gravity = vector(sample.gravity, 4);
    if (Math.hypot(gravity.x, gravity.y, gravity.z) <= .01) throw new APIError(400, 'Invalid gravity vector.');
    const result: Sample = { timestamp, gravity, userAcceleration: vector(sample.userAcceleration, 64),
      source: source as Sample['source'] };
    if (sample.rotationRate != null) {
      if (source === 'recordedAccelerometer') throw new APIError(400, 'Recorded accelerometer samples cannot contain measured gyroscope data.');
      result.rotationRate = vector(sample.rotationRate, 100);
    }
    return result;
  });
  const endedAt = item.endedAt == null ? previous : number(item.endedAt);
  if (endedAt < previous || endedAt > startedAt + 601 || previous - samples[0].timestamp > 601) {
    throw new APIError(400, 'Recording end time is invalid.');
  }
  return { id: item.id.toLowerCase(), formatVersion: 1, label: item.label, startedAt, endedAt, samples };
}

/** A queued URLSession task can run after the phone's local queue has expired.
 * Enforce the consent/source window again before writing any native upload. */
export function validateNativeUploadWindow(recording: Recording, enrolledAt: number, now = Date.now()): void {
  const firstSample = APPLE_EPOCH_MS + recording.samples[0].timestamp * 1000;
  if (firstSample < now - 48 * 3600000) throw new APIError(410, 'This recording is older than the 48-hour sharing window.');
  if (!Number.isFinite(enrolledAt) || firstSample < enrolledAt) {
    throw new APIError(410, 'Only motion recorded after this device was paired can be shared.');
  }
}

export function validateAnnotations(value: unknown, recording: Recording): Annotation[] {
  if (!Array.isArray(value) || value.length > 512) throw new APIError(400, 'Use at most 512 labels per recording.');
  const seen = new Set<string>();
  return value.map(value => {
    const item = object(value);
    if (typeof item.id !== 'string' || !UUID.test(item.id) || typeof item.recordingID !== 'string' ||
        item.recordingID.toLowerCase() !== recording.id || typeof item.label !== 'string' || !ANNOTATION_LABELS.has(item.label)) {
      throw new APIError(400, 'An activity label is invalid.');
    }
    const id = item.id.toLowerCase();
    if (seen.has(id)) throw new APIError(400, 'Activity label IDs must be unique.');
    seen.add(id);
    const start = number(item.start), end = number(item.end);
    if (start >= end || start < recording.samples[0].timestamp || end > recording.samples.at(-1)!.timestamp) {
      throw new APIError(400, 'An activity label must stay within the recorded motion.');
    }
    const notes = item.notes ?? '';
    if (typeof notes !== 'string' || notes.length > 2000) throw new APIError(400, 'Activity notes must be under 2,000 characters.');
    return { id, recordingID: recording.id, start, end, label: item.label, notes: notes.trim() };
  });
}

/** Bound bytes while reading, including requests with no Content-Length header. */
export async function readJSON(request: Request, maximum = MAX_BODY_BYTES): Promise<unknown> {
  if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    throw new APIError(415, 'Send application/json.');
  }
  const encoding = request.headers.get('content-encoding')?.toLowerCase() ?? 'identity';
  if (!['identity', 'deflate'].includes(encoding)) throw new APIError(415, 'Use an uncompressed JSON body or Content-Encoding: deflate.');
  const compressedMaximum = encoding === 'deflate' ? Math.min(maximum, 2 * 1024 * 1024) : maximum;
  if (Number(request.headers.get('content-length')) > compressedMaximum) throw new APIError(413, 'The upload is too large. Use chunks under 5 MB.');
  if (!request.body) throw new APIError(400, 'A JSON body is required.');
  // Count compressed input before decompression and decoded bytes afterwards.
  let compressedBytes = 0;
  const boundedInput = request.body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      compressedBytes += chunk.byteLength;
      if (compressedBytes > compressedMaximum) throw new APIError(413, 'The compressed upload is too large.');
      controller.enqueue(chunk);
    }
  }));
  const decoded = encoding === 'deflate' ? boundedInput.pipeThrough(new DecompressionStream('deflate')) : boundedInput;
  const reader = decoded.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    let part: ReadableStreamReadResult<Uint8Array>;
    try { part = await reader.read(); }
    catch (error) {
      if (error instanceof APIError) throw error;
      throw new APIError(400, 'The compressed JSON body could not be decoded.');
    }
    const { done, value } = part;
    if (done) break;
    size += value.byteLength;
    if (size > maximum) {
      await reader.cancel();
      throw new APIError(413, 'The upload is too large. Use chunks under 5 MB.');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes)); }
  catch { throw new APIError(400, 'The upload is not valid JSON.'); }
}
