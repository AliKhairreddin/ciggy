# Motion detection and a physical Watch test

## What the code does

Ciggy samples `CMDeviceMotion` at a requested 30 Hz on the Watch. Every sample includes gravity, user acceleration (g), and gyroscope-derived rotation rate (radians/second). Sensor timestamps are converted from seconds since boot to dates once per stream, so delayed callbacks do not change gesture timing. Sensor errors, missing hardware, denied permission, and a stream that never supplies data are reported through `MotionManager.status` and `lastError`. `isMonitoring` becomes true only when data arrives.

The gesture engine learns a resting gravity direction, then requires a raise of about 26 degrees, a steady hold of at least 0.7 seconds, and a return toward the original pose. Both wrist orientations work without hardcoded pitch/roll signs. A static pose, brief flick, missing return, excessive movement during the hold, or a gap in sensor samples cannot complete a gesture. The defaults are prototype thresholds; they need validation against real wrist recordings.

Completed gestures feed the smoking-session engine. Normal sensitivity requires five gestures, separated by at least six seconds, within eight minutes, with no inter-gesture gap longer than 2.5 minutes. Low/high sensitivity requires seven/four gestures. One candidate creates one automatic cigarette event and starts an eight-minute cooldown. Heart-rate samples are optional context and never required. Eating and drinking can have similar motion; the code cannot infer the object in the hand from wrist sensors alone.

`CMSensorRecorder` supplies a separate 50 Hz accelerometer-only background recording. Ciggy processes that history at 10 Hz, estimates gravity and angular movement, and does not invent historical gyroscope measurements. It saves the analyzer and cursor together between batches so a partial session or cooldown survives a relaunch. Historical analysis no longer skips a backlog when live monitoring ends. Stable candidate IDs make replay idempotent, and a retained record of automatic-session times prevents the lower-fidelity history path from restoring a corrected foreground session.

Apple permits up to 12 hours of recording per request, retains history for up to three days, and can delay sample availability by three minutes. Background refresh renewal remains best-effort; open Ciggy regularly to renew recording. Continuous live gyroscope collection while suspended is not part of this implementation. See Apple's [sensor recorder documentation](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/recordaccelerometer(forduration:)) and [history retrieval documentation](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)).

## Install later with Xcode

1. Open `ciggy/ciggy.xcodeproj` using `/Applications/dev/Xcode.app`.
2. Sign in under Xcode → Settings → Accounts. Both application targets use automatic signing; select the same valid development team for both if the saved team is unavailable.
3. Connect and unlock the paired iPhone and Apple Watch, enable Developer Mode as requested, and confirm Xcode lists the actual Watch as connected.
4. Run the `ciggy` scheme on the paired iPhone. It embeds the Watch app. Then run `ciggy Watch App` on the Watch if it has not already installed.
5. Allow Motion & Fitness access on Watch. Heart-rate read permission is optional. Ciggy does not require a server key, paid motion API, or additional Core Motion entitlement.

A signed physical-device build needs a valid Apple Account session and development profiles. An unsigned `.app` cannot be imported onto a Watch. At the time this change was validated, Xcode rejected its saved account login and the paired Watch was disconnected. Installation was deferred at the user's request.

## First live test

1. Wear the Watch on the hand whose movement you want to detect. The opposite wrist cannot measure that hand's gestures.
2. Set normal sensitivity. Keep Ciggy in the foreground and check that the existing motion indicator becomes active. In Xcode's console, the `com.ciggy.motion` / `Sensors` log reports the first sample and each completed cycle.
3. Start with the hand at rest for one second. Mimic your usual cigarette hand-to-mouth motion with an empty hand: raise, hold steadily for roughly one to three seconds, then lower to rest.
4. Repeat five times, approximately 15–30 seconds apart. Expect five completed-cycle logs and one automatic cigarette event/review. Opening the iPhone companion should show the same event; durable background sync on hardware can arrive later.
5. Check negative examples separately: sit still, hold the wrist up without lowering it, make a brief flick, and try eating/drinking gestures. Record which cycles and cigarette candidates the detector accepts. A second cigarette candidate is intentionally suppressed during the eight-minute cooldown.
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
