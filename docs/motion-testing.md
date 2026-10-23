# Motion detection and a physical Watch test

## What the code does

Ciggy samples `CMDeviceMotion` at a requested 30 Hz on the Watch. Every sample includes gravity, user acceleration (g), and gyroscope-derived rotation rate (radians/second). Sensor timestamps are converted from seconds since boot to dates once per stream, so delayed callbacks do not change gesture timing. Sensor errors, missing hardware, denied permission, and a stream that never supplies data are reported through `MotionManager.status` and `lastError`. `isMonitoring` becomes true only when data arrives.

The gesture engine learns a resting gravity direction, then requires a raise of about 26 degrees, a steady hold of at least 0.7 seconds, and a return toward the original pose. Both wrist orientations work without hardcoded pitch/roll signs. A static pose, brief flick, missing return, excessive movement during the hold, or a gap in sensor samples cannot complete a gesture. The defaults are prototype thresholds; they need validation against real wrist recordings.

Completed gestures feed the smoking-session engine. Normal sensitivity requires five gestures, separated by at least six seconds, within eight minutes, with no inter-gesture gap longer than 2.5 minutes. Low/high sensitivity requires seven/four gestures. One candidate creates one automatic cigarette event. Detection keeps observing later gestures and groups them into that same session until a gap of more than 2.5 minutes between accepted gestures. The next pattern must supply its own full gesture count and can be counted less than eight minutes later; there is no fixed cigarette cooldown. The eight-minute accumulation window rolls with gesture timestamps and is not a series of disconnected clock buckets. The live grouping engine saves completed gestures and counted-session state after each accepted delivery, so they survive foreground/background transitions and process relaunches; incomplete individual sensor gestures do not. A newly emitted candidate is synchronously delivered to the Watch repository before its counted-state checkpoint is saved, preserving replay recovery if the process stops between the writes. Live sample updates expire partial counts after the inter-gesture/session window, so diagnostics do not keep displaying stale progress. Reapplying sensitivity does not erase completed gestures. Heart-rate samples are optional context and never required; replayed context is deduplicated and capped to bound memory. Eating and drinking can have similar motion; the code cannot infer the object in the hand from wrist sensors alone.

`CMSensorRecorder` supplies a separate 50 Hz accelerometer-only background recording. Ciggy processes that history at 10 Hz, estimates gravity and angular movement, and does not invent historical gyroscope measurements. It saves the analyzer and cursor together between batches so partial progress and the already-counted session survive a relaunch. Missing source query results stay in persisted pending intervals while later history can advance. Retries replay those intervals with neighboring eight-minute context; unresolved intervals expire only when they fall outside the provider's three-day retention and leave a persistent indication that past totals may be incomplete. A nil query is not a successful zero-cigarette result. Historical analysis runs on foreground entry and every 60 seconds while open. Best-effort Watch refresh is requested every 30 minutes to renew capture, analyze, save and synchronize. Stable candidate IDs and retained supporting intervals (with 30 seconds of sensor timing tolerance) prevent replay duplicates and keep a corrected session from being restored by the other detection path.

Apple permits up to 12 hours of recording per request, retains history for up to three days, and can delay sample availability by three minutes. Background refresh renewal remains best-effort; open Ciggy regularly to renew recording. Continuous live gyroscope collection while suspended is not part of this implementation. See Apple's [sensor recorder documentation](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/recordaccelerometer(forduration:)) and [history retrieval documentation](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)).

## Why one cigarette may not appear

The app recognizes a motion pattern; it does not directly sense smoke or a cigarette. Detection requires the Watch on the moving hand, valid motion permission, recorded sensor coverage, a brief stable pose to learn the wrist baseline, and enough complete raise/hold/return cycles. Five puffs whose wrist tilt is too small, whose hold is brief, or whose hand never returns toward the original resting pose may produce fewer than five accepted cycles. A cigarette smoked on the other hand can produce no usable signal at all. Eating slowly or taking repeated sips can produce the same pattern and a false cigarette candidate. Lighting, tapping ash and stubbing out are not unique wrist signatures.

The background path is delayed and lower fidelity. A sleeping Watch does not supply live gyroscope samples to this app; accelerometer history must become available and be processed. Lack of a phone event can also be transport lag. Debug in this order: sensor coverage/status, completed cycle count, session count/candidate, saved event, then companion sync. Do not lower thresholds until every hand movement becomes a cigarette to hide a coverage or transport problem.

