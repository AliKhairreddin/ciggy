import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

const root = fileURLToPath(new URL('../', import.meta.url));
const origin = 'https://ciggy.thatcanadian.dev';
const monday = Date.parse('2026-01-05T00:00:00Z'), day = 86400000;
let temporary, worker, platform, env;

before(async () => {
  temporary = await mkdtemp(join(tmpdir(), 'ciggy-league-api-'));
  const outfile = join(temporary, 'worker.mjs');
  await build({ stdin: { contents: `export { default } from './server/index.ts';
    export * from './server/league.ts'; export { hash, randomToken } from './server/auth.ts';`,
    resolveDir: root, sourcefile: 'test-entry.ts', loader: 'ts' },
    outfile, bundle: true, platform: 'neutral', format: 'esm', target: 'es2023' });
  worker = await import(pathToFileURL(outfile));
  platform = new Miniflare(convertV4MiniflareOptions({ modules: true,
    script: 'export default { fetch() { return new Response("test"); } };',
    compatibilityDate: '2026-10-23', d1Databases: ['DB'], r2Buckets: ['RECORDINGS'] }));
  env = { ...await platform.getBindings(), APP_ORIGIN: origin,
    ACCESS_TEAM_DOMAIN: 'https://ciggy-test.cloudflareaccess.com', ACCESS_AUD: 'test-audience',
    ALLOWED_EMAILS: 'reviewer@example.test', ASSETS: { fetch: async () => new Response('private') } };
  for (const name of (await readdir(join(root, 'migrations'))).filter(name => name.endsWith('.sql')).sort()) {
    const schema = await readFile(join(root, 'migrations', name), 'utf8');
    await env.DB.batch(schema.split(';').map(sql => sql.trim()).filter(Boolean).map(sql => env.DB.prepare(sql)));
  }
});
beforeEach(async () => {
  await env.DB.batch(['league_scores', 'league_members', 'request_limits'].map(table => env.DB.prepare(`DELETE FROM ${table}`)));
});
after(async () => {
  await platform?.dispose();
  if (temporary) await rm(temporary, { recursive: true, force: true });
});
function request(path, method = 'GET', body, person, headers = {}) {
  return new Request(origin + path, { method,
    headers: { 'cf-connecting-ip': person?.ip ?? '192.0.2.1',
      ...(person?.token ? { authorization: `Bearer ${person.token}` } : {}),
      ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
}
async function call(path = '/api/league', method = 'GET', body, person, now = monday, headers = {}) {
  try { return await worker.handleLeague(request(path, method, body, person, headers), env, now); }
  catch (error) {
    if (typeof error.status !== 'number') throw error;
    return Response.json({ error: error.message }, { status: error.status,
      headers: error.retryAfter ? { 'retry-after': String(error.retryAfter) } : {} });
  }
}
async function member(now = monday) {
  const person = { id: crypto.randomUUID(), token: worker.randomToken(), ip: crypto.randomUUID() };
  const response = await call('/api/league/join', 'POST', { memberID: person.id }, person, now);
  assert.equal(response.status, 201);
  return { ...person, ...await response.json() };
}
async function score(person, count = 1, revision = 1, now = monday, seasonStart = '2026-01-05') {
  const response = await call('/api/league/score', 'PUT', { seasonStart, count, revision }, person, now);
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
}

test('membership is explicit, idempotent, pseudonymous and stores domain-separated token hashes', async () => {
  const empty = await (await call()).json();
  assert.deepEqual(empty.entries, []);
  assert.equal(empty.me, null);
  assert.equal(empty.member, null);
  assert.equal(empty.totalParticipants, 0);
  const person = await member();
  assert.match(person.alias, / #[A-F0-9]{8}$/);
  const retry = await call('/api/league/join', 'POST', { memberID: person.id }, person);
  assert.equal(retry.status, 200);
  assert.equal((await retry.json()).alias, person.alias);
  const saved = await env.DB.prepare('SELECT * FROM league_members').all();
  assert.equal(saved.results.length, 1);
  assert.equal(saved.results[0].token_hash, await worker.hash(`league:${person.token}`));
  assert.equal(JSON.stringify(saved).includes(person.token), false);
  const board = await (await call('/api/league', 'GET', undefined, person)).json();
  assert.equal(board.me.score, 0);
  assert.equal(board.me.rank, null);
  assert.equal(board.me.updatedAt, null);
  assert.equal(board.myRevision, null);
  assert.equal(board.totalParticipants, 0);
  assert.equal(board.member.id, person.id);
});

test('concurrent exact retries are idempotent and newer corrections can lower or clear a total', async () => {
  const person = await member();
  await Promise.all(Array.from({ length: 8 }, () => score(person, 24, 1)));
  await score(person, 12, 2);
  for (const payload of [{ count: 24, revision: 1 }, { count: 13, revision: 2 }]) {
    const stale = await call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', ...payload }, person);
    assert.equal(stale.status, 409);
  }
  const board = await (await call('/api/league', 'GET', undefined, person)).json();
  assert.equal(board.me.score, 12);
  assert.equal(board.me.rank, 1);
  assert.equal(board.myRevision, 2);
  assert.equal(board.me.updatedAt, '2026-01-05T00:00:00.000Z');
  await score(person, 0, 3);
  const zero = await (await call('/api/league', 'GET', undefined, person)).json();
  assert.equal(zero.me.score, 0);
  assert.equal(zero.me.rank, null);
  assert.equal(zero.entries.length, 0);
  assert.equal(zero.totalParticipants, 0);
});

test('UTC Monday resets the board and previous-week corrections remain possible', async () => {
  assert.deepEqual(worker.leagueSeason(monday - 1), { start: monday - 7 * day, end: monday });
  assert.deepEqual(worker.leagueSeason(monday), { start: monday, end: monday + 7 * day });
  const person = await member();
  await score(person, 42);
  const reset = await (await call('/api/league', 'GET', undefined, person, monday + 7 * day)).json();
  assert.equal(reset.me.score, 0);
  assert.equal(reset.seasonStart, '2026-01-12T00:00:00.000Z');
  await score(person, 40, 2, monday + 7 * day);
  const previous = await (await call('/api/league?season=previous', 'GET', undefined, person, monday + 7 * day)).json();
  assert.equal(previous.me.score, 40);
  assert.equal((await call('/api/league?season=all')).status, 400);
  for (const seasonStart of ['2026-01-04', '2026-01-12', '2025-12-22']) {
    assert.equal((await call('/api/league/score', 'PUT', { seasonStart, count: 10, revision: 1 }, person)).status, 409);
  }
});

test('ties share competition rank and own standing survives outside the top fifty', async () => {
  const people = await Promise.all(Array.from({ length: 52 }, () => member()));
  await env.DB.batch(people.map((person, index) => env.DB.prepare(
    'INSERT INTO league_scores(member_id, season_start, count, revision, updated_at) VALUES (?1, ?2, ?3, 1, ?4)')
    .bind(person.id, '2026-01-05', index < 2 ? 20 : 10, monday)));
  const outside = people.slice(2).sort((a, b) => a.id.localeCompare(b.id)).at(-1);
  const board = await (await call('/api/league', 'GET', undefined, outside, monday + day)).json();
  assert.equal(board.entries.length, 50);
  assert.equal(board.totalParticipants, 52);
  assert.deepEqual(board.entries.slice(0, 3).map(row => row.rank), [1, 1, 3]);
  assert.equal(board.me.id, outside.id);
  assert.equal(board.me.rank, 3);
  assert.equal(board.entries.some(row => row.id === outside.id), false);
  assert.deepEqual(Object.keys(board.entries[0]).sort(), ['alias', 'id', 'rank', 'score', 'updatedAt']);
});

test('deletion removes both seasons and rejects replayed joins and score writes', async () => {
  const person = await member(monday - day);
  await score(person, 9, 1, monday - day, '2025-12-29');
  await score(person, 3);
  for (let index = 0; index < 2; index++) {
    const deletion = await call('/api/league/membership', 'DELETE', undefined, person);
    assert.equal(deletion.status, 200);
    assert.deepEqual(await deletion.json(), { deleted: true });
  }
  assert.equal((await call('/api/league/join', 'POST', { memberID: person.id }, person)).status, 401);
  assert.equal((await call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', count: 5, revision: 2 }, person)).status, 401);
  assert.equal((await call('/api/league', 'GET', undefined, person)).status, 401);
  const saved = await env.DB.prepare('SELECT * FROM league_members WHERE id = ?1').bind(person.id).first();
  assert.equal(saved.alias, '');
  assert.equal(saved.revoked_at, monday);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM league_scores').first()).n, 0);
  assert.deepEqual((await (await call()).json()).entries, []);
});

test('deletion racing a score or first join cannot resurrect public data', async () => {
  const person = await member();
  const responses = await Promise.all([
    call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', count: 30, revision: 1 }, person),
    call('/api/league/membership', 'DELETE', undefined, person),
  ]);
  assert.ok([200, 401].includes(responses[0].status));
  assert.equal(responses[1].status, 200);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM league_scores').first()).n, 0);
  const fresh = { id: crypto.randomUUID(), token: worker.randomToken(), ip: crypto.randomUUID() };
  assert.equal((await call('/api/league/membership', 'DELETE', undefined, fresh)).status, 200);
  assert.equal((await call('/api/league/join', 'POST', { memberID: fresh.id }, fresh)).status, 401);
});

test('invalid credentials and payloads fail closed while calibration remains private', async () => {
  const person = await member();
  const stranger = { ...person, token: worker.randomToken() };
  assert.equal((await call('/api/league', 'GET', undefined, stranger)).status, 401);
  assert.equal((await call('/api/league/join', 'POST', { memberID: person.id }, stranger)).status, 401);
  assert.equal((await call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', count: 1, revision: 1 })).status, 401);
  assert.equal((await call('/api/league/join', 'POST', { memberID: crypto.randomUUID() }, person)).status, 409);
  assert.equal((await call('/api/league/join', 'POST', { memberID: 'invalid' }, stranger)).status, 400);
  for (const payload of [{ count: -1, revision: 1 }, { count: 100001, revision: 1 }, { count: 1.5, revision: 1 },
    { count: '10', revision: 1 }, { count: 1, revision: 0 }, { count: 1, revision: 1.1 }, { count: 1, revision: 9007199254740992 }]) {
    assert.equal((await call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', ...payload }, person)).status, 400);
  }
  assert.equal((await call('/api/league/score', 'PUT', { seasonStart: '2026-01-05', count: 1, revision: 1 }, person, monday,
    { origin: 'https://untrusted.example' })).status, 403);
  const context = { waitUntil() {} };
  for (const path of ['/api/recordings', '/api/session', '/api/delivery']) {
    const result = await worker.default.fetch(request(path, 'GET', undefined, person), env, context);
    assert.equal(result.status, 401);
  }
  const publicBoard = await worker.default.fetch(request('/api/league'), env, context);
  assert.equal(publicBoard.status, 200);
  assert.equal(publicBoard.headers.get('cache-control'), 'no-store');
  assert.equal((await worker.default.fetch(request('/'), env, context)).status, 303);
});

test('enrollment and traffic limits provide retry guidance and never save raw IP addresses', async () => {
  for (let index = 0; index < 11; index++) {
    const person = { id: crypto.randomUUID(), token: worker.randomToken(), ip: '192.0.2.3' };
    const response = await call('/api/league/join', 'POST', { memberID: person.id }, person);
    assert.equal(response.status, index === 10 ? 429 : 201);
    if (index === 10) assert.equal(response.headers.get('retry-after'), '86400');
  }
  for (let index = 0; index < 121; index++) {
    const response = await call();
    assert.equal(response.status, index === 120 ? 429 : 200);
    if (index === 120) assert.equal(response.headers.get('retry-after'), '60');
  }
  assert.equal(JSON.stringify(await env.DB.prepare('SELECT * FROM request_limits').all()).includes('192.0.2.'), false);
});

test('cleanup keeps two seasons, expires inactive membership and allows deletion after credential cleanup', async () => {
  const person = await member(monday - 15 * day);
  await score(person, 1, 1, monday - 15 * day, '2025-12-15');
  await score(person, 2, 1, monday - day, '2025-12-29');
  await score(person, 3);
  await worker.purgeLeague(env, monday);
  const scores = await env.DB.prepare('SELECT season_start FROM league_scores ORDER BY season_start').all();
  assert.deepEqual(scores.results.map(row => row.season_start), ['2025-12-29', '2026-01-05']);
  const expired = await call('/api/league', 'GET', undefined, person, monday + 90 * day);
  assert.equal(expired.status, 401);
  await worker.purgeLeague(env, monday + 90 * day);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM league_members').first()).n, 0);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM league_scores').first()).n, 0);
  const deletion = await call('/api/league/membership', 'DELETE', undefined, person, monday + 90 * day);
  assert.equal(deletion.status, 200);
});
