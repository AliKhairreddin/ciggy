# Reliability update — 20 October 2026

## What changed

- Removed the iPhone Settings tab. Profile access remains on Today and Watch; explicit Today/log deep links clear the iPhone profile stack.
- Replaced the large manual-log actions with secondary **Add missed cigarette** controls. Save guards prevent repeat taps, notes survive rotation, and iPhone undo remains available.
- Bound event repositories during background-only launches on both devices. Watch refresh work now keeps its system task alive for bounded history analysis or queued connectivity delivery, with cancellation on expiration.
- Retained completed gesture progress across short Watch background interruptions. Historical analysis runs on foreground catch-up and best-effort system refresh instead of only once on opening. Unavailable history intervals remain pending for retry; expired coverage leaves an incomplete-history status.
- Hardened sensor vectors, timestamps, configurable thresholds, optional heart-rate history, persisted settings/reviews, raw recording imports, and integer conversions.
- Corrected stale count adjustments when new automatic events merge while an adjustment sheet is open. Added cigarettes stay within the review window instead of being placed in the future.
- Updated calendar totals on wake, time changes and periodic refresh; future events no longer inflate the iPhone dashboard.

## Investigation of the missed cigarette

No raw sensor recording or device log from the reported cigarette was available, so its exact cause cannot be reconstructed. The code exposed several plausible failure paths: live Watch motion stops when the app backgrounds, completed puff progress was reset at that point, historical motion was only analyzed on the next foreground opening, and background launches could receive sync before event stores were bound. These behaviors have been addressed where the platform permits.

The existing detector requires repeated complete raise/hold/return cycles (five at normal sensitivity). Its eight-minute cooldown and automatic-session deduplication can suppress separate cigarettes smoked close together. It does not see the cigarette, flame, smoke, food, or water. Opposite-wrist smoking, gestures with little wrist tilt, and gestures lacking a return to the learned resting pose may still be missed. Core Motion history contains accelerometer data only, so its estimates can differ from live fused motion.

## What the simulations mean

The deterministic generator models initial handling/lighting-like movement, repeated raises/holds/returns, pauses, and finishing movement. Separate invented scenarios cover spoon eating, fork eating, drinking, stationary/opposite-wrist activity, missing samples and deliberately ambiguous hand-to-mouth movement. Parameters vary wrist orientation, gesture angles, timing and low-amplitude noise. These are assumptions, not measurements of human behavior.

The final-source release sweep generated 250,000 full session traces and 303,614,390 samples through each pipeline (607,228,780 combined sample deliveries), passing in 567.961 seconds excluding compilation. These totals count only the final run; earlier overlapping seeds are not added. Every generated trace passes through both the live gesture/session pipeline and the accelerometer-only history pipeline. Tests check duplicate suppression, cooldown recovery, checkpoint replay, invalid values and incomplete sensor cycles. Identical input traces deliberately receive identical output regardless of an imagined object label. The sweep does not train a model, and its category counts are not sensitivity, specificity, or expected real-world performance. Full counts and the reproduction command are in [motion-testing.md](motion-testing.md).

The sweep produced many eating/drinking candidates and missed some smoking-like traces. This demonstrates overlap under the chosen assumptions, not its real-world frequency. Simulations cannot justify a promise of reliable automatic distinction or a guarantee of zero crashes. A validated classifier would require labeled real sensor recordings, held-out participants, and physical-device battery/background testing. The small manual correction path remains available for missed or false detections.

## Calibration without recruiting a large new cohort

Existing measured datasets offer a more useful next step than additional invented labels. The [University of Twente's research catalogue](https://www.utwente.nl/en/eemcs/ps/research/dataset/) lists over 40 hours of smoking and similar activities, with research-use terms. The [SED/SED-FL study](https://arxiv.org/abs/2109.03475) describes publicly available semi-controlled and free-living smartwatch recordings with participant-held-out evaluation. Neither dataset was used to train or validate this release.

Before integrating a learned model, verify dataset usage terms, sensor axes/units, wrist placement and labels; evaluate on participants excluded from training, and separately evaluate accelerometer-only history because it lacks the live gyroscope. A smaller Apple Watch validation set is still needed to measure how well results transfer to this app and device. Dataset/model accuracy must be measured independently of the synthetic regression suite.

## Platform limits

Apple makes historical accelerometer samples available after a delay of up to three minutes and retains them for up to three days. The app requests up to twelve hours of recording and must renew it. System background refresh is best-effort; no code change here guarantees immediate, continuous background detection. See [Apple sensor history documentation](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)) and [background task guidance](https://developer.apple.com/documentation/watchkit/using-background-tasks).

## Validation and delivery

- Full shared Swift package suite: **111 tests passed**, covering detection, malformed input, settings, repositories, transport, count corrections, history reconciliation, and widget snapshots.
- iPhone simulator UI: **14 distinct functional scenarios passed across focused runs**, covering profile-only Settings, secondary manual logging, cancel/save/undo, drafts across rotation, large text, goals/appearance persistence, historical review, deep links and Live Activity start/restoration/stop. The final two rotation cases passed together with zero failures after their scroll helpers were corrected to avoid skipping the smaller action or querying an offscreen activation point.
- Watch simulator UI: **2 tests passed**, covering secondary logging with one saved event across relaunch and appearance persistence.
- Paired simulator event delivery: **passed**. A manual event queued on Watch while the companion was unavailable later appeared with the same event ID exactly once in the paired iPhone repository; the Watch outbox was acknowledged and cleared. Both repositories retained the event through reinstall. Initial simulator shell/first-unlock delays postponed delivery. A subsequent certificate-signed simulator launch attempt was denied by launchd (`NSPOSIXErrorDomain` 163), so this delivery result applies to the earlier running simulator builds. Physical-device background delivery remains untested.
- Signed Release archive: succeeded with iPhone app, embedded Watch app, and both widget extensions. All four bundles are version **1.0 (3)**, and the Watch companion identifier matches the iPhone bundle identifier.
- Project integrity: source memberships, shared library links, Watch embedding/dependency, plist syntax, and whitespace checks passed. Navigation intent metadata is present directly in both iPhone and widget executables.
- Cleanup: both paired simulators were restored to the final normal Xcode products, launched successfully, and retained the synchronized event exactly once with empty transport queues.

Initial unsigned simulator tests exposed a WidgetKit assertion: App Intents daemons rejected the extension because it lacked a signing team identity. Custom signing experiments on temporary simulator artifacts were refused by launchd. A clean build with Xcode's default simulator signing restored normal launches and the final UI tests passed without another widget crash. Use normal Xcode signing for runtime UI checks. Physical-device control taps and background sensor/battery behavior remain untested; the separately signed Release archive was not changed by these simulator experiments.

Distribution: product commit `9e2a5ee` was pushed to `origin/main`. The existing Xcode App Store Connect workflow uploaded version **1.0 (3)** successfully on 20 October 2026 at 18:43 Toronto time (`EXPORT SUCCEEDED`); Apple reported **Uploaded package is processing**. The archive contains the iPhone app, Watch app and both widget extensions. App Store Connect is signed out in the available browser, so completed processing and tester availability are **not yet verified**. No additional upload is needed; sign in and check this build in TestFlight. Physical-device installation/monitoring has not been verified in this task.
