# TestFlight 1.0 (10) — What to Test

This build adds reliability fixes from a review of the iPhone, Watch, and shared code. It also includes build 9's hourly opt-in calibration batches and automatic motion dashboard.

Unsaved Goals and Settings edits now survive unrelated settings arriving from the Watch or calibration changes. Try changing a daily limit or quit date, then saving after a separate setting updates.

Delayed pending Watch summaries no longer reopen a detection review you already marked accurate or adjusted. New detections remain separately reviewable, and repeated deliveries preserve them. Check review decisions and counts after reconnecting the iPhone and Watch.

Future-dated logs no longer inflate the current Watch count or prematurely reset a smoke-free streak. Manual Watch logs omit heart-rate context older than two minutes, and old HealthKit callbacks cannot restore a stopped reading.

Recent history checks now reuse available saved session progress, avoiding a duplicate count when a long continuous gesture pattern slows down and then speeds up. Detection thresholds are unchanged. Permanently missing motion coverage remains visible when only part of a missing interval can be recovered. Privacy text now explains optional motion uploads accurately.

Known limitations: independently correcting the same review on both offline devices can still produce conflicting counts; an interrupted correction between separate storage writes can also leave a mismatch. Very long motion sessions whose earlier state falls outside a backlog replay window remain ambiguous. Detection is experimental: back-to-back cigarettes may merge and similar wrist movements can be misclassified. watchOS controls background timing; complete capture, delivery latency, battery use, and real-world recognition have not been established by simulator tests.
