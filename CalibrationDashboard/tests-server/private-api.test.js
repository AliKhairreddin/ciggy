import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';

const root = fileURLToPath(new URL('../', import.meta.url));
const origin = 'https://ciggy.thatcanadian.dev';
let temporary, worker, app, platform, env;
const context = { waitUntil() {} };

before(async () => {
  temporary = await mkdtemp(join(tmpdir(), 'ciggy-private-api-'));
  const outfile = join(temporary, 'worker.mjs');
  await build({ stdin: { contents: `export { default, createApp } from './server/index.ts';
      export * from './server/validation.ts'; export * from './server/auth.ts'; export * from './server/store.ts';`,
    resolveDir: root, sourcefile: 'test-entry.ts', loader: 'ts' },
    outfile, bundle: true, platform: 'neutral', format: 'esm', target: 'es2023' });
  worker = await import(pathToFileURL(outfile));
  platform = new Miniflare(convertV4MiniflareOptions({ modules: true, script: 'export default { fetch() { return new Response("test"); } };',
    compatibilityDate: '2026-10-23', d1Databases: ['DB'], r2Buckets: ['RECORDINGS'] }));
  env = { ...await platform.getBindings(), APP_ORIGIN: origin,
    ACCESS_TEAM_DOMAIN: 'https://ciggy-test.cloudflareaccess.com', ACCESS_AUD: 'test-audience',
    ALLOWED_EMAILS: 'reviewer@example.test', SHARED_WORKSPACE_ID: '',
    ASSETS: { fetch: async () => new Response('private asset') } };
  const migrations = (await readdir(join(root, 'migrations'))).filter(name => name.endsWith('.sql')).sort();
  for (const name of migrations) {
    const schema = await readFile(join(root, 'migrations', name), 'utf8');
    await env.DB.batch(schema.split(';').map(sql => sql.trim()).filter(Boolean).map(sql => env.DB.prepare(sql)));
  }
  app = worker.createApp(async request => request.headers.get('x-test-reviewer') ?? 'reviewer@example.test');
});

beforeEach(async () => {
  await env.DB.batch(['recordings', 'pairing_codes', 'request_limits', 'participants'].map(table => env.DB.prepare(`DELETE FROM ${table}`)));
});
after(async () => {
  await platform?.dispose();
  if (temporary) await rm(temporary, { recursive: true, force: true });
});

function request(path, method = 'GET', body, headers = {}) {
  return new Request(origin + path, { method,
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(method === 'GET' ? {} : { origin }), ...headers },
    ...(body === undefined ? {} : { body: typeof body === 'string' || body instanceof Uint8Array ? body : JSON.stringify(body) }) });
}
const call = (path, method, body, headers, handler = app) => handler.fetch(request(path, method, body, headers), env, context);
function recording(id = crypto.randomUUID()) {
  const start = (Date.now() - worker.APPLE_EPOCH_MS) / 1000 + 1;
  return { id, formatVersion: 1, label: 'unlabelled', startedAt: start, endedAt: start + .2,
    samples: [0, .1, .2].map(offset => ({ timestamp: start + offset, gravity: { x: 0, y: 0, z: -1 },
      userAcceleration: { x: 0, y: 0, z: 0 }, rotationRate: { x: 0, y: 0, z: 0 }, source: 'liveDeviceMotion' })) };
}
async function participant(alias = 'Tester A') {
  const paired = await call('/api/pairing', 'POST', { alias });
  assert.equal(paired.status, 201);
  const { code } = await paired.json();
  const enrolled = await call('/api/enroll', 'POST', { code, alias });
  assert.equal(enrolled.status, 201);
  return { ...await enrolled.json(), code };
}
async function upload(person, raw = recording()) {
  const response = await call('/api/upload', 'POST', raw, { authorization: `Bearer ${person.token}` });
  assert.equal(response.status, 201);
  return { ...await response.json(), raw };
}

