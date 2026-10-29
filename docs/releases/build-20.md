# TestFlight 1.0 (20) — What to Test

Ciggy now replaces a background check that expired while the Watch app was open. Previously, that ignored request could delay a replacement for up to two hours. Future checks and already-delayed background requests keep their place.

Review cards and detection notifications now label the saved estimates' log times instead of presenting a broad history scan as an unexplained midnight-to-evening range. Adjusted reviews label the original estimates; older summaries without complete event timestamps explicitly show a review period. Saved counts and corrections are preserved.

Tracking details explains when reviews appear, why a check with no new detections creates no review, and how sitting, standing and smaller wrist movements affect the existing detector.

Please install both companion apps. Check that new estimates appear on Watch and iPhone, review and adjust a count, and reopen both apps to verify corrections persist without duplicates. Leave the Watch app open across a requested background-check time, then return to a face with a Ciggy complication and compare tracking freshness later. Check that review times refer to the estimated logs, not their arrival time.

watchOS still controls background execution and delivery; 15 minutes is a requested interval, not a guarantee. Recognition thresholds are unchanged: normal sensitivity needs five gestures spanning at least five minutes. Small movements and shorter activity can still be missed. Real-device latency and seated/standing accuracy need validation.
