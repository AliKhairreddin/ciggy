import { APIError, object, readJSON } from './validation.ts';
import type { Participant } from './auth.ts';

const DAY = 86400000;
function date(value: unknown, now: number, future = false): number | null {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 978307200000 || value > now + (future ? 7 * DAY : 300000)) {
    throw new APIError(400, 'Invalid delivery timestamp.');
  }
  return value;
}
function count(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 100000) throw new APIError(400, 'Invalid queue count.');
  return value;
}
function build(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== 'string' || !/^[a-zA-Z0-9. -]{1,32}$/.test(value)) throw new APIError(400, 'Invalid build.');
  return value;
}

export async function saveDeliveryReport(request: Request, env: Env, participant: Participant): Promise<Response> {
  const now = Date.now(), input = object(await readJSON(request, 8192));
  if (input.kind !== 'deliveryStatus') throw new APIError(400, 'Invalid delivery report.');
  const observedAt = date(input.observedAt, now), consentAt = date(input.consentAt, now);
  if (observedAt == null || consentAt == null || consentAt < participant.created_at || consentAt > observedAt || observedAt < now - 14 * DAY) {
    throw new APIError(400, 'Invalid delivery report period.');
  }
  let watch = null;
  if (input.watch != null) {
    const w = object(input.watch);
    watch = { checkedAt: date(w.checkedAt, observedAt), latestQueuedMotionAt: date(w.latestQueuedMotionAt, observedAt),
      queuedTransferCount: count(w.queuedTransferCount), pendingWindowCount: count(w.pendingWindowCount),
      nextBatchAt: date(w.nextBatchAt, observedAt, true), lastBatchAt: date(w.lastBatchAt, observedAt),
      lastDeliveredAt: date(w.lastDeliveredAt, observedAt), build: build(w.build) };
  }
  // Construct an allowlisted payload; unknown keys, error strings and tokens
  // never become part of saved diagnostics.
  const report = { observedAt, consentAt, phoneBuild: build(input.phoneBuild),
    phoneLastReceivedAt: date(input.phoneLastReceivedAt, observedAt), phoneLastUploadedAt: date(input.phoneLastUploadedAt, observedAt),
    phonePendingCount: count(input.phonePendingCount), phoneScheduledCount: count(input.phoneScheduledCount),
    phoneRetryAt: date(input.phoneRetryAt, observedAt, true), watch };
  await env.DB.prepare(`INSERT INTO delivery_reports(participant_id, observed_at, received_at, expires_at, report_json)
    SELECT ?1, ?2, ?3, ?4, ?5 WHERE EXISTS (SELECT 1 FROM participants WHERE id = ?1 AND revoked_at IS NULL AND expires_at > ?3)
    ON CONFLICT(participant_id) DO UPDATE SET observed_at=excluded.observed_at, received_at=excluded.received_at,
    expires_at=excluded.expires_at, report_json=excluded.report_json WHERE excluded.observed_at > delivery_reports.observed_at`)
    .bind(participant.id, observedAt, now, observedAt + 14 * DAY, JSON.stringify(report)).run();
  return Response.json({ saved: true });
}

export async function listDeliveryReports(env: Env, scope: string): Promise<Response> {
  const now = Date.now();
  const { results } = await env.DB.prepare(`SELECT p.id, p.alias, d.report_json, d.received_at FROM participants p
    LEFT JOIN delivery_reports d ON d.participant_id=p.id AND d.expires_at>?2
    WHERE p.owner_email=?1 AND p.kind='app' AND p.revoked_at IS NULL AND p.expires_at>?2 ORDER BY p.alias LIMIT 100`)
    .bind(scope, now).all<{ id: string; alias: string; report_json: string | null; received_at: number | null }>();
  return Response.json({ participants: results.map(row => ({ participantID: row.id, participant: row.alias,
    receivedAt: row.received_at, report: row.report_json ? JSON.parse(row.report_json) : null })) });
}
