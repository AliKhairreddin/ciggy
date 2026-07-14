# ciggy

WatchOS ciggy tracker with IOS companion app.

## Product idea

Ciggy is an Apple Watch-first smoking tracker that combines manual logging with optional automatic detection. The watch app records events at the moment they happen, and the iOS companion app shows daily progress, trends, goals, settings, and received watch events.

## Is this a good idea?

Yes, with the right expectations. A low-friction smoking tracker can help users understand routines, reduce under-reporting, and connect behavior with goals. The strongest product angle is habit awareness: make logging effortless, show useful trends, and nudge users without shame.

The automatic-detection idea is useful as a supporting feature, not as the only source of truth. Smoking gestures vary by person, watch wrist, device orientation, and context, so the app should always let users confirm, dismiss, or manually add events. Treating automation as "probable event detection" keeps the product trustworthy and avoids frustrating false positives.

## Hardware feasibility

The concept is feasible on Apple Watch hardware, but accuracy depends on sensor availability and runtime constraints:

- **Motion sensors:** Apple Watch provides accelerometer/gyroscope-derived device motion through Core Motion, which can detect repeated hand-to-mouth-like movement patterns.
- **Heart-rate data:** HealthKit can provide heart-rate samples when the user authorizes access, but sample frequency is not guaranteed and can vary by workout state, watchOS behavior, battery, and sensor contact.
- **Battery:** Continuous motion and heart-rate monitoring can drain the watch battery. The production app should support user-controlled detection windows, adaptive sampling, and conservative defaults.
- **Device placement:** Detection works best when the watch is worn on the hand used for smoking. Opposite-wrist use is likely to reduce accuracy.

## Software feasibility

The current codebase already has the main software building blocks:

- A watchOS app that starts motion, HealthKit, and event detection.
- An iOS companion app with dashboard, reports, goals, and settings screens.
- Shared models and repositories for smoking events.
- WatchConnectivity-based event forwarding from watchOS to iOS.
- A first-pass detection algorithm that fuses gesture detections with heart-rate spikes.

The current automatic detector is intentionally naive. It is enough for prototyping, demos, and collecting early user feedback, but it should not be marketed as medically accurate or reliable without validation.

## Recommended implementation path

1. **Manual-first MVP**
   - Keep manual watch logging fast and prominent.
   - Make iOS reports and goals useful before relying on automation.
   - Add clear privacy messaging for HealthKit and motion data.

2. **Assisted detection**
   - Use motion and heart-rate fusion to create "possible smoking event" prompts.
   - Ask users to confirm or reject detected events.
   - Store feedback so thresholds can be tuned per user.

3. **Personal calibration**
   - Let users record a short calibration period.
   - Adjust gesture and heart-rate thresholds based on their baseline.
   - Add quiet hours and known false-positive contexts.

4. **Validation and safety**
   - Measure precision, recall, false positives, and false negatives with real users.
   - Avoid medical claims unless supported by formal validation.
   - Keep export/delete controls clear for privacy compliance.

## Technical risks

- False positives from eating, drinking, shaving, brushing teeth, or similar hand-to-mouth gestures.
- False negatives when users smoke with the non-watch hand or when heart-rate samples are sparse.
- Battery drain from continuous sensor use.
- HealthKit authorization and availability differences across devices.
- Privacy expectations around sensitive behavioral and health-adjacent data.

## Bottom line

This is possible in hardware and software terms, and it is a worthwhile idea if positioned as a supportive habit-tracking app rather than a perfect detector. The best next step is to ship a manual-first MVP, add assisted detection behind clear user controls, and improve the detector with opt-in confirmation feedback.
