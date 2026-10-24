# Ciggy code audit — October 23, 2026

This review covered the shared repositories, synchronization and review workflow, motion/history processing, iPhone and Watch view models, HealthKit context, widgets, Live Activities, calibration upload controls, project configuration, and existing regression suites. The parallel calibration/dashboard task shipped separately from commit `2a461e2`; its build 9 does not contain these audit fixes.

## Corrected behavior

- **Form drafts:** unrelated synced settings no longer reset unsaved Goals or Settings fields. Each editable field follows only changes to its own saved value; saving preserves the other settings.
- **Offline review delivery:** a newer pending summary cannot reopen an already accurate or adjusted review. Additional detections remain reviewable in deterministic continuation summaries. Repeated, reordered, and divergent pending messages retain new event IDs and survive relaunch.
- **Clock skew:** future-dated events no longer inflate the Watch's current count/last-log display or reset the current smoke-free streak before their timestamp. The event remains saved for its actual time.
- **Heart-rate context:** manual Watch logs attach only valid readings from the preceding 120 seconds. Displayed context expires, stopping the query clears it, and callbacks from an older query cannot repopulate it. Automatic detection retains the original timestamped readings and its existing context rules.
- **Recent motion replay:** when a saved chronological checkpoint falls inside the recent replay context, the priority pass copies its analyzer and resumes from its cursor. This prevents a dense–sparse–dense continuing pattern from being counted again by a fresh analyzer. The chronological checkpoint remains independent and detection thresholds are unchanged.
- **Missing history:** an interval with an expired prefix now reports lost coverage even if its retained suffix is recovered.
- **Privacy copy:** the in-app explanation and TestFlight guide now reflect the existing, explicitly consented private motion-upload feature.
- **Portable Xcode builds:** the shared package reference now points to the repository root relative to the Xcode project, instead of assuming the checkout folder is named `ciggy`. A clean release snapshot exposed the old path's dependency-resolution failure.

## Remaining risks and validation limits

These changes do not establish that the app is free of bugs or that wrist-motion recognition is accurate in daily use.

1. **Concurrent corrections:** independently adjusting the same review on both devices while disconnected can create conflicting event mutations. Added correction events currently have random IDs, so two independent increases can both survive while only one review decision wins. A durable correction transaction with deterministic mutation identity and reconciliation is still required.
2. **Interrupted corrections:** the review decision, event changes, and outgoing transport records are separate writes. Termination between them can leave a saved review inconsistent with its count or companion delivery. The continuation merge fix does not make this workflow transactional.
3. **Very old motion backlogs:** a checkpoint older than the entire bounded replay context cannot supply earlier session state. An unusually long changing-cadence pattern crossing that boundary can still produce duplicate evidence; missing-gap reconciliation has the same ambiguity. Full resolution needs retained session continuity across those boundaries.
4. **Physical-device behavior:** simulator tests cannot verify real accelerometer history, all-day background scheduling, battery use, or real-world smoking/eating/drinking discrimination. Synthetic tests validate software behavior on invented traces, not recognition accuracy.

## Validation

- **193 shared Swift tests passed**, including 14 added regressions and the unchanged 800-trace synthetic motion sweep (974,648 samples through each pipeline).
- **5 iPhone unit tests passed** for independent form fields and preserving unrelated settings on save.
- **6 iPhone UI scenarios passed** across two focused runs: goals/screens, manual logging/undo, deep links, Live Activity start/relaunch/stop, rotation with logging/undo, and historical detection review.
- **2 Watch unit tests and 2 Watch UI scenarios passed**: fresh logs update before the next timer tick, future events remain excluded, manual save adds exactly one log through relaunch, and appearance persists.
- **41 dashboard/backend tests, TypeScript checks, and 5 Python dataset-decoder tests passed**. Dashboard deployment remains owned by the parallel calibration task; this audit changes no Worker code.
- Project source membership, both `CiggyShared` links, Watch embedding/dependency, matching companion identifiers, property lists, privacy manifests, and whitespace checks passed.

The combined run found an obsolete calibration-status string assertion after the parallel task's final copy change. Test-only commit `637b1f0` aligns it with hourly delivery; the full suite then passed. Watch UI testing also exposed a regression in the initial future-date fix: the count used a cached timer timestamp and delayed a fresh log until the next tick. The final code evaluates current time on every event emission, with native Watch unit and UI tests proving the correction. Incoming historical-preview events from the preceding iPhone run also interfered with the first Watch count assertion; final Watch checks ran with that test companion app stopped.

All Xcode and Swift commands used `DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer`. Native tests used the paired iPhone 18 Pro (`28D5127A-C145-4373-A9FC-C55C306F2BAE`) and Watch Series 12 (`815BA98E-CEF0-477F-A0D1-099A469584D6`) simulators. No simulator was erased.

## Distribution

Product changes are pushed directly to `origin/main` in `3e2a042`, with the portable package path fixed in `b985c11`. The final Release archive was built from a clean snapshot of `b985c11`; dependency resolution succeeded with a checkout directory name other than `ciggy`. All four executable bundles are signed and verified at **1.0 (10)**, contain privacy manifests, and retain the correct Watch companion identifier.

Xcode uploaded build 10 through the existing App Store Connect workflow on October 23 at **20:38:54 Toronto time**, reporting `EXPORT SUCCEEDED` and **Uploaded package is processing**. No duplicate upload is needed. This audit did not modify or redeploy the dashboard.

**Internal TestFlight delivery was verified at approximately 20:43 Toronto time on October 23.** After authenticated access was restored, exact build 1.0 (10), ID `35efa369-2f22-4b40-bf0c-883d754a6b46`, received the English (Canada) What to Test text from [build-10.md](releases/build-10.md). The UI showed Saved, then the full text was read back after reloading and matched the release file exactly (excluding the Markdown heading). Ciggy Internal lists build 10 as **Testing**, with 90 days remaining, and contains the two existing testers. Processing and internal availability are verified; this does not claim the testers have installed the update. Build 9's distinct notes were saved and verified separately, and it also shows Testing in the same group. No duplicate binary upload or group-access change was needed.
