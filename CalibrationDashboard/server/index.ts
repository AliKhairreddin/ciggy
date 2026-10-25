import { assertSameOrigin, cleanCode, enrollmentRateLimit, hash, pairingCode, participantForToken,
  randomToken, reviewerScope, verifyDashboardAccess, type Participant } from './auth.ts';
import { deleteObjects, deleteRecording, findRecording, loadRawRecording, metadata, purgeExpired,
  saveRecording, type RecordingRow } from './store.ts';
import { APIError, APPLE_EPOCH_MS, cleanAlias, object, readJSON, RETENTION_DAYS,
  UUID, validateAnnotations, validateRecording, type Annotation } from './validation.ts';
import { validateNativeUploadWindow } from './validation.ts';
import { summarizeRecording } from '../public/timeline.js';
import { listDeliveryReports, saveDeliveryReport } from './delivery.ts';
import { handleLeague, purgeLeague } from './league.ts';

type Authenticator = (request: Request, env: Env) => Promise<string>;
const DAY = 86400000;
function json(value: unknown, status = 200): Response { return Response.json(value, { status }); }
function secure(response: Response): Response {
  const headers = new Headers(response.headers);
  const isHTML = headers.get('Content-Type')?.includes('text/html') && response.body !== null;
  // Radix dialogs create a scroll-lock stylesheet. Authorize only styles carrying
  // this response's random nonce, without allowing arbitrary inline styles/scripts.
  const nonce = isHTML ? btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16)))) : null;
  headers.set('Cache-Control', 'no-store');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Content-Security-Policy', `default-src 'self'; script-src 'self'; style-src 'self'${nonce ? ` 'nonce-${nonce}'` : ''}; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`);
  headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  const secured = new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  return nonce ? new HTMLRewriter().on('head', {
    element(element) { element.append(`<meta name="csp-style-nonce" content="${nonce}">`, { html: true }); },
  }).transform(secured) : secured;
}
function identifier(value: string): string {
  if (!UUID.test(value)) throw new APIError(400, 'Invalid recording identifier.');
  return value.toLowerCase();
}

async function enroll(request: Request, env: Env): Promise<Response> {
  assertSameOrigin(request, env);
  await enrollmentRateLimit(request, env);
  const body = object(await readJSON(request, 4096)), codeHash = await hash(cleanCode(body.code));
  const alias = cleanAlias(body.alias);
  const id = crypto.randomUUID(), token = randomToken(), tokenHash = await hash(token), now = Date.now();
  const results = await env.DB.batch([
    env.DB.prepare(`INSERT INTO participants(id, alias, owner_email, token_hash, kind, created_at, expires_at)
      SELECT ?1, COALESCE(alias, ?2), owner_email, ?3, 'app', ?4, ?5 FROM pairing_codes
      WHERE code_hash = ?6 AND expires_at > ?4 AND consumed_by IS NULL`)
      .bind(id, alias, tokenHash, now, now + 30 * DAY, codeHash),
    env.DB.prepare(`UPDATE pairing_codes SET consumed_by = ?1 WHERE code_hash = ?2
      AND consumed_by IS NULL AND EXISTS (SELECT 1 FROM participants WHERE id = ?1)`)
      .bind(id, codeHash),
  ]);
  if (results[0].meta.changes !== 1) throw new APIError(401, 'This pairing code is invalid, expired, or already used.');
  return json({ participantID: id, token, expiresAt: new Date(now + 30 * DAY).toISOString(), retentionDays: RETENTION_DAYS }, 201);
}

async function pairing(request: Request, env: Env, email: string): Promise<Response> {
  assertSameOrigin(request, env, true);
  const body = object(await readJSON(request, 4096));
  const alias = body.alias == null || body.alias === '' ? null : cleanAlias(body.alias);
  const code = pairingCode(), expires = Date.now() + 15 * 60000;
  await env.DB.prepare('INSERT INTO pairing_codes(code_hash, owner_email, alias, expires_at) VALUES (?1, ?2, ?3, ?4)')
    .bind(await hash(code), email, alias, expires).run();
  return json({ code: code.match(/.{4}/g)!.join('-'), expiresAt: new Date(expires).toISOString() }, 201);
}

async function deleteParticipant(request: Request, env: Env): Promise<Response> {
  assertSameOrigin(request, env);
  const participant = await participantForToken(request, env, true), now = Date.now();
  await env.DB.prepare("UPDATE participants SET revoked_at = COALESCE(revoked_at, ?1), alias = 'Deleted participant', expires_at = MIN(expires_at, ?2) WHERE id = ?3")
    .bind(now, now + 14 * DAY, participant.id).run();
  const rows = await env.DB.prepare('SELECT object_key FROM recordings WHERE participant_id = ?1')
    .bind(participant.id).all<{ object_key: string }>();
  if (rows.results.length) await deleteObjects(env, rows.results.map(row => row.object_key));
  await env.DB.prepare('DELETE FROM recordings WHERE participant_id = ?1').bind(participant.id).run();
  await env.DB.prepare('DELETE FROM delivery_reports WHERE participant_id = ?1').bind(participant.id).run();
  return json({ deleted: true, revoked: true });
}

