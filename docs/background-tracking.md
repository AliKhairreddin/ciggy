# Background tracking and delivery timing

The build 16 changes improve how Ciggy uses each background execution opportunity. They do not establish a guaranteed all-day update within five or ten minutes. Physical-device latency and battery measurements are still required.

## How a count reaches the phone

The detector needs at least five minutes of continuing qualifying gestures for its first estimate. While Ciggy is running, it can evaluate each new gesture. While the Watch app is suspended, `CMSensorRecorder` continues its previously requested recording, but Ciggy's classifier runs only when watchOS gives the app execution time. Recorded samples can take up to three minutes to become available. Apple exposes a historical query, not a notification that wakes an arbitrary classifier whenever new samples arrive. See [the detector's duration rule](cigarette-duration.md), Apple's [sensor recorder](https://developer.apple.com/documentation/coremotion/cmsensorrecorder), and [retrieval timing](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)).

Built-in step counting is different: [`CMPedometer`](https://developer.apple.com/documentation/coremotion/cmpedometer) returns step counts already processed by the system, including cached history. That API does not let Ciggy install its smoking classifier as another system activity detector. Moving computation to iPhone or a server still requires the Watch to read and send its samples first. SensorKit can access selected paired-Watch data from iPhone, but requires [approval for a research study](https://developer.apple.com/documentation/sensorkit/configuring-your-project-for-sensor-reading) and imposes a [24-hour holding period](https://developer.apple.com/documentation/sensorkit/srfetchrequest).

Once an estimate is saved, Ciggy attempts live delivery and queues durable WatchConnectivity delivery. Background transfers occur when the system permits; an iPhone live message does not itself wake the Watch app. Consequently, total delay includes the evidence window, sample availability, the next execution opportunity, and synchronization. [Apple's transfer documentation](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)) and [message behavior](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)) describe these limits.

## Build 16 scheduling and work order

- Request the next background refresh with a **15-minute preferred date**. Preserve an earlier pending request, and replace consumed or stale scheduling state. This is a request, not a periodic timer: Apple documents approximately four refreshes per hour with an active-face complication, with a shared budget and possible deferral. [Refresh budget](https://developer.apple.com/documentation/watchkit/wkapplicationrefreshbackgroundtask)
- Check the most recent **15 minutes**, with up to **eight preceding minutes** of classifier context, before reconciling the older backlog. Preserve the chronological cursor and missing intervals so prioritizing recent activity does not discard older work.
- Analyze counts, save events, and queue synchronization before optional calibration extraction. Use a cooperative **three-second total processing budget**: allot 2.25 seconds to analysis, then calibration receives at most 0.75 seconds and runs only if at least 0.25 seconds remains. These budgets cannot preempt a synchronous sensor query or guarantee how much execution time watchOS grants.
- Cancel expired work cooperatively, retain unfinished history for retry, and avoid treating an interrupted read as a successful empty result. Keep independent background work alive when foreground monitoring stops, and consume the old refresh appointment before scheduling its successor.

An active Ciggy complication gives the app more opportunities to refresh. It does not keep the classifier running continuously. Longer execution APIs have specific purposes and limits; a workout session or another background category cannot be used merely to turn passive cigarette tracking into unrestricted runtime. [Extended-session purposes](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions)

## Physical-device validation

Use this as a test protocol, not a report of completed testing:

1. Install the matching build on a paired physical iPhone and Watch. Launch Ciggy once, allow motion access, and confirm that recording is armed. Put a Ciggy complication on the **active** Watch face.
2. For the baseline, enable Watch Settings → General → Background App Refresh, including Ciggy, and turn Low Power Mode off. Apple notes that active-face complications can still refresh when their background-refresh setting is off; the enabled setting here removes an avoidable test variable. Low Power Mode reduces both background and complication update frequency. [Background refresh settings](https://support.apple.com/guide/watch/apd422aaa391/watchos), [Low Power Mode](https://support.apple.com/108320)
3. Launch from the device Home Screen with Xcode's debugger detached. Apple warns that running through Xcode prevents normal suspension and can change background behavior. [Testing WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
4. Use labeled empty-hand motion trials from [the motion test guide](motion-testing.md), alongside stillness and eating/drinking controls. Return to the Watch face during the passive trial. Keep activity times, coverage/check times, observed count changes, device conditions, and available diagnostic logs private.
5. Measure foreground-assisted and passive trials separately. Opening the Watch runs history analysis; opening the iPhone requests a history check. Record either action because it changes the conditions. Verify saved events and companion delivery separately, then check that reopening or replaying history does not duplicate counts.

Repeat with calibration sharing on and off, an older backlog, interrupted connectivity, and app relaunches. Report observed latency distributions, missing coverage, false counts, and battery use; passing simulator or synthetic tests alone does not validate passive delivery timing.
