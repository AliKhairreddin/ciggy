import { hash, type Participant } from './auth.ts';
import { APIError, appleDateISO, RETENTION_DAYS, type Annotation, type Recording } from './validation.ts';
import { summarizeRecording } from '../public/timeline.js';

export type RecordingRow = {
  id: string; participant_id: string; recording_id: string; object_key: string; body_hash: string;
  started_at: number; ended_at: number; sample_count: number; sources_json: string;
  annotations_json: string; label_revision: number; state: 'pending' | 'ready' | 'deleted'; created_at: number; expires_at: number;
  alias?: string; owner_email?: string;
  overview_json?: string | null;
};

export function metadata(row: RecordingRow) {
  return { id: row.id, recordingID: row.recording_id, participantID: row.participant_id,
    participant: row.alias, startedAt: appleDateISO(row.started_at), endedAt: appleDateISO(row.ended_at),
    sampleCount: row.sample_count, sources: JSON.parse(row.sources_json) as string[],
    annotationCount: (JSON.parse(row.annotations_json) as Annotation[]).length,
    labelRevision: row.label_revision,
    importedAt: new Date(row.created_at).toISOString(), expiresAt: new Date(row.expires_at).toISOString() };
}

/** The 8192/72h device budget covers minute-long foreground fragments, five-minute
 * history, and bounded gap reconciliation. Deleted reservations still count.
 * Reserve metadata first. Retries resume a pending upload using the same canonical
 * bytes; a reused UUID with different motion cannot overwrite good data. */
export async function saveRecording(env: Env, participant: Participant, recording: Recording, annotations: Annotation[] = []) {
  const now = Date.now(), text = JSON.stringify(recording), digest = await hash(text);
  const proposedID = crypto.randomUUID(), objectKey = `${participant.id}/${recording.id}.json`;
  const sources = [...new Set(recording.samples.map(sample => sample.source))];
  await env.DB.prepare(`INSERT OR IGNORE INTO recordings
    (id, participant_id, recording_id, object_key, body_hash, started_at, ended_at, sample_count,
     sources_json, annotations_json, state, created_at, expires_at)
    SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'pending', ?11, ?12
    WHERE (SELECT COUNT(*) FROM recordings WHERE participant_id = ?2 AND created_at >= ?13) < 8192
      AND EXISTS (SELECT 1 FROM participants WHERE id = ?2 AND revoked_at IS NULL AND expires_at > ?11)`)
    .bind(proposedID, participant.id, recording.id, objectKey, digest, recording.startedAt,
      recording.endedAt, recording.samples.length, JSON.stringify(sources), JSON.stringify(annotations),
      now, now + RETENTION_DAYS * 86400000, now - 72 * 3600000).run();
  const row = await env.DB.prepare('SELECT * FROM recordings WHERE participant_id = ?1 AND recording_id = ?2')
    .bind(participant.id, recording.id).first<RecordingRow>();
  if (!row) throw new APIError(429, 'The device upload limit has been reached. Saved data is unchanged.', 3600);
  if (row.state === 'deleted') return { id: row.id, recordingID: row.recording_id, duplicate: true,
    deleted: true, expiresAt: new Date(row.expires_at).toISOString() };
  if (row.body_hash !== digest) throw new APIError(409, 'This recording ID already belongs to different motion data.');
  if (row.state === 'ready') return { id: row.id, recordingID: row.recording_id, duplicate: true,
    expiresAt: new Date(row.expires_at).toISOString() };
  await env.RECORDINGS.put(objectKey, text, { httpMetadata: { contentType: 'application/json' } });
  const result = await env.DB.prepare(`UPDATE recordings SET state = 'ready', overview_json = ?4
    WHERE id = ?1 AND state = 'pending' AND EXISTS
    (SELECT 1 FROM participants WHERE id = ?2 AND revoked_at IS NULL AND expires_at > ?3)`)
    .bind(row.id, participant.id, now, JSON.stringify(summarizeRecording(recording))).run();
  if (!result.meta.changes) {
    // A deletion/revocation won a race with the object write. Do not publish it.
    const latest = await env.DB.prepare('SELECT state FROM recordings WHERE id = ?1').bind(row.id).first<{ state: string }>();
    if (latest?.state !== 'ready') {
      await env.DB.prepare('UPDATE recordings SET raw_deleted_at = NULL WHERE id = ?1').bind(row.id).run();
      await env.RECORDINGS.delete(objectKey);
      await env.DB.prepare("UPDATE recordings SET raw_deleted_at = ?1 WHERE id = ?2 AND state = 'deleted'")
        .bind(Date.now(), row.id).run();
      throw new APIError(409, 'This recording was deleted or the device connection was revoked.');
    }
  }
  return { id: row.id, recordingID: row.recording_id, duplicate: row.id !== proposedID,
    expiresAt: new Date(row.expires_at).toISOString() };
}