test('private pages and recording APIs fail closed without Access; upload tokens cannot browse', async () => {
  const person = await participant();
  await upload(person);
  for (const path of ['/', '/api/recordings', '/api/session']) {
    const response = await call(path, 'GET', undefined, { authorization: `Bearer ${person.token}` }, worker.default);
    assert.equal(response.status, path === '/' ? 303 : 401);
    if (path === '/') assert.equal(response.headers.get('location'), '/login');
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
  const notConfigured = await worker.default.fetch(request('/'), { ...env, ACCESS_AUD: '' }, context);
  assert.equal(notConfigured.status, 503);
});

test('signed Access cookies guard dashboard assets and APIs; redirects have fixed same-origin destinations', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const resolver = createLocalJWKSet({ keys: [{ ...await exportJWK(publicKey), kid: 'cookie-key' }] });
  const signed = await new SignJWT({ email: 'reviewer@example.test' })
    .setProtectedHeader({ alg: 'RS256', kid: 'cookie-key' }).setIssuer(env.ACCESS_TEAM_DOMAIN)
    .setAudience(env.ACCESS_AUD).setIssuedAt().setExpirationTime('1h').sign(privateKey);
  const guarded = worker.createApp((request, bindings) => worker.verifyDashboardAccess(request, bindings, resolver));
  const cookie = { cookie: `unrelated=value; CF_Authorization=${signed}` };
  for (const path of ['/', '/app.js', '/styles.css']) {
    const response = await call(path, 'GET', undefined, cookie, guarded);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), 'private asset');
  }
  const session = await call('/api/session', 'GET', undefined, cookie, guarded);
  assert.equal((await session.json()).email, 'reviewer@example.test');
  const login = await call('/login?returnTo=https://untrusted.example', 'GET', undefined, cookie, guarded);
  assert.equal(login.status, 303);
  assert.equal(login.headers.get('location'), '/');
  const unsigned = await call('/styles.css?redirect=https://untrusted.example', 'GET', undefined, {}, guarded);
  assert.equal(unsigned.status, 303);
  assert.equal(unsigned.headers.get('location'), '/login');
  assert.equal(await unsigned.text(), '');
  const signature = signed.split('.');
  signature[2] = (signature[2][0] === 'A' ? 'B' : 'A') + signature[2].slice(1);
  const forged = { cookie: `CF_Authorization=${signature.join('.')}` };
  const rejectedAPI = await call('/api/recordings', 'GET', undefined, forged, guarded);
  assert.equal(rejectedAPI.status, 403);
  const rejectedAsset = await call('/app.js', 'GET', undefined, forged, guarded);
  assert.equal(rejectedAsset.status, 303);
  assert.equal(rejectedAsset.headers.get('location'), '/login');
  assert.equal(await rejectedAsset.text(), '');
  const unguardedLogin = await call('/login', 'GET', undefined, {}, guarded);
  assert.equal(unguardedLogin.status, 401, 'A missing edge Access rule must not cause a redirect loop or serve assets.');
});

