# ciggy

WatchOS ciggy tracker with IOS companion app.

## Product idea

Ciggy is an Apple Watch-first smoking tracker that combines manual logging with motion-first assisted detection. The watch app records events at the moment they happen, and the iOS companion app shows daily progress, trends, goals, settings, and received watch events.

## Is this a good idea?

Yes, with the right expectations. A low-friction smoking tracker can help users understand routines, reduce under-reporting, and connect behavior with goals. The strongest product angle is habit awareness: make logging effortless, show useful trends, and nudge users without shame.

The automatic-detection idea is useful as a supporting feature, not as the only source of truth. Smoking gestures vary by person, watch wrist, device orientation, and context, so automatic events are presented as a passive summary with optional **Accurate** and **Adjust count** feedback. This preserves low-friction tracking without hiding uncertainty or interrupting the user after every cigarette.

## Hardware feasibility

The concept is feasible on Apple Watch hardware, but accuracy depends on sensor availability and runtime constraints:

- **Motion sensors:** Apple Watch provides accelerometer/gyroscope-derived device motion through Core Motion, which can detect repeated hand-to-mouth-like movement patterns.
- **Heart-rate data:** HealthKit can add optional context when the user authorizes access. It is not required to create a detection candidate because sample frequency is not guaranteed.
- **Battery:** Continuous motion and heart-rate monitoring can drain the watch battery. The production app should support user-controlled detection windows, adaptive sampling, and conservative defaults.
- **Device placement:** Detection works best when the watch is worn on the hand used for smoking. Opposite-wrist use is likely to reduce accuracy.

## Software feasibility

The current codebase already has the main software building blocks:

- A watchOS app that starts motion, optional HealthKit context, and event detection, with explicit sensor and background status.
- An iOS companion app with dashboard, reports, goals, and settings screens.
- Shared models and repositories for smoking events.
- WatchConnectivity-based event forwarding from watchOS to iOS.
- A motion-first detection pipeline that reads gravity, user acceleration, and gyroscope-derived rotation rate, verifies complete raise/hold/return cycles relative to the resting wrist, and groups repeated cycles into one probable smoking session.
- A five-minute duration estimate combined with repeated matching movements: five at normal sensitivity, four/seven at high/low sensitivity. Continued qualifying motion can produce successive estimated cigarettes without a quiet gap.
- Optional heart-rate context attached when HealthKit happens to provide samples; heart rate never gates a detection.
- Automatic logging of probable detections into one quiet, reviewable summary instead of a blocking prompt for every event.
- Synchronized **Accurate** and **Adjust count** feedback that can support future threshold tuning.
- Idempotent addition and deletion delivery, including deletion tombstones that prevent delayed transfers from restoring corrected events.

The current automatic detector is intentionally conservative and still requires real-world calibration. It is enough for prototyping, demos, and collecting early user feedback, but it should not be marketed as medically accurate or reliable without validation.

The prototype never substitutes generated heart-rate data on a physical device. Simulator-only data is visibly labeled, heart-rate context uses HealthKit sample timestamps, and notification/sensitivity settings are synchronized between the phone and Watch.

Automatic collection uses two complementary paths. While Ciggy is visible, it processes live device motion and any heart-rate samples that watchOS saves. On a physical Apple Watch, it also arms `CMSensorRecorder` for up to 12 hours of historical 50 Hz accelerometer capture that continues while Ciggy is suspended or terminated. When Ciggy next opens, it retrieves samples that are old enough to be available, downsamples them for efficient analysis, automatically logs probable smoking sessions, and creates one history summary on both devices. Historical analysis preserves its classifier and cursor together across app launches; live monitoring does not discard an unprocessed backlog, and history does not duplicate previously logged or corrected automatic sessions.

The build 16 background path requests a refresh with a 15-minute preferred date to analyze saved motion and renew the 12-hour recording window. It preserves an earlier pending request and recovers scheduling after interrupted work. Every WatchConnectivity background wake also renews recording and checks recent motion. Opening the iPhone requests a bounded, durable Watch history check; delivery and execution depend on watchOS. A recent-first pass checks the latest 15 minutes with eight preceding minutes of classifier context before chronological reconciliation, preserving the older cursor and missing intervals. Counts are analyzed, saved, and queued for synchronization before optional calibration extraction, which receives at most 0.75 seconds from a three-second total background processing budget. Foreground monitoring checks history every minute, and every foreground launch re-arms capture. A background-only launch initializes the same event stores and sync handlers as a visible launch. See [background tracking](docs/background-tracking.md) for the work order, Apple platform limits, and physical-device test protocol.

