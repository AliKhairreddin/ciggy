# Build 9 validation and source scope

This delivery changes optional calibration transport and dashboard presentation only. No detector thresholds, cigarette grouping, count calculation or event-sync behavior is changed.

- Shared package: 179 tests passed, including batch deadlines surviving relaunch, missed wakes and opt-out cleanup.
- Watch simulator: `testSecondaryLoggingSavesOneEventAndSurvivesRelaunch` passed using the correctly paired iPhone/Watch simulators.
- Dashboard/API: 41 tests passed, including summary peak/gap preservation, overlapping coverage, default extent including older files, private overview access and legacy backfill/deletion.
- Worker TypeScript and Wrangler binding checks passed.
- Local fixture preview: all seven source files automatically plotted; recorded coverage and missing-gyroscope state checked; refreshing preserved a label draft. Fixtures are local development data and are not deployed.
- Production diagnostic read before changes: Ali had 28 ready recordings / 53,273 samples. 18 background files contained 53,260 samples; 10 live fragments contained 13 samples. Raw uploads reached storage; choosing only the newest tiny fragment hid the usable history.
- Physical Watch crash root cause remains unconfirmed: developer tunnel could not be established; the connected iPhone lacked Developer Mode. The simulator did not reproduce the crash. Raw transfer pressure is reduced, not asserted as a proven root cause.

The release is archived from this task's committed source snapshot, excluding concurrent audit edits in the shared checkout. TestFlight notes are in `docs/releases/build-9.md` and must be saved/read back on exact build 9 before delivery is complete.

## Delivery evidence — October 23, 2026

- Native production source: `2a461e2`; archive `/tmp/Ciggy-Hourly-Calibration-Build9-Final.xcarchive` was generated from a clean git-archive snapshot preserving the `ciggy` checkout basename needed by that revision's local package reference. Concurrent audit product code is excluded.
- The final exact-source test run exposed one obsolete status-copy assertion. Test-only commit `637b1f0` updates that literal; the clean snapshot then passed all 179 tests. No binary production code changed for this test correction.
- All four signed executable bundles were verified as 1.0 (9), including the exact phone/Watch companion relationship. Deep/strict code-signature verification passed. Apple upload succeeded at 20:30 EDT (`EXPORT SUCCEEDED`).
- Web polish `36c2e16` removes default raw-file downloads and improves the collapsed source layout. Final Worker deployment: `d131ef0a-395f-462e-b1a9-8f9f6efcd436`, https://ciggy.thatcanadian.dev. D1 migration 0003 succeeded; final API/dashboard suite: 41 passed, TypeScript passed. Anonymous page redirects to login; private API returns 401.
- A subsequent live diagnostic read found 30 ready recordings / 59,184 samples. One representative background file contains 2,983 samples across 299.92 seconds without gaps over one second; movement varies from a median 0.011g to a measured 1.6862g peak. This verifies real recorded motion, not a cigarette classification.
- Outstanding: App Store Connect browser is signed out in the currently accessible Dia profile. The user has been asked to open the signed-in developer profile. Build 9 processing, internal tester availability and saved/read-back What to Test notes are not yet verified. Notes are prepared in `docs/releases/build-9.md`; delivery must not be described as TestFlight-complete until this is resolved. Authenticated production graph inspection is also pending that browser session; local rendered fixture verification and production storage/security/deployment checks succeeded.
