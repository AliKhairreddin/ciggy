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
