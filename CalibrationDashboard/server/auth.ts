import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import { APIError } from './validation.ts';

export function assertSameOrigin(request: Request, env: Env, dashboard = false): void {
  const origin = request.headers.get('origin');
  if (request.headers.get('sec-fetch-site') === 'cross-site' ||
      (origin !== null && origin !== env.APP_ORIGIN) || (dashboard && origin !== env.APP_ORIGIN)) {
    throw new APIError(403, 'This action must come from the Ciggy dashboard.');
  }
}

function dashboardToken(request: Request): string | null {
  const assertion = request.headers.get('cf-access-jwt-assertion');
  if (assertion) return assertion;
  const cookies = request.headers.get('cookie');
  if (!cookies) return null;
  if (cookies.length > 32768) throw new APIError(401, 'Sign in through Cloudflare Access to view recordings.');
  const matches = cookies.split(';').map(value => value.trim()).filter(value => value.startsWith('CF_Authorization='));
  if (matches.length !== 1) return null;
  try { return decodeURIComponent(matches[0].slice('CF_Authorization='.length)); }
  catch { return null; }
}

/** Access protects /login and issues its domain-scoped HttpOnly cookie. The
 * Worker independently verifies that same JWT for every dashboard request. */
export async function verifyDashboardAccess(request: Request, env: Env, resolver?: JWTVerifyGetKey): Promise<string> {
  if (!/^https:\/\/[a-z0-9-]+\.cloudflareaccess\.com$/.test(env.ACCESS_TEAM_DOMAIN) || !env.ACCESS_AUD || !env.ALLOWED_EMAILS) {
    throw new APIError(503, 'Private dashboard sign-in is not configured yet.');
  }
  const token = dashboardToken(request);
  if (!token || token.length > 16000) throw new APIError(401, 'Sign in through Cloudflare Access to view recordings.');
  try {
    const key = resolver ?? createRemoteJWKSet(new URL(`${env.ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`));
    const { payload } = await jwtVerify(token, key, { issuer: env.ACCESS_TEAM_DOMAIN,
      audience: env.ACCESS_AUD, algorithms: ['RS256'], requiredClaims: ['exp', 'iat', 'email'] });
    const email = typeof payload.email === 'string' ? payload.email.toLowerCase() : '';
    const allowed = env.ALLOWED_EMAILS.split(',').map(value => value.trim().toLowerCase()).filter(Boolean);
    if (!email || !allowed.includes(email)) throw new Error('Not allowed');
    return email;
  } catch { throw new APIError(403, 'Your dashboard sign-in is invalid or is not authorized.'); }
}

/** owner_email is a historical column name. Production uses a shared workspace
 * key there; deployments without this opt-in remain isolated by reviewer email. */
export function reviewerScope(email: string, env: Env): string {
  if (!env.SHARED_WORKSPACE_ID) return email;
  if (!/^[a-z0-9-]{1,64}$/.test(env.SHARED_WORKSPACE_ID)) throw new APIError(503, 'The private workspace is not configured correctly.');
  return `workspace:${env.SHARED_WORKSPACE_ID}`;
}

export async function hash(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}
export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
export function pairingCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map(byte => alphabet[byte & 31]).join('');
}
export function cleanCode(value: unknown): string {
  if (typeof value !== 'string') throw new APIError(400, 'Enter the pairing code from your dashboard.');
  const code = value.replace(/[\s-]/g, '').toUpperCase();
  if (!/^[A-HJ-NP-Z2-9]{12}$/.test(code)) throw new APIError(400, 'Enter the complete 12-character pairing code.');
  return code;
}
export type Participant = { id: string; alias: string; owner_email: string; created_at: number; expires_at: number; revoked_at: number | null };
export async function participantForToken(request: Request, env: Env, allowDeletion = false): Promise<Participant> {
  const authorization = request.headers.get('authorization');
  const token = authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
  if (!token) throw new APIError(401, 'Connect this device with a dashboard pairing code.');
  const participant = await env.DB.prepare('SELECT id, alias, owner_email, created_at, expires_at, revoked_at FROM participants WHERE token_hash = ?1')
    .bind(await hash(token)).first<Participant>();
  if (!participant || (!allowDeletion && (participant.revoked_at !== null || participant.expires_at <= Date.now()))) {
    throw new APIError(401, 'This device connection has expired or was revoked.');
  }
  return participant;
}

export async function enrollmentRateLimit(request: Request, env: Env): Promise<void> {
  const now = Date.now(), hour = Math.floor(now / 3600000);
  // Only a short-lived digest is saved; IP addresses never enter the database.
  const key = await hash(`enroll:${hour}:${request.headers.get('cf-connecting-ip') ?? 'unknown'}`);
  const result = await env.DB.prepare('INSERT INTO request_limits(key, count, expires_at) VALUES (?1, 1, ?2) ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count')
    .bind(key, (hour + 1) * 3600000).first<{ count: number }>();
  if (!result || result.count > 20) throw new APIError(429, 'Too many pairing attempts. Try again later.', 3600);
}
