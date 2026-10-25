# Build 18 consumer copy and tracking details

Today on iPhone and Watch now shows a concise notice when recent activity is pending or tracking needs attention. The motion explanation cards, connection rows and monitoring indicator have been removed from home. The notice opens Tracking details, which is also reachable through Settings. Freshness is reevaluated while the screen is open; recent samples cannot hide missing history, permission problems or capture expiry.

Settings → Tracking details retains the full status, manual check action, motion/background scheduling explanation and optional heart-rate context. Private motion calibration remains in Settings. Reports focuses on cigarette charts. Live Activity and correction copy is shorter, and phone/Watch consumer copy uses Ciggy's packaging parody throughout. Functional actions and accessibility labels remain clear. The former “Smoke-free” metric now says “Days since log,” matching the saved-event calculation.

The parody and consumer-surface rules are recorded in `AGENTS.md`. Motion classification, background scheduling and synchronization behavior are unchanged.

## Validation

- Swift package: 296 tests passed, including freshness aging, missing-data precedence and suspended-processing notices.
- Native iPhone: five unit tests and six UI checks passed across the main screens, settings/detail navigation, manual logging and undo, persistent count corrections, large text and folded/rotated layouts.
- The historical-correction UI test initially assumed its eight-hour fixture always contained today's events. It was corrected to open earlier-day reviews after midnight, verify the appropriate daily total and verify the saved correction after relaunch; its rerun passed.
- Paired Watch: two unit tests and two UI checks passed for logging/relaunch and the new Settings route.
- Screenshots of Today, Reports, Goals, Tracking details and Watch home/details were inspected locally. Screenshots and simulator logs are not committed.
- Xcode source groups, shared-library links, Watch embedding/dependency and matching companion identifiers were verified.
- Validation and release builds use an isolated source snapshot containing only this change, excluding concurrent leaderboard work.

Build-specific update details are in [the release notes](releases/build-18.md). TestFlight delivery is recorded after upload and processing verification.