export async function findRecording(env: Env, id: string, email?: string, participantID?: string): Promise<RecordingRow> {
  const row = await env.DB.prepare(`SELECT r.*, p.alias, p.owner_email FROM recordings r
    JOIN participants p ON p.id = r.participant_id WHERE r.id = ?1
    AND r.state = 'ready' AND r.expires_at > ?2 AND p.revoked_at IS NULL
    AND ((?3 IS NOT NULL AND p.owner_email = ?3) OR (?4 IS NOT NULL AND p.id = ?4))`)
    .bind(id, Date.now(), email ?? null, participantID ?? null).first<RecordingRow>();
  if (!row) throw new APIError(404, 'This recording is unavailable or has expired.');
  return row;
}

export async function loadRawRecording(env: Env, row: RecordingRow): Promise<Recording> {
  const raw = await env.RECORDINGS.get(row.object_key);
  if (!raw) throw new APIError(503, 'The saved motion file is temporarily unavailable. Its labels are preserved.');
  // All stored objects were bounded and validated before insertion.
  return raw.json<Recording>();
}

export async function deleteRecording(env: Env, row: RecordingRow): Promise<void> {
  // Keep a short-lived tombstone so a delayed app retry cannot restore a deletion.
  await env.DB.prepare("UPDATE recordings SET state = 'deleted', annotations_json = '[]', overview_json = NULL WHERE id = ?1")
    .bind(row.id).run();
  await env.RECORDINGS.delete(row.object_key);
  await env.DB.prepare('UPDATE recordings SET raw_deleted_at = ?1 WHERE id = ?2').bind(Date.now(), row.id).run();
}

export async function deleteObjects(env: Env, keys: string[]): Promise<void> {
  for (let start = 0; start < keys.length; start += 1000) {
    await env.RECORDINGS.delete(keys.slice(start, start + 1000));
  }
}

export async function purgeExpired(env: Env): Promise<void> {
  const now = Date.now();
  const { results } = await env.DB.prepare(`SELECT r.id, r.object_key, r.state, r.expires_at, p.revoked_at FROM recordings r
    JOIN participants p ON p.id = r.participant_id
    WHERE r.expires_at <= ?1 OR (r.state = 'deleted' AND r.raw_deleted_at IS NULL)
      OR p.revoked_at IS NOT NULL ORDER BY r.expires_at LIMIT 1000`)
    .bind(now).all<Pick<RecordingRow, 'id' | 'object_key' | 'state' | 'expires_at'> & { revoked_at: number | null }>();
  if (results.length) {
    await deleteObjects(env, results.map(row => row.object_key));
    // Two bulk statements stay below D1's Free-plan query budget even for a
    // thousand expired chunks. Delete only objects whose cleanup just succeeded.
    await env.DB.prepare(`UPDATE recordings SET state = 'deleted', annotations_json = '[]', overview_json = NULL, raw_deleted_at = ?1
      WHERE id IN (SELECT value FROM json_each(?2))`)
      .bind(now, JSON.stringify(results.map(row => row.id))).run();
    const remove = results.filter(row => row.expires_at <= now || row.revoked_at !== null);
    if (remove.length) {
      await env.DB.prepare('DELETE FROM recordings WHERE id IN (SELECT value FROM json_each(?1))')
        .bind(JSON.stringify(remove.map(row => row.id))).run();
    }
  }
  await env.DB.batch([
    env.DB.prepare('DELETE FROM pairing_codes WHERE expires_at <= ?1').bind(now),
    env.DB.prepare('DELETE FROM request_limits WHERE expires_at <= ?1').bind(now),
    env.DB.prepare(`DELETE FROM participants WHERE expires_at <= ?1
      AND NOT EXISTS (SELECT 1 FROM recordings WHERE participant_id = participants.id)`).bind(now),
  ]);
}