## Deterministic synthetic session sweep

`SyntheticMotionSimulationTests` is a reproducible procedural regression and stress suite. It constructs complete sessions from initial object handling, rest, raising, steady holding, lowering, inter-action pauses, final handling and rest. It varies wrist orientation and mirror, movement duration, angle, hold duration, pause duration, number of repetitions, and small smooth sensor noise. The same 10 Hz trace passes through the live gesture/fusion pipeline and the accelerometer-only filtering/fusion pipeline. All samples are generated and consumed locally in memory; they are never inserted into the user's history.

Eight scenario families cover smoking-like motions (5–10 repetitions), spoon/fork meals (8–16), drinking (1–7 sips), stationary wrists, smoking with the other hand, repeated sensor blackouts, and deliberately ambiguous hand-to-mouth motions. The parameter ranges are **explicit engineering assumptions, not measured behavioral distributions or validated motion capture**. This sweep reports how this implementation behaves on those assumptions. It is not training, and increasing the trace count does not establish real-world precision, recall, or reliable separation of smoking from eating/drinking.

The ambiguous family intentionally uses a trace that can represent all three activities. A regression test requires identical candidates for identical signals regardless of the intended object label. That limitation cannot be solved by generating more invented examples. Improvements to recognition need representative labeled real wrist recordings, including the user's normal rest positions, both wrist sides, hard negative activities and missing coverage. A small opt-in personal recording can expose a missed-motion bug, but it is not a population accuracy validation.

The default test run sweeps 800 sessions. Run a large, deterministic local sweep with:

```sh
CIGGY_SIMULATION_SESSIONS=250000 DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test -c release --filter SyntheticMotionSimulationTests.testSyntheticSessionSweep
```

The suite prints session, sample and candidate totals by scenario for each pipeline. It asserts no duplicate event IDs, no double logging within these short sessions, no candidates from motionless/opposite-wrist traces or interrupted cycles, and recovery across 100 sequential sessions with checkpoint restoration. Separate regression tests cover invalid vectors, nonfinite configuration, duplicate/backward sample delivery, invalid samples during a gesture, stale progress, repeated settings application, bounded heart-rate context and checkpoint identity.

### Recorded run: October 20, 2026

The final-source release sweep completed **250,000 full session traces**, with **303,614,390 generated samples through each pipeline** (607,228,780 combined sample deliveries), in 567.961 seconds excluding compilation. The selected sweep test passed with zero failures, duplicate IDs or safety-invariant failures. Each row contains 31,250 invented scenarios; candidate totals are **not accuracy estimates**. These totals replace the earlier 120,000-session prefix run; overlapping seeds are not counted again.

| Intended synthetic scenario | Generated samples | Live candidates | Recorded candidates |
| --- | ---: | ---: | ---: |
| Smoking-like | 47,023,999 | 21,777 | 22,715 |
| Spoon meal | 38,646,224 | 29,862 | 30,545 |
| Fork meal | 41,376,199 | 26,262 | 28,340 |
| Drinking | 22,826,841 | 9,541 | 9,831 |
| Stationary | 33,298,218 | 0 | 0 |
| Smoking with the opposite hand, Watch wrist stationary | 33,293,534 | 0 | 0 |
| Sensor interruption during every cycle | 47,008,927 | 0 | 0 |
| Deliberately ambiguous repeated hand-to-mouth | 40,140,448 | 31,250 | 31,250 |

The modeled meals triggered many false smoking candidates, and some smoking-like traces did not reach the threshold. This demonstrates why these results cannot justify claiming reliable activity recognition. Thresholds were not tuned to make invented labels look accurate. The shipped fixes address dropped progress, source coverage, synchronization, invalid inputs and duplicate handling; automatic counts remain estimates that can be corrected.

## Install later with Xcode

1. Open `ciggy/ciggy.xcodeproj` using `/Applications/dev/Xcode.app`.
2. Sign in under Xcode → Settings → Accounts. Both application targets use automatic signing; select the same valid development team for both if the saved team is unavailable.
3. Connect and unlock the paired iPhone and Apple Watch, enable Developer Mode as requested, and confirm Xcode lists the actual Watch as connected.
4. Run the `ciggy` scheme on the paired iPhone. It embeds the Watch app. Then run `ciggy Watch App` on the Watch if it has not already installed.
5. Allow Motion & Fitness access on Watch. Heart-rate read permission is optional. Ciggy does not require a server key, paid motion API, or additional Core Motion entitlement.