async function listRecordings(request: Request, env: Env, email: string): Promise<Response> {
  const params = new URL(request.url).searchParams, now = Date.now();
  const from = params.has('from') ? Date.parse(params.get('from')!) : now - RETENTION_DAYS * DAY;
  const to = params.has('to') ? Date.parse(params.get('to')!) : now + 300000;
  if (!Number.isFinite(from) || !Number.isFinite(to) || from > to) throw new APIError(400, 'Choose a valid date range.');
  const participant = params.has('participant') ? identifier(params.get('participant')!) : null;
  const limit = params.has('limit') ? Number(params.get('limit')) : 100;
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new APIError(400, 'Page size must be between 1 and 200.');
  let cursorTime: number | null = null, cursorID: string | null = null;
  if (params.has('cursor')) {
    try {
      const cursor = object(JSON.parse(atob(params.get('cursor')!)));
      if (typeof cursor.t !== 'number' || !Number.isFinite(cursor.t) || typeof cursor.id !== 'string') throw new Error();
      cursorTime = cursor.t; cursorID = identifier(cursor.id);
    } catch { throw new APIError(400, 'Invalid page cursor.'); }
  }
  const { results } = await env.DB.prepare(`SELECT r.*, p.alias FROM recordings r JOIN participants p ON p.id = r.participant_id
    WHERE p.owner_email = ?1 AND p.revoked_at IS NULL AND r.state = 'ready' AND r.expires_at > ?2
      AND r.ended_at >= ?3 AND r.started_at <= ?4 AND (?5 IS NULL OR r.participant_id = ?5)
      AND (?6 IS NULL OR r.started_at < ?6 OR (r.started_at = ?6 AND r.id < ?7))
    ORDER BY r.started_at DESC, r.id DESC LIMIT ?8`)
    .bind(email, now, (from - APPLE_EPOCH_MS) / 1000, (to - APPLE_EPOCH_MS) / 1000,
      participant, cursorTime, cursorID, limit + 1).all<RecordingRow>();
  const page = results.slice(0, limit), last = page.at(-1);
  return json({ recordings: page.map(metadata),
    nextCursor: results.length > limit && last ? btoa(JSON.stringify({ t: last.started_at, id: last.id })) : null });
}

async function importRecording(request: Request, env: Env, email: string): Promise<Response> {
  assertSameOrigin(request, env, true);
  const body = object(await readJSON(request));
  const alias = cleanAlias(body.participant), recording = validateRecording(body.recording);
  const annotations = validateAnnotations(body.annotations ?? [], recording);
  const proposed = crypto.randomUUID(), now = Date.now();
  await env.DB.prepare(`INSERT OR IGNORE INTO participants(id, alias, owner_email, kind, created_at, expires_at)
    VALUES (?1, ?2, ?3, 'import', ?4, ?5)`).bind(proposed, alias, email, now, now + 30 * DAY).run();
  const participant = await env.DB.prepare("SELECT id, alias, owner_email, created_at, expires_at, revoked_at FROM participants WHERE owner_email = ?1 AND alias = ?2 AND kind = 'import' AND revoked_at IS NULL")
    .bind(email, alias).first<Participant>();
  if (!participant) throw new APIError(503, 'The participant could not be saved. Try again.');
  return json(await saveRecording(env, participant, recording, annotations), 201);
}