A Ciggy complication on the active Watch face gives background checks more opportunities, but watchOS can delay or omit them. The 15-minute preferred date is not a guaranteed interval, and the five-minute detector window is not a promise of an iPhone update within five or ten minutes. Newly recorded samples can take up to three minutes to become retrievable, history is retained for up to three days, and `CMSensorRecorder` is unavailable in Simulator. The interface shows the latest recorded motion time and pending/gap states separately from sync reachability. Detection reviews are scoped to local calendar days, with today first and earlier days separately accessible. Automatic detections are included when saved and stay visibly reviewable; users can correct the count without answering a prompt each time. Physical-device latency measurements and real-world calibration remain necessary.

Build 20 replaces background appointments that watchOS ignored while Ciggy was foregrounded. Reviews label estimated log times separately from the history scan's wider window; a check with no new detections does not create a review. See the [tracking timing and wrist-posture investigation](docs/tracking-review-investigation.md) for the confirmed scheduling defect, remaining latency limits, and small-motion blind spots.

## Tracking experience

The iPhone bottom bar contains **Today**, **Reports**, **Goals**, and **League**. Open Settings through the profile icon at the top right of Today; the Watch also uses its header profile icon. Manual entry remains available as a small **Add missed cigarette** action, and automatic detections remain reviewable with **Accurate** and **Adjust count**.

Detection is an estimate from wrist motion, not a measurement of the object in the hand. Normal sensitivity requires at least five completed raise/hold/return cycles and at least five minutes of continuing qualifying activity. The first duration starts at the first recognized gesture; after a count, another five-minute segment with fresh gestures can create another count without a quiet gap. More than 2½ minutes between accepted gestures breaks the accumulated evidence, so idle time cannot turn into extra cigarettes. The five-minute default is an engineering estimate informed by measured smoking durations, **not an established global average**. Shorter cigarettes can be missed and a long single cigarette can be split. See the [duration evidence and counting rules](docs/cigarette-duration.md).

The Watch must be on the moving hand. Stopping or restarting live sensors clears incomplete live duration; unavailable source intervals cannot establish continuous smoking. Saved accelerometer history can separately catch up when it contains continuous motion. The first estimate needs five minutes of qualifying evidence, plus any delay before watchOS supplies and processes the recording and delivers the event to iPhone. This does not guarantee a five-minute iPhone update.

Synthetic tests exercise full assumed smoking, spoon/fork eating, drinking, resting, opposite-wrist and interrupted-data scenarios through both live-motion and historical-acceleration pipelines. They are deterministic software stress tests, **not training data or proof of real-world accuracy**. Identical wrist traces cannot be distinguished by labeling them differently. See [the motion test guide](docs/motion-testing.md) for the reproducible large-sweep command and historical results. Earlier [reliability validation](docs/reliability-validation.md) and measured replay results predate the duration rule and do not validate its accuracy.

## Ashtray League

An optional global leaderboard ranks weekly cigarette counts from highest to lowest. Join under a generated Ciggy alias, see the top 50 and your own position, and browse this week or last week. Equal totals share a rank; the weekly edition resets Monday at 00:00 UTC. The podium has questionable bragging rights and no prizes.

Joining shares only your alias and the current and previous weeks’ aggregate cigarette totals. Counts include saved manual logs and automatic estimates; corrections and delayed Watch delivery update the league when the iPhone synchronizes. Nothing is shared until you join, and leaving deletes your public league record. See [league rules and implementation](docs/leaderboard.md) and [privacy](docs/privacy.md).

## Private calibration

The optional dashboard at `https://ciggy.thatcanadian.dev` compares real wrist-motion recordings by tester, date, and source. Authorized testers can mark smoking, eating, drinking, and other intervals and export a labeled dataset. Each tester pairs and explicitly opts in from iPhone Settings → Private motion calibration. The Watch sends five-minute, 10 Hz historical chunks to iPhone when runtime permits; the iPhone queues Wi-Fi uploads in a background URLSession. Background acceleration has estimated gravity and no gyroscope. Recording gaps and delayed delivery remain visible.

Sharing defaults off; no pre-consent recordings are uploaded. Credentials stay in Keychain, reads require Cloudflare Access, uploads are deduplicated per tester and recording ID, unsent local data is bounded to 48 hours, and shared raw data plus labels expire after 14 days. Pausing and confirmed server deletion are available in the iPhone app. See [privacy](docs/privacy.md) and [calibration deployment](CalibrationDashboard/README.md).

The [research and benchmark guide](docs/motion-research.md) documents the supplied studies and a reproducible replay of measured SED data. This release does not ship a trained classifier or claim that labeling immediately teaches the app.

## iPhone Duo

Ciggy uses the native iOS 27.1 hinge and reserved-region APIs for the cover display, fully open layouts, book mode, and half-open desk mode. The fold's actual frame and interactive margins keep independently scrollable content and controls clear as its angle changes. Rotation preserves notes, goals, and report selections. The native laptop pose also unlocks an immersive ashtray scene above a full-width ambient music player, with ten randomly selected scenic backgrounds. This Easter egg is exclusive to Duo desk mode; adjusting the hinge or rotation restores tracking. See [the Duo guide](docs/iphone-duo.md) for layouts and native simulator validation.