test('an explicitly shared workspace lets both authorized reviewers inspect both enrolled testers', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const resolver = createLocalJWKSet({ keys: [{ ...await exportJWK(publicKey), kid: 'shared-key' }] });
  const sharedEnv = { ...env, ALLOWED_EMAILS: 'reviewer@example.test,friend@example.test',
    SHARED_WORKSPACE_ID: 'ciggy-internal-testers' };
  const guarded = worker.createApp((request, bindings) => worker.verifyDashboardAccess(request, bindings, resolver));
  const cookie = async email => ({ cookie: `CF_Authorization=${await new SignJWT({ email })
    .setProtectedHeader({ alg: 'RS256', kid: 'shared-key' }).setIssuer(env.ACCESS_TEAM_DOMAIN)
    .setAudience(env.ACCESS_AUD).setIssuedAt().setExpirationTime('1h').sign(privateKey)}` });
  const reviewer = await cookie('reviewer@example.test'), friend = await cookie('friend@example.test');
  const sharedCall = (path, method, body, headers = {}) => guarded.fetch(request(path, method, body, headers), sharedEnv, context);
  for (const [alias, owner] of [['Tester A', reviewer], ['Tester B', friend]]) {
    const pair = await (await sharedCall('/api/pairing', 'POST', { alias }, owner)).json();
    const enrolled = await (await sharedCall('/api/enroll', 'POST', { alias, code: pair.code })).json();
    assert.equal((await sharedCall('/api/upload', 'POST', recording(), { authorization: `Bearer ${enrolled.token}` })).status, 201);
    assert.equal((await sharedCall('/api/recordings', 'GET', undefined, { authorization: `Bearer ${enrolled.token}` })).status, 401);
  }
  for (const headers of [reviewer, friend]) {
    const list = await (await sharedCall('/api/recordings', 'GET', undefined, headers)).json();
    assert.deepEqual(list.recordings.map(row => row.participant).sort(), ['Tester A', 'Tester B']);
    for (const row of list.recordings) assert.equal((await sharedCall(`/api/recordings/${row.id}`, 'GET', undefined, headers)).status, 200);
  }
  const outsider = await sharedCall('/api/recordings', 'GET', undefined, await cookie('outsider@example.test'));
  assert.equal(outsider.status, 403, 'Sharing never bypasses the signed-email allowlist.');
  const owner = await env.DB.prepare('SELECT DISTINCT owner_email FROM participants').all();
  assert.deepEqual(owner.results, [{ owner_email: 'workspace:ciggy-internal-testers' }]);
});

test('Access verification checks signature, audience, issuer, expiration and allowlisted email', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const publicJWK = { ...await exportJWK(publicKey), kid: 'test-key' };
  const resolver = createLocalJWKSet({ keys: [publicJWK] });
  const jwt = async (email, audience = env.ACCESS_AUD, issuer = env.ACCESS_TEAM_DOMAIN, expiration = '1h') =>
    new SignJWT({ email }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
      .setIssuer(issuer).setAudience(audience).setIssuedAt().setExpirationTime(expiration).sign(privateKey);
  const authenticate = token => worker.verifyDashboardAccess(request('/', 'GET', undefined,
    { 'cf-access-jwt-assertion': token }), env, resolver);
  assert.equal(await authenticate(await jwt('reviewer@example.test')), 'reviewer@example.test');
  const signed = (await jwt('reviewer@example.test')).split('.');
  signed[2] = (signed[2][0] === 'A' ? 'B' : 'A') + signed[2].slice(1);
  await assert.rejects(authenticate(signed.join('.')), error => error.status === 403);
  for (const token of [await jwt('outsider@example.test'), await jwt('reviewer@example.test', 'another-app'),
    await jwt('reviewer@example.test', env.ACCESS_AUD, 'https://other.cloudflareaccess.com'),
    await jwt('reviewer@example.test', env.ACCESS_AUD, env.ACCESS_TEAM_DOMAIN, 946684800)]) {
    await assert.rejects(authenticate(token), error => error.status === 403);
  }
});

test('pairing codes are single use and stored only as hashes; bearer values stay out of DB', async () => {
  const person = await participant();
  const replay = await call('/api/enroll', 'POST', { code: person.code, alias: 'Another tester' });
  assert.equal(replay.status, 401);
  const row = await env.DB.prepare('SELECT token_hash FROM participants WHERE id = ?1').bind(person.participantID).first();
  assert.equal(row.token_hash, await worker.hash(person.token));
  assert.notEqual(row.token_hash, person.token);
  const code = await env.DB.prepare('SELECT code_hash FROM pairing_codes').first();
  assert.notEqual(code.code_hash, person.code.replaceAll('-', ''));
});

