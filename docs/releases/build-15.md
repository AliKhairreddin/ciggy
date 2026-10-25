# TestFlight 1.0 (15) — What to Test

Ciggy now estimates a cigarette after at least five minutes of repeated smoking-like wrist movements. Continued qualifying motion can produce another estimate after a further five minutes, without requiring a quiet gap between cigarettes. Five minutes is a prototype counting rule, not a global average or a measurement of the cigarette itself.

Nearby estimates remain separate, while replayed motion cannot add the same estimate twice. Interrupted live monitoring, missing motion and long pauses reset incomplete evidence. Counts and corrections remain synchronized.

Please test with empty-hand raise, hold and lower movements while Ciggy stays active on the Watch. Check that a short pattern does not count, a sustained pattern creates an estimate, and continued movement can create another. Then rest and check that the counter does not increase just because time passes. Verify iPhone synchronization, saved counts after reopening, and count corrections on both devices.

Known limits: shorter cigarettes may be missed, longer cigarettes may be split, and other similar movements may count. This is an unvalidated motion-and-duration estimate. Background analysis and phone delivery still depend on watchOS; this update does not guarantee an update within five minutes.
