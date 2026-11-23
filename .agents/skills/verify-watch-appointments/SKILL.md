---
name: verify-watch-appointments
description: Check the Watch background refresh slot when changing foreground transitions, capture renewal, preferred dates, or retries.
---

# Verify Watch refresh appointments

Run the bounded model from the repository root on macOS. CI includes it in the full Swift suite under Xcode 27.2.

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcrun swift test --filter WatchRefreshScheduleModelTests
```

Ciggy keeps an earlier pending appointment across repeated opens and checks. If its date passes in the foreground, Ciggy must ask for another on exit. An overdue appointment from before that session remains pending through a two-hour grace period.

The model starts with a successful 15-minute reservation and one simulated WatchKit slot. It generates all sequences of four foreground entries, exits, checks, grants or clock advances chosen from 60, 900, 7,200 and 7,201 seconds. A grant is eligible only in the background once a request is due. The simulated system discards requests that come due in the foreground. For each lifecycle transition, the oracle inspects the date the production scheduler requests and whether the system has an outstanding appointment. Separate cases load a legacy preference, restart the scheduler, disable scheduling, and deliver an old rejection after a replacement. Real watchOS wake latency, permission prompts and sensor queries are outside this model.

A failure prints the prefix of lifecycle and clock actions. Check which system slot existed immediately before the final action. To replay the missing appointment in a disposable checkout, remove the due-date retirement inside the scheduler's `.foregroundEnded` arm while keeping the foreground reset. To replay postponement, remove the pending-date grace check before saving the next preferred date. Run each change separately, restore the source, then rerun. The historical implementations are in `watchOS/Services/BackgroundMotionMonitor.swift` at `1eb6cd7` and `0f17ea1`.

Coverage at `9dc1cf0153e2e1a0567f93f5c41131df2f4bffa4` includes `WatchRefreshSchedule.appointment` and `rejected` in `Shared/Services/MotionCapturePolicy.swift`, the four wake inputs in `watchOS/WatchApp.swift` and the connection to WatchKit in `BackgroundMotionMonitor.armRecording` and `scheduleRenewal`. The checker lives in `Tests/CiggySharedTests/WatchRefreshScheduleModelTests.swift`. Check those transitions and replay the historical failures before advancing the coverage commit.
