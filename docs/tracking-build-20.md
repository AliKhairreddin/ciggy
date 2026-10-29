# Tracking timing — build 20

Product commit `1c17e22` is pushed to `origin/main`. Build 1.0 (20) replaces Watch background refresh appointments that expired during a foreground session and labels review timestamps as estimated logs. Saved counts, correction scopes and recognition thresholds are unchanged. The [investigation](tracking-review-investigation.md) explains the confirmed defect, remaining timing constraints and posture-related blind spots.

## Validation

- Full Xcode toolchain: 316 shared Swift tests passed, including foreground-expiry scheduling, review timing, empty checks, pending-review merging, correction persistence and synthetic motion across resting orientations, motion planes and smaller excursions.
- The existing paired iPhone simulator passed five native unit tests and three UI tests for review creation, correction persistence across relaunch and Tracking details navigation.
- Its paired Watch simulator passed both native unit tests. The initial iPhone test run stalled in temporary Xcode simulator copies; the completed run disabled parallel test destinations and used the established paired simulator directly.
- Reviewed the rendered iPhone review cards and Tracking details. Estimated logs and original estimates wrap within their cards.
- Verified iOS/watchOS source membership, both shared-library links, Watch dependency/embedding and the exact companion bundle identifier.
- Signed Release archive succeeded. iPhone, Watch and both widget extensions all report 1.0 (20), with verified code signatures.
- Reviewed staged files for whitespace errors, secrets, tester-specific evidence and generated files. Motion fixtures use invented data only.

These checks establish software behavior and build integrity. They do not establish physical-device background latency or seated/standing detection accuracy.

## Delivery status

Xcode successfully uploaded build 1.0 (20) to App Store Connect and reported `EXPORT SUCCEEDED`; Apple reported that the package had begun processing. This native update requires no server deployment.

TestFlight delivery is **verified**. Apple finished processing [build 1.0 (20)](https://appstoreconnect.apple.com/teams/a4ef6364-db9c-4a79-817d-bf54fd43e9da/apps/6824809527/testflight/ios/70a1b393-0ade-474f-90ef-1aefcbca4706). The build-specific 1,526-character English (Canada) [What to Test body](releases/build-20.md) was saved in App Store Connect and matched exactly after a full page reload. The existing internal tester group is assigned and lists this exact build as **Testing**, confirming availability to its testers. External testing is not part of this delivery.
