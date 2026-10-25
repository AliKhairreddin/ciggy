import { assertSameOrigin, hash } from './auth.ts';
import { APIError, object, readJSON, UUID } from './validation.ts';

const DAY = 86400000;
const MEMBERSHIP_DAYS = 90;
const ALIASES = ['Ashtray Accountant', 'Filter Philosopher', 'Breakroom Baron', 'Receipt Collector',
  'Lighter Librarian', 'Paperwork Royalty', 'Pocket Auditor', 'Fine Print Fan'];
type Member = { id: string; alias: string; joined_at: number; expires_at: number; revoked_at: number | null };
type Entry = { id: string; alias: string; score: number; rank: number | null; updated_at: number | null };
type Ranked = Entry & { position: number; total: number };
type Score = { count: number; revision: number; updated_at: number };

/** Weekly totals use identical UTC boundaries on every device. */
export function leagueSeason(now: number, previous = false) {
  const midnight = Math.floor(now / DAY) * DAY;
  const start = midnight - ((new Date(midnight).getUTCDay() + 6) % 7) * DAY - (previous ? 7 * DAY : 0);
  return { start, end: start + 7 * DAY };
}
function dayString(now: number): string { return new Date(now).toISOString().slice(0, 10); }
function publicMember(member: Member) {
  return { id: member.id, alias: member.alias, joinedAt: new Date(member.joined_at).toISOString() };
}
function publicEntry(entry: Entry) {
  return { id: entry.id, alias: entry.alias, score: entry.score, rank: entry.rank,
    updatedAt: entry.updated_at === null ? null : new Date(entry.updated_at).toISOString() };
}
function token(request: Request, required = true): string | null {
  const header = request.headers.get('authorization');
  if (!header && !required) return null;
  const value = header?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
  if (!value) throw new APIError(401, 'Join the Ashtray League to use this action.');
  return value;
}
async function memberForToken(request: Request, env: Env, now: number, required = true) {
  const value = token(request, required);
  if (!value) return null;
  const member = await env.DB.prepare('SELECT id, alias, joined_at, expires_at, revoked_at FROM league_members WHERE token_hash = ?1')
    .bind(await hash(`league:${value}`)).first<Member>();
  if (!member || member.revoked_at !== null || member.expires_at <= now) {
    throw new APIError(401, 'This league membership has expired or was removed.');
  }
  return member;
}

/** Fixed windows are shared across Worker instances. Only windowed IP digests
 * are saved; neither raw IPs nor bearer credentials enter D1 or application logs. */
async function rateLimit(request: Request, env: Env, now: number, kind: string, maximum: number, interval: number) {
  const window = Math.floor(now / interval), reset = (window + 1) * interval;
  const key = await hash(`league:${kind}:${window}:${request.headers.get('cf-connecting-ip') ?? 'unknown'}`);
  const row = await env.DB.prepare(`INSERT INTO request_limits(key, count, expires_at) VALUES (?1, 1, ?2)
    ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count`)
    .bind(key, reset).first<{ count: number }>();
  if (!row || row.count > maximum) throw new APIError(429, 'The league is taking a short break. Try again soon.', Math.max(1, Math.ceil((reset - now) / 1000)));
}

async function join(request: Request, env: Env, now: number): Promise<Response> {
  const value = token(request)!, body = object(await readJSON(request, 1024));
  if (typeof body.memberID !== 'string' || !UUID.test(body.memberID)) throw new APIError(400, 'A valid league membership identifier is required.');
  const id = body.memberID.toLowerCase(), digest = await hash(`league:${value}`);
  const existing = await env.DB.prepare('SELECT id, alias, joined_at, expires_at, revoked_at FROM league_members WHERE token_hash = ?1 OR id = ?2')
    .bind(digest, id).all<Member>();
  if (existing.results.length) {
    const member = await memberForToken(request, env, now);
    if (member?.id !== id) throw new APIError(409, 'This membership identifier is already in use.');
    return Response.json(publicMember(member));
  }
  await rateLimit(request, env, now, 'join', 10, DAY);
  // Generated names contain no user-supplied text, avoiding a public moderation surface.
  const alias = `${ALIASES[crypto.getRandomValues(new Uint8Array(1))[0] % ALIASES.length]} #${id.replaceAll('-', '').slice(-8).toUpperCase()}`;
  await env.DB.prepare(`INSERT OR IGNORE INTO league_members(id, token_hash, alias, joined_at, expires_at)
    VALUES (?1, ?2, ?3, ?4, ?5)`).bind(id, digest, alias, now, now + MEMBERSHIP_DAYS * DAY).run();
  const member = await memberForToken(request, env, now);
  if (member?.id !== id) throw new APIError(409, 'This membership identifier is already in use.');
  return Response.json(publicMember(member), { status: 201 });
}

