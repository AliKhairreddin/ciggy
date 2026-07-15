# ciggy

WatchOS ciggy tracker with IOS companion app.

## Product idea

Ciggy is an Apple Watch-first smoking tracker that combines manual logging with motion-first assisted detection. The watch app records events at the moment they happen, and the iOS companion app shows daily progress, trends, goals, settings, and received watch events.

## Is this a good idea?

Yes, with the right expectations. A low-friction smoking tracker can help users understand routines, reduce under-reporting, and connect behavior with goals. The strongest product angle is habit awareness: make logging effortless, show useful trends, and nudge users without shame.

The automatic-detection idea is useful as a supporting feature, not as the only source of truth. Smoking gestures vary by person, watch wrist, device orientation, and context, so the app should always let users confirm, dismiss, or manually add events. Treating automation as "probable event detection" keeps the product trustworthy and avoids frustrating false positives.

## Hardware feasibility

The concept is feasible on Apple Watch hardware, but accuracy depends on sensor availability and runtime constraints:

- **Motion sensors:** Apple Watch provides accelerometer/gyroscope-derived device motion through Core Motion, which can detect repeated hand-to-mouth-like movement patterns.
- **Heart-rate data:** HealthKit can add optional context when the user authorizes access. It is not required to create a detection candidate because sample frequency is not guaranteed.
- **Battery:** Continuous motion and heart-rate monitoring can drain the watch battery. The production app should support user-controlled detection windows, adaptive sampling, and conservative defaults.
- **Device placement:** Detection works best when the watch is worn on the hand used for smoking. Opposite-wrist use is likely to reduce accuracy.

## Software feasibility

The current codebase already has the main software building blocks:

- A watchOS app that starts motion, HealthKit, and event detection.
- An iOS companion app with dashboard, reports, goals, and settings screens.
- Shared models and repositories for smoking events.
- WatchConnectivity-based event forwarding from watchOS to iOS.
- A motion-first detection pipeline that groups repeated, separated hand-to-mouth movements into one probable smoking session.
- Default prototype grouping of five matching movements within eight minutes, with sensitivity settings ranging from four to seven movements.
- Optional heart-rate context attached when HealthKit happens to provide samples; heart rate never gates a detection.
- A Watch confirmation prompt that keeps probable detections out of the event history until the user confirms them.
- Local confirmation and dismissal feedback that can support future threshold tuning.

The current automatic detector is intentionally conservative and still requires real-world calibration. It is enough for prototyping, demos, and collecting early user feedback, but it should not be marketed as medically accurate or reliable without validation.

The prototype never substitutes generated heart-rate data on a physical device. Simulator-only data is visibly labeled, heart-rate context uses HealthKit sample timestamps, and notification/sensitivity settings are synchronized between the phone and Watch.

Automatic collection is currently a foreground prototype: it observes wrist motion and any heart-rate samples that watchOS saves while Ciggy is running. It does not start a workout or claim continuous background detection. Real-device calibration is still required before treating assisted detection as dependable.

## Recommended implementation path

1. **Manual-first MVP**
   - Keep manual watch logging fast and prominent.
   - Make iOS reports and goals useful before relying on automation.
   - Add clear privacy messaging for HealthKit and motion data.

2. **Assisted detection**
   - Use the regularity of repeated hand-to-mouth motion to create "possible smoking event" prompts.
   - Keep heart rate as optional supporting context rather than a requirement.
   - Ask users to confirm or reject detected events.
   - Store feedback so thresholds can be tuned per user.

3. **Personal calibration**
   - Let users record a short calibration period.
   - Adjust gesture count, orientation, timing, and dominant-hand thresholds based on their baseline.
   - Add quiet hours and known false-positive contexts.

4. **Validation and safety**
   - Measure precision, recall, false positives, and false negatives with real users.
   - Avoid medical claims unless supported by formal validation.
   - Keep export/delete controls clear for privacy compliance.

## Technical risks

- False positives from eating, drinking, shaving, brushing teeth, or similar hand-to-mouth gestures.
- False negatives when users smoke with the non-watch hand.
- Battery drain from continuous motion sensing.
- HealthKit authorization and availability differences across devices.
- Privacy expectations around sensitive behavioral and health-adjacent data.

## Bottom line

This is possible in hardware and software terms, and it is a worthwhile idea if positioned as a supportive habit-tracking app rather than a perfect detector. The best next step is to ship a manual-first MVP, add assisted detection behind clear user controls, and improve the detector with opt-in confirmation feedback.

## Development

With an Xcode developer toolchain selected, run `swift test` to execute the deterministic motion-session, motion-debounce, persistence, and fresh-install metric tests. The package also exposes separate `CiggyiOS` and `CiggyWatch` products for platform builds.

## iPhone and Watch simulator sync

The iPhone and Watch apps have separate local stores. They synchronize confirmed and manual events through WatchConnectivity rather than directly sharing simulator storage.

Apple's Simulator does not deliver `transferUserInfo(_:)`, even though that API provides durable background delivery on paired physical devices. Ciggy therefore sends each event in two ways:

- `sendMessage` for immediate delivery while both companion apps are live. This is the path used by Simulator.
- `transferUserInfo` for durable, at-least-once delivery on real paired devices. Duplicate event IDs are ignored by the repository.

To test a Watch log in the iPhone companion app:

1. In Xcode's Devices and Simulators/Device Hub, create or select an Apple Watch simulator paired with the exact iPhone simulator you will run.
2. Run the `ciggy` scheme on that iPhone simulator. This scheme builds and embeds the matching Watch product.
3. Open the embedded Ciggy app on the Watch simulator belonging to the same pair. If it is not installed, select that paired Watch destination and run the `ciggy Watch App` scheme, then relaunch the iPhone scheme so Xcode registers the companion pair.
4. Keep both apps open. Wait for **Live sync** on iPhone and **iPhone live** on Watch.
5. Log a cigarette on Watch. It should appear immediately on the iPhone dashboard.

If the UI says **Install Watch**/**Install iPhone app**, Xcode has not registered the two installed products as companions. If it says **Open Watch** or **Open iPhone to sync**, the counterpart is installed but not reachable. Recheck that the destinations are the same simulator pair, launch both apps again, and keep both running. Simulator-only queued delivery is not available; validate background delivery on physical paired devices.

Apple reference: [`transferUserInfo(_:)`](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo%28_%3A%29).
