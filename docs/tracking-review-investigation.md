# Tracking timing and wrist posture

## Review timing

A review is created only after an automatic estimate is saved. A history check that finds no new cigarettes produces no review. New estimates merge into the pending review for the same local day and source; after the user marks it accurate or adjusts it, later estimates create a new review. There is no evening-only rule. Live detections also create cards; the Watch history path schedules the optional detection-summary notification when it saves new estimates.

Before build 20, cards displayed the history scan's start/end without explaining what those dates represented. A backlog spanning midnight through the afternoon could therefore look like an all-day tracking confirmation even if only one afternoon estimate had been found. Pending reviews also accumulate across checks. That range proves neither uninterrupted coverage nor that undetected cigarettes did not occur.

Build 20 shows **Estimated logs** using the original event timestamps when all originals are available. Adjusted reviews label these **Original estimates**. Legacy or partially delivered summaries explicitly show **Review period** instead. The same wording is used in history notifications, replacing the misleading relative “last N hours” text. Presentation does not rewrite review IDs, correction windows, counts, or delivery state. Settings → Tracking details explains the difference between a detection review and tracking freshness.

## Confirmed scheduling defect and fix

Apple documents that a background refresh is ignored if the app is in the foreground when scheduled. Ciggy retained the corresponding preferred date and normally protected an overdue appointment for two hours to avoid repeatedly postponing a legitimate delayed background request. If the preferred date fell during a foreground session, that protection could instead preserve a request watchOS had ignored.

Build 20 remembers the current foreground session's start. On background entry it retires a preferred date that fell within that session, then schedules the next check. Future appointments and overdue dates preceding the session remain protected. Tests cover the replacement, both preserved cases, unknown sessions, and invalid/reversed dates.

This is a demonstrated code path, not a diagnosis of any particular tester's delayed alert. Physical-device execution and delivery timestamps are still needed to attribute a real delay.

## Remaining latency limits

- The detector needs repeated completed gestures spanning at least five minutes. Normal sensitivity requires five gestures; high/low requires four/seven. A new qualifying gesture must satisfy both duration and count. Short activity may never yield an estimate.
- Saved acceleration can take up to three minutes to become retrievable; Ciggy queries behind that availability cutoff.
- The Watch requests background runtime at a preferred 15-minute interval. watchOS controls actual execution. An active-face complication improves opportunities; it does not provide an exact timer. Foreground history is checked every minute.
- The recent pass prioritizes 15 minutes with eight minutes of context. Older history reconciles separately within available runtime, and interrupted coverage remains pending.
- WatchConnectivity delivery can add delay before the iPhone receives an already-saved Watch estimate.

The foreground-expiry fix cannot remove these constraints. The latest history check and latest motion sample in Tracking details distinguish processing/freshness from the review's event times.

## Sitting, standing, and smaller movements

The detector uses gravity and acceleration vectors across x/y/z, with gyroscope rotation for live samples. Background recordings contain acceleration only, so gravity and angular speed are estimated. Axes describe the Watch's coordinate frame, not measured hand height or distance from the floor. No body-height or knee-height threshold is used.

The gesture engine learns a stable resting wrist orientation. It requires roughly 26° (0.45 radians) of orientation change, a steady hold of at least 0.7 seconds, and return within roughly 14° (0.25 radians) of the resting orientation. It can reacquire a resting pose, but does not explicitly classify sitting versus standing or use a separately trained model for either posture. Small excursions, a different return pose, or otherwise nonmatching gestures can be missed. The sensitivity control changes the required gesture count; it does not lower that angle threshold.

Synthetic regression traces exercise three resting orientations, three motion planes, and 0.3/0.6/1.4-radian excursions through both live and recorded pipelines. The two larger excursions produce an estimate after sufficient repeated activity; the below-threshold excursion does not. These invented traces validate software behavior, not real-world posture accuracy. Thresholds remain unchanged pending labeled examples of smaller seated movements and confounding eating/drinking/other activity. Loosening them without comparison could add false counts.

## Device validation

Use an opted-in physical Watch without an attached debugger. Record the activity times, foreground opens/closes, current face/complication, history-check time, latest motion-sample time, Watch count update and iPhone receipt separately. Compare existing labeled seated/standing examples, or empty-hand motion trials, against nearby confounding activity. A zero-count period with missing data is not proof of no smoking. Keep real recordings, screenshots, timestamps and account details in private calibration storage or local temporary files, never this public repository.

To exercise the scheduling fix, keep Ciggy foregrounded across its preferred refresh date, then return to the Watch face. Verify that a successor is requested instead of retaining the ignored appointment. Its eventual delivery still depends on watchOS. Reopen both apps and confirm catch-up does not duplicate counts and corrections still persist.

## Apple references

- [Scheduling background refresh](https://developer.apple.com/documentation/watchkit/wkapplication/schedulebackgroundrefresh(withpreferreddate:userinfo:scheduledcompletion:)): preferred dates, foreground ignores, one pending request and budgets.
- [Keeping complications up to date](https://developer.apple.com/videos/play/wwdc2020/10049/): background opportunities depend on system load and battery.
- [Retrieving recorded accelerometer data](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)): availability delay, missing intervals and retention.