export function createApp(authenticateDashboard: Authenticator = verifyDashboardAccess) {
  return {
    async fetch(request: Request, env: Env, _context: ExecutionContext): Promise<Response> {
      try {
        const { pathname } = new URL(request.url), method = request.method;
        let response: Response;
        if (pathname === '/api/league' || pathname.startsWith('/api/league/')) response = await handleLeague(request, env);
        else if (pathname === '/api/enroll' && method === 'POST') response = await enroll(request, env);
        else if (pathname === '/api/upload' && method === 'POST') {
          assertSameOrigin(request, env);
          const participant = await participantForToken(request, env);
          const now = Date.now();
          // Source-age failures use 410 even when a queued file is older than the
          // reviewer's import window, so the app can discard it permanently.
          if (request.headers.get('X-Ciggy-Payload') === 'delivery-status') {
            response = await saveDeliveryReport(request, env, participant);
          } else {
            const recording = validateRecording(await readJSON(request), now, Infinity);
            validateNativeUploadWindow(recording, participant.created_at, now);
            response = json(await saveRecording(env, participant, recording), 201);
          }
        } else if (pathname === '/api/participant' && method === 'DELETE') response = await deleteParticipant(request, env);
        else {
          // All browsing, raw downloads and reviewer mutations fail closed.
          let email: string;
          try { email = await authenticateDashboard(request, env); }
          catch (error) {
            const isAPI = pathname === '/api' || pathname.startsWith('/api/');
            if (error instanceof APIError && [401, 403].includes(error.status) &&
                !isAPI && pathname !== '/login' && (method === 'GET' || method === 'HEAD')) {
              // Fixed same-origin destination; never trust returnTo/redirect query parameters.
              return secure(new Response(null, { status: 303, headers: { Location: '/login' } }));
            }
            throw error;
          }
          const scope = reviewerScope(email, env);
          if (pathname === '/login' && (method === 'GET' || method === 'HEAD')) {
            response = new Response(null, { status: 303, headers: { Location: '/' } });
          } else if (pathname === '/api/session' && method === 'GET') response = json({ email, retentionDays: RETENTION_DAYS });
          else if (pathname === '/api/delivery' && method === 'GET') response = await listDeliveryReports(env, scope);
          else if (pathname === '/api/pairing' && method === 'POST') response = await pairing(request, env, scope);
          else if (pathname === '/api/import' && method === 'POST') response = await importRecording(request, env, scope);
          else if (pathname === '/api/recordings' && method === 'GET') response = await listRecordings(request, env, scope);
          else if (/^\/api\/participants\/[^/]+$/.test(pathname) && method === 'PATCH') {
            assertSameOrigin(request, env, true);
            const id = identifier(pathname.split('/').at(-1)!), body = object(await readJSON(request, 4096));
            const alias = cleanAlias(body.alias);
            const result = await env.DB.prepare('UPDATE participants SET alias = ?1 WHERE id = ?2 AND owner_email = ?3 AND revoked_at IS NULL')
              .bind(alias, id, scope).run();
            if (!result.meta.changes) throw new APIError(404, 'Participant unavailable.');
            response = json({ participantID: id, participant: alias });
          } else if (/^\/api\/recordings\/[^/]+(?:\/(?:labels|overview))?$/.test(pathname)) {
            const parts = pathname.split('/'), id = identifier(parts[3]);
            const row = await findRecording(env, id, scope);
            if (parts[4] === 'overview' && method === 'GET') {
              // Existing recordings are summarized once, then reused. A failed
              // source read never replaces saved evidence with an empty chart.
              const overview = row.overview_json ? JSON.parse(row.overview_json) : summarizeRecording(await loadRawRecording(env, row));
              if (!row.overview_json) await env.DB.prepare("UPDATE recordings SET overview_json = ?1 WHERE id = ?2 AND state = 'ready' AND overview_json IS NULL")
                .bind(JSON.stringify(overview), id).run();
              response = json({ ...metadata(row), overview, annotations: JSON.parse(row.annotations_json) as Annotation[] });
            } else if (parts[4] === 'labels' && method === 'PUT') {
              assertSameOrigin(request, env, true);
              const body = object(await readJSON(request, 1024 * 1024));
              if (!Number.isSafeInteger(body.expectedRevision) || body.expectedRevision !== row.label_revision) {
                throw new APIError(409, 'These labels changed elsewhere. Reload this recording before saving.');
              }
              const raw = await loadRawRecording(env, row), annotations = validateAnnotations(body.annotations, raw);
              const result = await env.DB.prepare(`UPDATE recordings SET annotations_json = ?1, label_revision = label_revision + 1
                WHERE id = ?2 AND label_revision = ?3 AND state = 'ready' AND expires_at > ?4`)
                .bind(JSON.stringify(annotations), id, row.label_revision, Date.now()).run();
              if (!result.meta.changes) throw new APIError(409, 'This recording changed while you were editing. Reload before saving.');
              response = json({ annotations, labelRevision: row.label_revision + 1 });
            } else if (parts.length === 4 && method === 'GET') {
              const recording = await loadRawRecording(env, row);
              response = json({ id, participantID: row.participant_id, participant: row.alias,
                recording, annotations: JSON.parse(row.annotations_json) as Annotation[], labelRevision: row.label_revision,
                importedAt: new Date(row.created_at).toISOString(), expiresAt: new Date(row.expires_at).toISOString() });
            } else if (parts.length === 4 && method === 'DELETE') {
              assertSameOrigin(request, env, true);
              await deleteRecording(env, row);
              response = json({ deleted: true });
            } else throw new APIError(405, 'This method is not supported.');
          } else if (pathname.startsWith('/api/')) throw new APIError(404, 'API route not found.');
          else if (method === 'GET' || method === 'HEAD') response = await env.ASSETS.fetch(request);
          else throw new APIError(405, 'This method is not supported.');
        }
        return secure(response);
      } catch (error) {
        if (error instanceof APIError) {
          const response = json({ error: error.message }, error.status);
          if (error.retryAfter) response.headers.set('Retry-After', String(error.retryAfter));
          return secure(response);
        }
        // Never log raw samples, aliases, pairing codes, tokens, or request bodies.
        return secure(json({ error: 'The Ciggy service is temporarily unavailable. Please retry.' }, 503));
      }
    },
    async scheduled(_controller: ScheduledController, env: Env, _context: ExecutionContext): Promise<void> {
      await purgeExpired(env);
      await purgeLeague(env);
    }
  };
}

export default createApp();
