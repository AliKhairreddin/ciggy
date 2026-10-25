# TestFlight 1.0 (16) — What to Test

Ciggy now requests automatic Watch background checks about every 15 minutes instead of 30. Keep a Ciggy complication on the active Watch face. Apple controls actual execution and can delay or bunch checks; this is not guaranteed delivery within five or ten minutes.

Each check now analyzes and saves cigarette estimates and queues synchronization before optional calibration work. This build also fixes a lost follow-up schedule and prevents cancelled foreground work from consuming a separate background check. Saved-motion processing prioritizes the latest 15 minutes with up to eight minutes of preceding context, while preserving older history and unfinished checks.

The five-minute motion-and-duration counting rule is unchanged. This update improves background scheduling and work order, not recognition accuracy.

Please install both apps on a paired physical iPhone and Watch, open each once, and add a Ciggy complication to the active face. Return to the Watch face and iPhone Home Screen without force-quitting either app. Test without an attached Xcode debugger. Use empty-hand motion trials and periods of rest; compare actual checked-motion timestamps and freshness with your trial times. Reopening either app can trigger a check, so record when you do it. After reopening, verify count synchronization and corrections on both devices, and check that repeated history reads do not duplicate counts.

Physical-device background latency and battery use still need validation.
