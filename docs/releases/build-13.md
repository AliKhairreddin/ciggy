# TestFlight 1.0 (13) — What to Test

This build improves optional motion-calibration delivery to the private dashboard. Cigarette detection, automatic counts, corrections and cigarette-event sync are unchanged from build 12.

The Watch keeps an hourly calibration batch schedule, prepares more saved motion during its existing background opportunities, and can hand a bounded batch to Apple for delivery without waking after every two files. Saved queues now survive app-container changes after updates, and retained calibration files are recovered safely without creating duplicate dashboard recordings.

The iPhone queues more received files with background uploads, gives retry deadlines to the system, and requests background recovery for saved files still awaiting preparation. Uploads remain Wi-Fi only. A lost live connection to Watch is explained separately from background file delivery.

The private dashboard now shows the last reported delivery stage, queue counts, timestamps and app builds. This small diagnostic report is included only while calibration sharing is enabled and expires after 14 days. Reports can be stale; they are not a live connection indicator or cigarette detections.

Update both companion apps. With sharing already enabled and the iPhone on Wi-Fi, leave both apps in the background without swiping them away. Check the dashboard later for additional motion and delivery status. Confirm pauses stop sharing and your cigarette counts continue normally.

Known limitations: watchOS and iOS decide when background work runs, so hourly batch eligibility is not a guaranteed hourly upload. Force-quitting either app, connectivity, battery conditions and unavailable source history can delay delivery. Simulator checks cannot establish real-device delivery timing or battery use. Older source data may already have expired; the dashboard preserves those gaps.
