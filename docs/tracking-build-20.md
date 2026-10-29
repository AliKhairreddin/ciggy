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

TestFlight delivery is **not yet fully verified**. The App Store Connect browser session requires sign-in, preventing verification of finished processing, final tester-group assignment and tester availability. The build-specific 1,526-character [What to Test body](releases/build-20.md) is prepared locally but has **not** been saved or read back in App Store Connect. Complete those steps on this exact build after sign-in before reporting TestFlight delivery complete.
