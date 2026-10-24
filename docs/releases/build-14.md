# TestFlight 1.0 (14) — What to Test

This build fixes a Watch crash path during saved-motion catch-up and improves automatic calibration delivery diagnostics.

The Watch now bounds every saved-motion request against Core Motion's current three-day retention limit. A delayed analysis cutoff or an old repair cursor could previously request expired data and cause Core Motion to terminate the app. Unavailable portions remain gaps; the app does not invent samples or counts.

Cigarette recognition, sensitivity, session boundaries, counting and event synchronization are unchanged. The only change in the tracking history reader is protection against an invalid sensor request.

iPhone delivery reports are queued before raw motion preparation. A report is considered delivered only after the server acknowledges it. Failed reports retry through the system's background upload service with persisted backoff, and report failures are visible in Motion calibration settings. The settings also clarify that Check Watch is an optional recovery action.

Update both apps and open each once after this update to verify that the Watch stays open and initializes the new code. With sharing enabled and the iPhone on Wi-Fi, return to the Watch face and iPhone Home Screen, then leave both apps in the background. Check the private dashboard later without using Check Watch or Retry. Confirm new motion and delivery status appear and normal cigarette counts continue.

The Watch retains hourly batch eligibility; iPhone upload starts when files arrive and Wi-Fi/background execution permit. Apple controls actual wake and delivery times, so this is not a guaranteed hourly upload. Swiping an app away can prevent background recovery. Physical-device testing is still required to confirm unattended delivery and crash resolution on your Watch.