## Technical risks

- False positives from eating, drinking, shaving, brushing teeth, or similar hand-to-mouth gestures.
- False negatives when users smoke with the non-watch hand.
- Battery drain from continuous motion sensing.
- HealthKit authorization and availability differences across devices.
- Privacy expectations around sensitive behavioral and health-adjacent data.

## Motion APIs and live Watch testing

See [the motion test guide](docs/motion-testing.md) for sensor details, physical-device installation, an empty-hand gesture test, opt-in raw recording, and APIs for the UI to display diagnostics or collect labelled calibration data.

Outgoing event/review mutations and incoming messages received before repositories are ready now persist across app restarts. Live sync acknowledges receipt, while physical devices also use durable WatchConnectivity transfers.

## Daily roasts and achievements

Enable **Daily roasts & summaries** in iPhone Settings and save to allow local notifications. The catalog has 110 distinct messages across 11 scenarios: the first cigarette, 5/10/15/20 cigarettes, higher counts, reaching a custom daily limit, exceeding that limit, staying below it, cutting down from the previous day, and a day with zero logged cigarettes. Each scenario cycles through all ten messages before repeating, with rotation saved across launches.

Manual iPhone logs and received Watch events trigger daily milestones at 1 and every multiple of 5, plus the daily limit and the first count above it. Bursts of synced events are combined into one alert with the current count. iPhone owns these milestone notifications so the Watch's copy of the same event cannot generate a second roast. Normal system notification routing can show iPhone notifications on its paired Watch.

Positive achievements review yesterday's completed day when the iPhone next opens or receives events. They use logged history, require tracking to have started before that day, and are delivered at most once per day. They do not assume an empty fresh install proves a smoke-free day. Notifications stay off until enabled; old milestones do not replay on launch, when notifications are enabled, or after correcting a count. **Preview a roast** cycles through the full catalog using labeled sample notifications without changing smoking history.

## Widgets and Dynamic Island

Ciggy includes five widget choices — Today, Daily Budget, Since Last Log, Your Week, and Quick Log — for Home Screen, Lock Screen, and Watch complications/Smart Stack. It also includes three iOS controls and an optional Live Activity for the Lock Screen and Dynamic Island. See [the widget guide](docs/widgets-and-live-activities.md) for sizes, setup, update behavior, and signing requirements.

## Development

With an Xcode developer toolchain selected, run `swift test` to execute the deterministic motion-session, motion-debounce, persistence, and fresh-install metric tests. The package also exposes separate `CiggyiOS` and `CiggyWatch` products for platform builds.

See [TestFlight delivery](docs/testflight.md) for signing, archiving, and beta distribution, and the [privacy policy](docs/privacy.md) for the current data practices.

See [private motion delivery](docs/calibration-delivery.md) for opt-in Watch → iPhone → dashboard uploads, timing, status checks, gap recovery, and labeling back-to-back cigarettes.

## iPhone and Watch simulator sync

The iPhone and Watch apps have separate local stores. They synchronize automatic and manual events, event deletions, detection reviews, and feedback through WatchConnectivity rather than directly sharing simulator storage.

Apple's Simulator does not deliver `transferUserInfo(_:)`, even though that API provides durable background delivery on paired physical devices. Ciggy therefore sends every event/review mutation in two ways:

- `sendMessage` for immediate delivery while both companion apps are live. This is the path used by Simulator.
- `transferUserInfo` for durable, at-least-once delivery on real paired devices. Duplicate event IDs and review revisions are ignored, while deletion tombstones reject stale event deliveries.

To test a Watch log in the iPhone companion app:

1. In Xcode's Devices and Simulators/Device Hub, create or select an Apple Watch simulator paired with the exact iPhone simulator you will run.
2. Run the `ciggy` scheme on that iPhone simulator. This scheme builds and embeds the matching Watch product.
3. Open the embedded Ciggy app on the Watch simulator belonging to the same pair. If it is not installed, select that paired Watch destination and run the `ciggy Watch App` scheme, then relaunch the iPhone scheme so Xcode registers the companion pair.
4. Keep both apps open. Wait for **Live sync** on iPhone and **iPhone live** on Watch.
5. Log a cigarette on Watch. It should appear immediately on the iPhone dashboard.
6. In a Debug build, open Settings on either device and choose **Preview 6 detected in 8 hours** to exercise the historical summary without waiting for physical Watch sensor history. Marking it accurate or adjusting it on either device synchronizes the result to the other.

If the UI says **Install Watch**/**Install iPhone app**, Xcode has not registered the two installed products as companions. If it says **Open Watch** or **Open iPhone to sync**, the counterpart is installed but not reachable. Recheck that the destinations are the same simulator pair, launch both apps again, and keep both running. Simulator-only queued delivery is not available; validate background delivery on physical paired devices.

Apple reference: [`transferUserInfo(_:)`](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo%28_%3A%29).
