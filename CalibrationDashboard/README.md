# Private motion journal

The Worker serves the React and shadcn/ui Ciggy dashboard, stores recording JSON in a private R2 bucket, and keeps participant metadata and activity labels in D1. The raw format is the app's `MotionRecording` version 1; its numeric dates are seconds since January 1, 2001. Background accelerometer recordings have no measured gyroscope data.

The same Worker also serves the optional [Ashtray League](../docs/leaderboard.md), a public global weekly ranking of shared cigarette totals. Its `/api/league` routes, credentials, and D1 tables are separate from private calibration. Migration `0005_ashtray_league.sql` adds the league; it never makes recordings or dashboard assets public.

## Sign-in and shared workspace

Configure one Cloudflare Access self-hosted application for **`ciggy.thatcanadian.dev/login`**. Its Allow policy must include only the authorized testers' email addresses. No public Bypass applications are needed for the native API.

In the Access application's cookie settings, enable **HttpOnly**, use **SameSite Lax**, and **disable Cookie Path Attribute**. Disabling the path restriction lets the application-domain `CF_Authorization` cookie reach `/`, static assets, and `/api/*` after sign-in at `/login`. Cloudflare documents this behavior in its [authorization cookie settings](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/).

Set `ACCESS_TEAM_DOMAIN` to the exact HTTPS organization issuer and `ACCESS_AUD` to this Access application's audience. Set the `ALLOWED_EMAILS` Worker secret to the same comma-separated email allowlist. Keep the secret out of source control. The Worker verifies the signature, issuer, audience, expiration, and allowed email for either the Access assertion header or the `CF_Authorization` cookie. A cookie's presence alone grants no access.

Unauthenticated page and asset requests redirect to the fixed `/login` path. Access performs sign-in there, and the authenticated Worker redirects to `/`. API failures remain JSON `401`/`403` responses, and missing Access configuration fails closed with `503`. Redirect query parameters are ignored.

Production explicitly sets `SHARED_WORKSPACE_ID=ciggy-internal-testers`: both authorized reviewers can see and label both testers' consented recordings in one workspace. The database's historical `owner_email` column stores `workspace:<id>` in this mode. Deployments with no shared workspace ID remain isolated by reviewer email. The actual signed email is still checked against the allowlist and returned by `/api/session`.

## App pairing and API

The native routes use their own credentials and remain outside the `/login` Access path:

| Route | Authorization and behavior |
| --- | --- |
| `POST /api/enroll` | `{code,alias}`; a single-use, 15-minute dashboard code yields a random device bearer token. |
| `POST /api/upload` | Device bearer; raw `MotionRecording` JSON, at most 5 MiB and 18,000 samples in ten minutes. The first sample must be after enrollment and no older than 48 hours. Expired or pre-enrollment uploads return terminal `410`. |
| `DELETE /api/participant` | Device bearer; revoke this participant and delete their shared raw recordings and labels. The token cannot browse the dashboard or other participants' data. |

Dashboard requests require a verified Access session. Writes also require the configured same-origin `Origin` header:

| Route | Behavior |
| --- | --- |
| `GET /api/session` | Signed email and retention information. |
| `POST /api/pairing` | `{alias}` → `{code,expiresAt}`. Create a separate code for each tester. |
| `GET /api/recordings` | Paginated metadata; optional `from`, `to` ISO dates, participant UUID, cursor, and limit up to 200. Defaults to activity from the last 14 days. |
| `GET /api/recordings/:id` | Recording, participant alias, activity annotations, and `labelRevision`. |
| `PUT /api/recordings/:id/labels` | `{annotations,expectedRevision}`; stale concurrent edits return `409`. Annotation times use the recording's 2001 epoch. |
| `DELETE /api/recordings/:id` | Delete raw data and labels; retain a temporary deletion marker against delayed retries. |
| `POST /api/import` | `{participant,recording,annotations}`; explicit reviewer import, using the existing 14-day source-age limit. |
| `PATCH /api/participants/:id` | `{alias}`; rename the participant within the authorized workspace. |

Uploads deduplicate by participant and original recording UUID. A UUID reused for different raw data is rejected with `409`; an interrupted object write remains pending and can resume without publishing partial data. A participant is limited to 576 accepted chunks per rolling 72 hours; `429` includes retry guidance. Native requests can send uncompressed JSON. Standard zlib-wrapped `Content-Encoding: deflate` is also bounded and accepted; Foundation's raw DEFLATE output must not be mislabeled as that encoding.

Raw data and labels expire 14 days after the first upload reservation, are excluded from reads immediately on expiration, and are removed by hourly cleanup. Device connections expire after 30 days. Deletion markers cannot expose raw data and expire with the original recording. Provider-managed D1 Time Travel backups have their own Cloudflare retention; deleting live data does not promise immediate erasure of provider backups. See the [privacy policy](../docs/privacy.md).

## Checks and deployment

```sh
npm ci
npm test
npm run build
npm run typecheck
npx wrangler deploy --dry-run
```

After the Access application and its exact issuer/audience are configured, set `ALLOWED_EMAILS` using `wrangler secret put ALLOWED_EMAILS` through its protected prompt. Apply **all** migrations with `wrangler d1 migrations apply ciggy-calibration --remote`, then deploy with `wrangler deploy`. The checked-in configuration uses the project's existing Cloudflare account, D1 database, private R2 bucket, and custom domain. Worker preview and `workers.dev` URLs are disabled; all static assets run through the Worker authentication gate.

Verify that `/` redirects to `/login`, `/api/recordings` returns `401` without a session, native routes reject missing tokens/codes, and both authorized reviewers can sign in and see the shared workspace. Inspect the Access-issued cookie for domain scope, HttpOnly, and Secure flags. Confirm the R2 bucket has no public URL enabled. Do not print cookies, pairing codes, bearer tokens, raw samples, or participant aliases in deployment logs.

Tests use local D1/R2 simulation and signed test JWTs. They exercise cookie/header validation, guarded assets, fixed redirects, shared and isolated reviewer scopes, pairing, source-age and enrollment boundaries, idempotent uploads, label conflicts, deletion, bounded compression, rate limits, and cleanup within the Free-plan D1 query budget.
