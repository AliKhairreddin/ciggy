# TestFlight 1.0 (8) — What to Test

Motion sharing now attempts immediate Watch-to-iPhone delivery when the phone is reachable, with the existing background file transfer as backup. The iPhone saves a complete validated recording before acknowledging it and uploads over Wi-Fi.

When sharing is enabled, live Watch motion is queued after a cigarette detection, on foreground checks and when the Watch app backgrounds. Background history now shares useful fragments around gaps instead of dropping a whole five-minute window. Missing intervals retry sooner, with bounded backoff, and fuller data keeps existing samples and labels intact.

Update both the iPhone and Watch apps. Your existing pairing and sharing choice are kept. In iPhone Settings → Private motion calibration, check the last upload, phone queue, Watch check time and transfer status. “Check Watch and retry uploads” resends your sharing setting and requests a check. Keep iPhone on Wi-Fi.

Visit https://ciggy.thatcanadian.dev to review the uploaded motion. The dashboard checks recent arrivals each minute while open and reuses saved history between full reconciliations. Mark each actual cigarette separately, including back-to-back ones, and number it in Notes. This helps investigate a future motion-based boundary detector; labels do not change your count or train a model automatically.

Automatic cigarette grouping is unchanged in this build. Back-to-back cigarettes without a recognized break can still merge. watchOS controls background timing; complete five-minute history windows have a three-minute availability allowance before extraction, and device transfers/uploads can add delay. Only motion after sharing consent is eligible. Shared recordings and labels expire after 14 days; offline queues are bounded.
