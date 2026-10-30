import { assertSameOrigin } from './auth.ts';
import { APIError, object, readJSON, UUID } from './validation.ts';

const DAY = 86400000;
const reasons = ['unknown', 'no-uploaded-motion', 'motion-present', 'watch-not-tracking'];

export async function handleFeedback(request: Request, env: Env, scope: string): Promise<Response> {
  const now = Date.now(), url = new URL(request.url);
  if (request.method === 'GET') {
    const from = Date.parse(url.searchParams.get('from') ?? ''), to = Date.parse(url.searchParams.get('to') ?? '');
    if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) throw new APIError(400, 'Choose a valid feedback period.');
    const participant = url.searchParams.get('participant');
    if (participant && !UUID.test(participant)) throw new APIError(400, 'Choose a tester.');
    const rows = await env.DB.prepare(`SELECT f.body_json, f.created_at, f.expires_at FROM review_feedback f
      JOIN participants p ON p.id = f.participant_id WHERE p.owner_email = ?1 AND p.revoked_at IS NULL
      AND f.deleted_at IS NULL AND f.expires_at > ?2 AND f.ended_at >= ?3 AND f.started_at <= ?4
      AND (?5 IS NULL OR p.id = ?5) ORDER BY f.started_at DESC LIMIT 1001`)
      .bind(scope, now, from, to, participant).all<{ body_json: string; created_at: number; expires_at: number }>();
    if (rows.results.length > 1000) throw new APIError(400, 'Choose a shorter feedback period or one tester.');
    return Response.json({ feedback: rows.results.map(row => ({ ...JSON.parse(row.body_json), createdAt: row.created_at, expiresAt: row.expires_at })) });
  }
  assertSameOrigin(request, env, true);
  if (request.method === 'DELETE') {
    const id = url.pathname.split('/').at(-1)!;
    if (!UUID.test(id)) throw new APIError(400, 'Invalid feedback identifier.');
    await env.DB.prepare(`UPDATE review_feedback SET body_json = '{}', started_at = 0, ended_at = 0, deleted_at = ?3 WHERE id = ?1 AND participant_id IN
      (SELECT id FROM participants WHERE owner_email = ?2 AND revoked_at IS NULL)`).bind(id, scope, now).run();
    return Response.json({ deleted: true });
  }
  if (request.method !== 'POST' || url.pathname !== '/api/review-feedback') throw new APIError(405, 'This method is not supported.');
  const body = object(await readJSON(request, 8192));
  if (typeof body.id !== 'string' || !UUID.test(body.id) || typeof body.participantID !== 'string' || !UUID.test(body.participantID)
      || typeof body.start !== 'number' || typeof body.end !== 'number' || !Number.isFinite(body.start) || !Number.isFinite(body.end)
      || body.start >= body.end || body.end - body.start > DAY || body.start < now - 14 * DAY || body.end > now + 300000
      || !Number.isInteger(body.missedCount) || Number(body.missedCount) < 1 || Number(body.missedCount) > 100
      || typeof body.reason !== 'string' || !reasons.includes(body.reason)
      || typeof body.notes !== 'string' || body.notes.length > 2000
      || (body.reviewID != null && (typeof body.reviewID !== 'string' || !UUID.test(body.reviewID)))) {
    throw new APIError(400, 'Choose a recent interval of up to 24 hours, 1–100 missed cigarettes, and a valid observation.');
  }
  const saved = { id: body.id.toLowerCase(), participantID: body.participantID.toLowerCase(), start: body.start, end: body.end,
    missedCount: body.missedCount, reason: body.reason, notes: body.notes.trim(), reviewID: typeof body.reviewID === 'string' ? body.reviewID.toLowerCase() : null };
  const participant = await env.DB.prepare('SELECT id FROM participants WHERE id = ?1 AND owner_email = ?2 AND revoked_at IS NULL')
    .bind(saved.participantID, scope).first();
  if (!participant) throw new APIError(404, 'This tester is unavailable.');
  const text = JSON.stringify(saved);
  await env.DB.prepare(`INSERT OR IGNORE INTO review_feedback(id, participant_id, started_at, ended_at, body_json, created_at, expires_at)
    SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7 WHERE EXISTS
      (SELECT 1 FROM participants WHERE id = ?2 AND owner_email = ?8 AND revoked_at IS NULL)
    AND (SELECT COUNT(*) FROM review_feedback WHERE participant_id = ?2 AND expires_at > ?6) < 500`)
    .bind(saved.id, saved.participantID, saved.start, saved.end, text, now, now + 14 * DAY, scope).run();
  const row = await env.DB.prepare(`SELECT body_json, expires_at FROM review_feedback WHERE id = ?1 AND participant_id = ?2
    AND EXISTS (SELECT 1 FROM participants WHERE id = ?2 AND owner_email = ?3 AND revoked_at IS NULL)`)
    .bind(saved.id, saved.participantID, scope).first<{ body_json: string; expires_at: number }>();
  if (!row) throw new APIError(429, 'Feedback could not be saved. The tester may be unavailable or have reached the feedback limit.', 3600);
  if (row.body_json !== text) throw new APIError(409, 'This feedback ID already has a different observation.');
  if (row.expires_at <= now) throw new APIError(410, 'This feedback has expired.');
  return Response.json({ saved: true, id: saved.id }, { status: 201 });
}
