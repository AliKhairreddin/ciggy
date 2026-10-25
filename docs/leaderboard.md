# Ashtray League

The league is an optional global weekly ranking of **logged cigarette totals, highest first**. It uses the current and previous Monday–Sunday weeks, with the same Monday 00:00 UTC boundary for everyone. The league does not publish individual event times, notes, motion, heart-rate data, or location. Totals can include estimated detections and manual entries; they are not independently verified.

People join under a generated Ciggy alias. The board shows the first 50 participating aliases and the signed-in member's own standing even when outside that list. Equal totals share competition rank (for example, 1, 1, 3). Only positive totals appear in the public ranking. A member with zero logged cigarettes sees their own zero total with no rank. This release has one global board and no prizes.

## Synchronization and corrections

The iPhone computes each weekly total from its saved event repository and synchronizes the aggregate after joining. The server stores only the weekly count, monotonically increasing revision, and synchronization timestamp. A newer revision replaces the total in either direction, so deleting or correcting a detection can lower a published count. Repeating the same revision and count is idempotent; an older revision or a conflicting reuse of a revision returns `409` without replacing the saved total.

Current and previous weeks can be reconciled. Older weeks are outside the retained board scope and cannot be submitted. Zero is an explicit saved total, never a substitute for failed synchronization. The interface preserves a previously valid board when a network request fails and explain when its saved snapshot was fetched. `updatedAt` is the server's accepted synchronization time, not a guarantee that Watch history is complete.

The native app reuses board snapshots for up to one minute, with their generation time visible. It synchronizes changed totals while the iPhone app is active and when League opens, at most once per minute; reopening an unchanged board does not re-upload history. Current and previous weeks are recomputed so late Watch delivery and corrections reconcile both. Credentials, pending aggregate submissions, and revision counters are saved in Keychain before writes. Missing/corrupt local storage does not publish zero. A membership whose Keychain survived reinstall is paused until the user leaves and rejoins with the new installation’s history.

## Native API

These routes share the existing Worker and D1 database at `https://ciggy.thatcanadian.dev`. They have separate credentials and tables from the private calibration service. Access to the league never grants access to calibration data or dashboard assets.

| Route | Contract |
| --- | --- |
| `GET /api/league?season=current` | Public board. `season=previous` selects the previous week. Optional bearer authentication adds the member's own standing and revision. Invalid supplied credentials return `401` rather than silently downgrading to anonymous. |
| `POST /api/league/join` | Bearer is a client-generated, cryptographically random 32-byte base64url token. Body is `{memberID: UUID}`. Returns `{id,alias,joinedAt}`. The same token and member ID can safely retry an uncertain enrollment. |
| `PUT /api/league/score` | Member bearer; body `{seasonStart: "yyyy-MM-dd", count, revision}`. Count must be an integer from 0 through 100000; revision must be a positive JavaScript-safe integer. Returns `{accepted:true,seasonStart,count,revision,updatedAt}`. |
| `DELETE /api/league/membership` | Member bearer; atomically removes the member's public alias and both saved scores. Returns `{deleted:true}`. Repeating deletion, including after server expiry, is safe. |

The board response is:

```text
{
  seasonStart, seasonEnd, serverNow, generatedAt,  // ISO 8601 UTC strings
  entries: [{id, alias, score, rank, updatedAt}],
  totalParticipants,                            // Positive totals in this season
  me: {id, alias, score, rank, updatedAt} | null,
  member: {id, alias, joinedAt} | null,
  myRevision: integer | null                    // Own selected-season revision only
}
```

`entries` contains exactly `min(totalParticipants, 50)` rows. `me.rank` is null at zero and `updatedAt` is null before a first accepted synchronization. `seasonEnd` is exclusive. Names are generated server-side from a small curated vocabulary and a UUID suffix; arbitrary public text is not accepted. Clients must save the credential and submission revision before making requests and use `myRevision` to recover after lost local synchronization state. No raw smoking history is needed for this protocol.

## Retention, deletion, and abuse controls

Hourly cleanup removes totals older than the previous season and memberships inactive for 90 days. Reads immediately exclude expired or revoked members. Successful score synchronization extends active membership. Leaving clears the alias and scores transactionally and keeps a minimal credential-hash revocation marker for 90 days. This marker also prevents an in-flight first enrollment from recreating a just-deleted membership. After leaving, joining again uses a new credential and member ID. Cloudflare-managed database backups have their own retention; live deletion does not promise immediate erasure from provider backups.

Credentials are stored in D1 only as domain-separated SHA-256 hashes. IP-based limits use short-lived windowed hashes, never raw IP addresses in application storage: 10 new memberships per UTC day, 120 board reads per minute, and 30 mutations per minute. A `429` response includes `Retry-After`. The service never accepts a client-supplied rank. Counts remain self-reported and the service does not claim protection against a modified client or coordinated fake accounts.

The private dashboard remains protected by its existing Cloudflare Access authentication. No broad public bypass is introduced. The `/api/league` route family alone accepts public reads or league credentials, and cross-site browser requests fail closed.

## Deployment and verification

Apply migration `0005_ashtray_league.sql` using the existing D1 migration workflow before deploying the Worker. No new binding, secret, domain, or platform entitlement is required. Run the existing dashboard test suite, TypeScript checks, and Worker dry run. The league tests exercise weekly boundaries, descending and tied ranks, top-50 plus own standing, corrections, concurrent retries, deletion races, credential isolation, rate limits, and retention. All fixtures are synthetic.