test('uploads are idempotent and a conflicting reuse of an ID cannot overwrite saved raw data', async () => {
  const person = await participant(), first = await upload(person);
  const duplicate = await call('/api/upload', 'POST', first.raw, { authorization: `Bearer ${person.token}` });
  assert.equal((await duplicate.json()).duplicate, true);
  const changed = structuredClone(first.raw);
  changed.samples[1].userAcceleration.x = 1;
  const conflict = await call('/api/upload', 'POST', changed, { authorization: `Bearer ${person.token}` });
  assert.equal(conflict.status, 409);
  const saved = await (await call(`/api/recordings/${first.id}`)).json();
  assert.equal(saved.recording.samples[1].userAcceleration.x, 0);
  const list = await (await call('/api/recordings')).json();
  assert.equal(list.recordings.length, 1);
  assert.equal(list.recordings[0].sampleCount, 3);
  assert.equal(list.recordings[0].recording, undefined, 'List responses contain metadata only.');
});

test('concurrent identical uploads converge to one saved record', async () => {
  const person = await participant(), raw = recording();
  const responses = await Promise.all([1, 2].map(() => call('/api/upload', 'POST', raw,
    { authorization: `Bearer ${person.token}` })));
  assert.deepEqual(responses.map(response => response.status), [201, 201]);
  const ids = await Promise.all(responses.map(async response => (await response.json()).id));
  assert.equal(ids[0], ids[1]);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 1);
});

test('labels use optimistic revisions and remain scoped to their raw recording', async () => {
  const person = await participant(), item = await upload(person);
  const annotation = { id: crypto.randomUUID(), recordingID: item.raw.id,
    start: item.raw.samples[0].timestamp, end: item.raw.samples.at(-1).timestamp, label: 'smoking', notes: 'One observed cigarette' };
  const update = await call(`/api/recordings/${item.id}/labels`, 'PUT', { annotations: [annotation], expectedRevision: 0 });
  assert.equal(update.status, 200);
  assert.equal((await update.json()).labelRevision, 1);
  const stale = await call(`/api/recordings/${item.id}/labels`, 'PUT', { annotations: [], expectedRevision: 0 });
  assert.equal(stale.status, 409);
  const outside = { ...annotation, start: annotation.start - 1 };
  const badRange = await call(`/api/recordings/${item.id}/labels`, 'PUT', { annotations: [outside], expectedRevision: 1 });
  assert.equal(badRange.status, 400);
  const detail = await (await call(`/api/recordings/${item.id}`)).json();
  assert.equal(detail.annotations.length, 1);
});

test('another reviewer cannot list, read, label or delete a participant they did not enroll', async () => {
  const person = await participant(), item = await upload(person), headers = { 'x-test-reviewer': 'other@example.test' };
  const listed = await (await call('/api/recordings', 'GET', undefined, headers)).json();
  assert.equal(listed.recordings.length, 0);
  assert.equal((await call(`/api/recordings/${item.id}`, 'GET', undefined, headers)).status, 404);
  assert.equal((await call(`/api/recordings/${item.id}`, 'DELETE', undefined, headers)).status, 404);
});

test('cross-site browser writes are rejected and native uploads without Origin are allowed', async () => {
  const person = await participant();
  const rejected = await call('/api/upload', 'POST', recording(),
    { origin: 'https://untrusted.example', authorization: `Bearer ${person.token}` });
  assert.equal(rejected.status, 403);
  const native = request('/api/upload', 'POST', recording(), { authorization: `Bearer ${person.token}` });
  native.headers.delete('origin');
  assert.equal((await app.fetch(native, env, context)).status, 201);
  const missingDashboardOrigin = request('/api/pairing', 'POST', {});
  missingDashboardOrigin.headers.delete('origin');
  assert.equal((await app.fetch(missingDashboardOrigin, env, context)).status, 403);
});