A signed physical-device build needs a valid Apple Account session and development profiles. An unsigned `.app` cannot be imported onto a Watch. A simulator launch or successful archive alone does not verify physical-device motion detection.

## First live test

1. Wear the Watch on the hand whose movement you want to detect. The opposite wrist cannot measure that hand's gestures.
2. Set normal sensitivity. Keep Ciggy in the foreground and check that the existing motion indicator becomes active. In Xcode's console, the `com.ciggy.motion` / `Sensors` log reports the first sample and each completed cycle.
3. Start with the hand at rest for one second. Mimic your usual cigarette hand-to-mouth motion with an empty hand: raise, hold steadily for roughly one to three seconds, then lower to rest.
4. Repeat five times, approximately 15–30 seconds apart. Expect five completed-cycle logs and one automatic cigarette event/review. Opening the iPhone companion should show the same event; durable background sync on hardware can arrive later.
5. Check negative examples separately: sit still, hold the wrist up without lowering it, make a brief flick, and try eating/drinking gestures. Record which cycles and cigarette candidates the detector accepts. Continue a long pattern to verify it stays at one count, then leave more than 2.5 minutes without an accepted cycle and repeat a full pattern. The next count should appear even when less than eight minutes separates the two counts. Test genuinely close cigarettes separately: without a recognized gap the current motion-only rule can merge them, and missed gestures can create a false gap.
6. To exercise history, leave Ciggy in the background, perform a labelled test period, wait at least three minutes, and reopen it. Historical results can differ from live results because this path has acceleration only. Reopening should not duplicate an already recorded live cigarette.

## Opt-in raw capture without adding UI

In the **Debug Watch scheme**, Edit Scheme → Run → Arguments, enable `-CiggyRecordMotion`. Run the Watch app again. This records up to five minutes of real samples, ending earlier if the app enters the background, and queues the resulting JSON for transfer to the paired iPhone. The flag exists only in Debug builds. Normal launches do not capture raw recordings. No synthetic motion is substituted on physical hardware.

Files are stored in each app's private Application Support directory under `CiggyMotionRecordings`. The iPhone validates the incoming file, preserves its recording ID and subsecond timestamps, and exposes `MotionRecordingStore.shared.latestRecordingURL`. Retrieve the app container through Xcode's device tools when supported, or attach a share action in the UI to that URL. File transfer requires physical paired devices; Simulator does not exercise this path.

The APIs available to the UI chat are:

- `MotionManager.shared`: `status`, `lastError`, `isMonitoring`, `hasGyroscope`, `latestSample`, `gesturePhase`, `observedGestureCount`, and `samplePublisher`. UI diagnostics update at 5 Hz; processing remains at 30 Hz.
- `MotionManager.shared.configureGestureDetection(configuration)`: tune the raise, hold, return, and timing criteria for calibration. Reset `DetectionAlgorithm`'s session when changing a profile.
- `DetectionAlgorithm.sessionGestureCount` and `resetSession()`: observe/reset the partial smoking session.
- `MotionRecordingStore.shared.start(label:duration:)`: opt-in capture with a smoking-gesture, eating, drinking, other, or unlabelled label. The duration is capped at ten minutes / 18,000 samples.
- `finishIfRecording()`, `latestRecordingURL`, `lastError`, and `deleteRecordings()`: finish, share, and remove private recordings.
- `ConnectivityManager.shared.sendMotionRecording(at:)`: explicitly queue a recording for the paired companion. Automatic transfer happens only when the opt-in Debug flag is used.

## Checks

Use the full toolchain explicitly:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The iPhone scheme also builds and embeds the Watch target. Shared tests cover valid/rejected gestures, mirrored orientations, malformed and out-of-order samples, acceleration-only analysis, checkpoint/replay identity, restart-safe synchronization, corrected-session deduplication, and raw recording/import. Simulator and unsigned-device builds verify platform compilation. Detection accuracy, battery life, permission prompts, and background delivery still need physical hardware testing.