async function saveScore(request: Request, env: Env, now: number): Promise<Response> {
  const member = (await memberForToken(request, env, now))!, body = object(await readJSON(request, 1024));
  const seasonStart = body.seasonStart;
  if (seasonStart !== dayString(leagueSeason(now).start) && seasonStart !== dayString(leagueSeason(now, true).start)) {
    throw new APIError(409, 'Only the current and previous UTC weeks can be synchronized. Reload the league.');
  }
  if (typeof body.count !== 'number' || !Number.isSafeInteger(body.count) || body.count < 0 || body.count > 100000) {
    throw new APIError(400, 'The cigarette total must be a whole number between 0 and 100000.');
  }
  if (typeof body.revision !== 'number' || !Number.isSafeInteger(body.revision) || body.revision < 1) {
    throw new APIError(400, 'A positive, safe score revision is required.');
  }
  // Recheck active membership inside the atomic upsert. Newer revisions replace
  // totals in either direction, so corrections cannot be undone by late retries.
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO league_scores(member_id, season_start, count, revision, updated_at)
      SELECT id, ?1, ?2, ?3, ?4 FROM league_members WHERE id = ?5 AND revoked_at IS NULL AND expires_at > ?4
      ON CONFLICT(member_id, season_start) DO UPDATE SET count = excluded.count,
        revision = excluded.revision, updated_at = excluded.updated_at
      WHERE excluded.revision > league_scores.revision`)
      .bind(seasonStart, body.count, body.revision, now, member.id),
    env.DB.prepare(`UPDATE league_members SET expires_at = ?1
      WHERE id = ?2 AND revoked_at IS NULL AND expires_at > ?3 AND EXISTS (
        SELECT 1 FROM league_scores WHERE member_id = ?2 AND season_start = ?4 AND revision = ?5 AND count = ?6)`)
      .bind(now + MEMBERSHIP_DAYS * DAY, member.id, now, seasonStart, body.revision, body.count),
  ]);
  const score = await env.DB.prepare(`SELECT s.count, s.revision, s.updated_at FROM league_scores s
    JOIN league_members m ON m.id = s.member_id WHERE s.member_id = ?1 AND s.season_start = ?2
    AND m.revoked_at IS NULL AND m.expires_at > ?3`).bind(member.id, seasonStart, now).first<Score>();
  if (!score) throw new APIError(401, 'This league membership has expired or was removed.');
  if (score.revision !== body.revision || score.count !== body.count) {
    throw new APIError(409, 'A newer score revision is already saved. Reconcile your saved total before retrying.');
  }
  return Response.json({ accepted: true, seasonStart, count: score.count, revision: score.revision,
    updatedAt: new Date(score.updated_at).toISOString() });
}

async function leave(request: Request, env: Env, now: number): Promise<Response> {
  const digest = await hash(`league:${token(request)!}`);
  await env.DB.batch([
    // Also tombstone an unknown credential: deletion can beat an in-flight join,
    // and a locally retained credential may outlive server-side expiry cleanup.
    env.DB.prepare(`INSERT INTO league_members(id, token_hash, alias, joined_at, expires_at, revoked_at)
      VALUES (?1, ?2, '', ?3, ?4, ?3) ON CONFLICT(token_hash) DO UPDATE SET
      revoked_at = COALESCE(league_members.revoked_at, excluded.revoked_at), alias = '',
      expires_at = CASE WHEN league_members.revoked_at IS NULL THEN excluded.expires_at ELSE league_members.expires_at END`)
      .bind(crypto.randomUUID(), digest, now, now + MEMBERSHIP_DAYS * DAY),
    env.DB.prepare('DELETE FROM league_scores WHERE member_id IN (SELECT id FROM league_members WHERE token_hash = ?1)').bind(digest),
  ]);
  return Response.json({ deleted: true });
}

async function board(request: Request, env: Env, now: number): Promise<Response> {
  const season = new URL(request.url).searchParams.get('season') ?? 'current';
  if (season !== 'current' && season !== 'previous') throw new APIError(400, 'Choose the current or previous season.');
  const member = await memberForToken(request, env, now, false);
  const { start, end } = leagueSeason(now, season === 'previous');
  // Read saved aggregate totals in one snapshot. Rank uses only score;
  // stable ID order selects top 50 without giving earlier joins a better rank.
  const results = await env.DB.batch<Ranked | Score>([
    env.DB.prepare(`WITH scores AS (
      SELECT m.id, m.alias, s.count AS score, s.updated_at FROM league_members m
      JOIN league_scores s ON s.member_id = m.id
      WHERE m.revoked_at IS NULL AND m.expires_at > ?2 AND s.season_start = ?1 AND s.count > 0
    ), ranked AS (
      SELECT *, RANK() OVER (ORDER BY score DESC) AS rank,
        ROW_NUMBER() OVER (ORDER BY score DESC, id) AS position, COUNT(*) OVER () AS total FROM scores
    ) SELECT * FROM ranked WHERE position <= 50 OR id = ?3 ORDER BY position`)
      .bind(dayString(start), now, member?.id ?? ''),
    env.DB.prepare(`SELECT s.count, s.revision, s.updated_at FROM league_scores s
    JOIN league_members m ON m.id = s.member_id WHERE s.member_id = ?1 AND s.season_start = ?2
    AND m.revoked_at IS NULL AND m.expires_at > ?3`).bind(member?.id ?? '', dayString(start), now),
  ]);
  const rows = results[0].results.filter((row): row is Ranked => 'score' in row);
  const ownScore = results[1].results.find((row): row is Score => 'count' in row);
  const me = member ? rows.find(row => row.id === member.id) ??
    { id: member.id, alias: member.alias, score: ownScore?.count ?? 0, rank: null, updated_at: ownScore?.updated_at ?? null } : null;
  return Response.json({ seasonStart: new Date(start).toISOString(), seasonEnd: new Date(end).toISOString(),
    serverNow: new Date(now).toISOString(), generatedAt: new Date(now).toISOString(),
    entries: rows.filter(row => row.position <= 50).map(publicEntry),
    totalParticipants: rows[0]?.total ?? 0, me: me ? publicEntry(me) : null,
    myRevision: ownScore?.revision ?? null,
    member: member ? publicMember(member) : null });
}

export async function handleLeague(request: Request, env: Env, now = Date.now()): Promise<Response> {
  const path = new URL(request.url).pathname, method = request.method;
  assertSameOrigin(request, env);
  await rateLimit(request, env, now, method === 'GET' ? 'read' : 'write', method === 'GET' ? 120 : 30, 60000);
  if (path === '/api/league' && method === 'GET') return board(request, env, now);
  if (path === '/api/league/join' && method === 'POST') return join(request, env, now);
  if (path === '/api/league/score' && method === 'PUT') return saveScore(request, env, now);
  if (path === '/api/league/membership' && method === 'DELETE') return leave(request, env, now);
  throw new APIError(404, 'League route not found.');
}

export async function purgeLeague(env: Env, now = Date.now()): Promise<void> {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM league_scores WHERE season_start < ?1')
      .bind(dayString(leagueSeason(now, true).start)),
    env.DB.prepare('DELETE FROM league_members WHERE expires_at <= ?1').bind(now),
  ]);
}