test('deleted uploads cannot be restored by a delayed retry; participant deletion revokes its bearer', async () => {
  const person = await participant(), item = await upload(person);
  assert.equal((await call(`/api/recordings/${item.id}`, 'DELETE')).status, 200);
  const retry = await call('/api/upload', 'POST', item.raw, { authorization: `Bearer ${person.token}` });
  assert.equal((await retry.json()).deleted, true);
  assert.equal((await (await call('/api/recordings')).json()).recordings.length, 0);
  const deleted = await call('/api/participant', 'DELETE', undefined, { authorization: `Bearer ${person.token}` });
  assert.equal(deleted.status, 200);
  assert.equal((await call('/api/upload', 'POST', recording(), { authorization: `Bearer ${person.token}` })).status, 401);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 0);
});

test('retention cleanup removes raw objects, annotations and metadata after fourteen days', async () => {
  const person = await participant(), item = await upload(person);
  const row = await env.DB.prepare('SELECT object_key FROM recordings WHERE id = ?1').bind(item.id).first();
  assert.ok(await env.RECORDINGS.get(row.object_key));
  await env.DB.prepare('UPDATE recordings SET expires_at = ?1 WHERE id = ?2').bind(Date.now() - 1, item.id).run();
  assert.equal((await call(`/api/recordings/${item.id}`)).status, 404);
  await app.scheduled({}, env, context);
  assert.equal(await env.RECORDINGS.get(row.object_key), null);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 0);
});

test('compressed uploads are decoded with a bound on decoded bytes and reject malformed streams', async () => {
  const person = await participant(), raw = recording();
  const compressed = await call('/api/upload', 'POST', deflateSync(JSON.stringify(raw)),
    { authorization: `Bearer ${person.token}`, 'content-encoding': 'deflate' });
  assert.equal(compressed.status, 201);
  const broken = await call('/api/upload', 'POST', new Uint8Array([1, 2, 3]),
    { authorization: `Bearer ${person.token}`, 'content-encoding': 'deflate' });
  assert.equal(broken.status, 400);
  const bomb = request('/api/upload', 'POST', deflateSync(Buffer.alloc(worker.MAX_BODY_BYTES + 1, ' ')),
    { 'content-encoding': 'deflate' });
  await assert.rejects(worker.readJSON(bomb), error => error.status === 413);
});

test('validation rejects forged gyro history, backward samples, stale recordings and oversized sample lists', () => {
  const raw = recording();
  const invalid = [
    { ...raw, samples: raw.samples.map(sample => ({ ...sample, source: 'recordedAccelerometer' })) },
    { ...raw, samples: [...raw.samples].reverse() },
    { ...raw, startedAt: raw.startedAt - 15 * 86400 },
    { ...raw, samples: Array(18001).fill(raw.samples[0]) },
  ];
  for (const value of invalid) assert.throws(() => worker.validateRecording(value), error => error.status === 400);
});

test('native uploads reject data older than 48 hours even if a networking task stayed queued', async () => {
  const person = await participant(), raw = recording(), delta = 49 * 3600;
  raw.startedAt -= delta; raw.endedAt -= delta;
  raw.samples.forEach(sample => { sample.timestamp -= delta; });
  const response = await call('/api/upload', 'POST', raw, { authorization: `Bearer ${person.token}` });
  assert.equal(response.status, 410);
  assert.match((await response.json()).error, /48-hour/);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 0);
});

test('native uploads cannot share samples from before enrollment or from a future clock', async () => {
  const person = await participant(), raw = recording();
  const row = await env.DB.prepare('SELECT created_at FROM participants WHERE id = ?1').bind(person.participantID).first();
  const first = (row.created_at - worker.APPLE_EPOCH_MS) / 1000 - 1;
  const shift = raw.startedAt - first;
  raw.startedAt -= shift; raw.endedAt -= shift;
  raw.samples.forEach(sample => { sample.timestamp -= shift; });
  const beforeConsent = await call('/api/upload', 'POST', raw, { authorization: `Bearer ${person.token}` });
  assert.equal(beforeConsent.status, 410);
  assert.match((await beforeConsent.json()).error, /after this device was paired/);
  const future = recording();
  future.startedAt += 600; future.endedAt += 600;
  future.samples.forEach(sample => { sample.timestamp += 600; });
  assert.equal((await call('/api/upload', 'POST', future, { authorization: `Bearer ${person.token}` })).status, 400);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 0);
});

test('a failed object write remains pending and can resume without exposing a partial recording', async () => {
  const person = await participant(), raw = recording();
  const brokenEnv = { ...env, RECORDINGS: { put: async () => { throw new Error('temporary object storage failure'); } } };
  const first = await app.fetch(request('/api/upload', 'POST', raw,
    { authorization: `Bearer ${person.token}` }), brokenEnv, context);
  assert.equal(first.status, 503);
  assert.equal((await (await call('/api/recordings')).json()).recordings.length, 0);
  const retry = await call('/api/upload', 'POST', raw, { authorization: `Bearer ${person.token}` });
  assert.equal(retry.status, 201);
  assert.equal((await (await call('/api/recordings')).json()).recordings.length, 1);
});

test('metadata pagination does not omit recordings sharing a timestamp', async () => {
  const person = await participant(), first = recording();
  const second = { ...structuredClone(first), id: crypto.randomUUID() };
  await upload(person, first);
  await upload(person, second);
  const page = await (await call('/api/recordings?limit=1')).json();
  assert.equal(page.recordings.length, 1);
  assert.ok(page.nextCursor);
  const next = await (await call(`/api/recordings?limit=1&cursor=${encodeURIComponent(page.nextCursor)}`)).json();
  assert.equal(next.recordings.length, 1);
  assert.notEqual(next.recordings[0].id, page.recordings[0].id);
  assert.equal(next.nextCursor, null);
});

test('pairing is rate limited and expired codes cannot enroll a device', async () => {
  const pair = await (await call('/api/pairing', 'POST', { alias: 'Tester' })).json();
  await env.DB.prepare('UPDATE pairing_codes SET expires_at = ?1').bind(Date.now() - 1).run();
  assert.equal((await call('/api/enroll', 'POST', { code: pair.code, alias: 'Tester' })).status, 401);
  for (let index = 0; index < 19; index++) {
    assert.equal((await call('/api/enroll', 'POST', { code: 'AAAAAAAAAAAA', alias: 'Tester' })).status, 401);
  }
  const limited = await call('/api/enroll', 'POST', { code: 'AAAAAAAAAAAA', alias: 'Tester' });
  assert.equal(limited.status, 429);
  assert.ok(limited.headers.get('retry-after'));
});

test('upload limits count reserved and deleted chunks so retries and deletions cannot bypass the budget', async () => {
  const person = await participant(), now = Date.now();
  await env.DB.prepare(`WITH RECURSIVE chunks(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM chunks WHERE n < 575)
    INSERT INTO recordings
    (id, participant_id, recording_id, object_key, body_hash, started_at, ended_at, sample_count,
      sources_json, state, created_at, expires_at)
    SELECT printf('00000000-0000-4000-8000-%012d', n), ?1,
      printf('10000000-0000-4000-8000-%012d', n), 'fixture-' || n, 'fixture', 1, 2, 3, '[]',
      CASE WHEN n % 2 = 0 THEN 'pending' ELSE 'deleted' END, ?2, ?3 FROM chunks`)
    .bind(person.participantID, now, now + 86400000).run();
  const response = await call('/api/upload', 'POST', recording(), { authorization: `Bearer ${person.token}` });
  assert.equal(response.status, 429);
  assert.ok(response.headers.get('retry-after'));
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 576);
  await env.DB.prepare('UPDATE recordings SET expires_at = ?1').bind(Date.now() - 1).run();
  let prepared = 0;
  const boundedDB = { prepare(...args) { prepared++; return env.DB.prepare(...args); },
    batch: statements => env.DB.batch(statements) };
  await worker.purgeExpired({ ...env, DB: boundedDB });
  assert.ok(prepared <= 6, 'Large cleanup batches must fit the Free-plan D1 query budget.');
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS count FROM recordings').first()).count, 0);
});
