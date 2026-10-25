# Widgets and Live Activities

Ciggy offers five widgets on iPhone, iPad, and Apple Watch:

| Widget | Shows | Tap opens |
| --- | --- | --- |
| Cigarettes Today | Cigarettes recorded today and progress toward the daily limit | Today |
| Daily Limit Remaining | Cigarettes left before the daily limit, or the amount over it | Goals (Watch: settings) |
| Since Last Log | Elapsed time since the most recent recorded event | Today |
| Last 7 Days | Today plus the previous six days; larger layouts include a daily chart | Reports (Watch: weekly summary) |
| Log a Cigarette | Opens the existing logging form; save in the app | Log a cigarette |

**Cigarettes Today counts up; Daily Limit Remaining counts down.** With three recorded cigarettes and a limit of ten, they show **3 today** and **7 left**. The remaining gauge reflects the fraction left, while the count gauge reflects the fraction recorded. Reaching the limit shows **0 / at limit**; exceeding it by two shows **+2 / over**, including on compact complications. Small Home Screen widgets retain their titles. Gallery previews use a consistent synthetic daytime example so this distinction remains visible at any hour. Existing widget identifiers and tap destinations are unchanged, so installed widgets keep their placements.

The shared custom template icons have consistent meanings: a cigarette for recorded counts, a limit marker for the daily limit, a timer for elapsed time, a chart for seven-day totals, and an add-cigarette icon for the logging form. They inherit the widget or complication's system tint and rendering mode. Names and compact labels carry the meaning alongside the icons; no count depends on recognizing an icon alone.

The original vector artwork is in `Shared/Resources/CiggyIcons.xcassets`, exposed through `CiggyIcon` and `CiggyIconView`. These are custom symbol assets with nine weights and three scales, rather than ordinary image assets, so the same artwork can be used by native tabs and Control Center. Apple requires controls to use symbol images and supports [creating custom symbols](https://developer.apple.com/documentation/technologyoverviews/custom-sf-symbols). Preserve symbol metadata when editing the artwork.

Ciggy is a parody: the custom cigarette motifs, chart-bar visual puns, and gallery copy about paper trails, receipts, and a "line in the ash" carry its packaging-inspired humor. Functional names, counts, limit states, and accessibility labels remain literal so the joke does not obscure the difference between recorded and remaining cigarettes. The project's [brand instructions](../AGENTS.md#parody-brand-and-voice) apply across both apps and their extensions.

The elapsed timer measures time **since the last recorded event**, not verified smoke-free time. It does not show an unrelated daily-limit ring. A fresh installation with no events says **No logs yet**. Automatic estimates remain included until corrected, as in the app. “Last 7 Days” is a rolling seven-calendar-day view, not the current calendar week.

## Supported surfaces

- iPhone/iPad Home Screen: small, medium, large, and extra large where the device supports it. Extra-large portrait is included on iPadOS 27 and later.
- iPhone/iPad Lock Screen: circular, rectangular, and inline.
- StandBy: the system uses the Home Screen widget layouts.
- Apple Watch: circular, rectangular, inline, and corner complications, on compatible watch faces. Rectangular widgets also appear in the Smart Stack.
- iOS 18 and later: **Log a Cigarette**, **Cigarettes Today**, and **Ciggy Reports** controls can be added to Control Center, compatible Lock Screen controls, or the Action button.
- Live Activity: Lock Screen plus compact, minimal, and expanded Dynamic Island presentations on compatible iPhones.

To add a Home Screen widget, hold an empty area, choose **Edit → Add Widget**, and search for **Ciggy**. To add a Lock Screen widget, customize the Lock Screen and select Ciggy. On Watch, edit a compatible complication slot or add Ciggy in the Smart Stack. Controls appear under Ciggy in the control gallery. Open Ciggy once after installing so it publishes its initial snapshot.

## Live Activity

On **Today**, choose **Start Live Activity**. The activity shows the day's count, daily limit, cigarettes remaining (or the amount over the limit), and a running time since the last log. The **Log** link opens the logging form; saving still requires an explicit tap. Tap the activity itself to open Today. **Stop Live Activity** removes it. The app restores an existing activity after relaunch and respects dismissal by the user; opening the app or receiving a Watch event does not silently create another one.

ActivityKit permits up to eight active hours. Ciggy marks a session stale at the earlier of eight hours or local midnight. Stale layouts say **Session ended** instead of showing yesterday's count. When the app next runs, it ends the expired activity. iOS can retain an ended activity on the Lock Screen temporarily. Start another session when needed. If activities are disabled, enable **Live Activities** for Ciggy in iPhone Settings.

## Data, updates, and signing

Both apps publish a small snapshot to the App Group `group.That-Canadian-Software-Services.ciggy`. The snapshot contains only recent log timestamps, the latest older log when needed for the timer, and the daily limit. Notes and HealthKit data are excluded. Sensitive values use SwiftUI's privacy redaction. Each device uses its own local App Group; WatchConnectivity continues to synchronize repository mutations between devices with existing duplicate protection and deletion tombstones.

Logging, deletion/undo, count adjustments, and goal changes request widget timeline reloads. Midnight timeline entries reset totals without needing to open the app. WidgetKit decides when requested reloads appear, so widgets are not guaranteed to refresh instantly. An existing Live Activity updates when the iPhone receives repository/goal changes, including Watch events delivered in the background. This does not provide server push updates or guarantee immediate delivery while the iPhone app is terminated.

The `ciggy` target embeds **CiggyWidgets** and the Watch app; the Watch app embeds **CiggyWatchWidgets**. All four targets use the same App Group entitlement and existing development team. A physical-device installation requires the App Group to be registered for that team and available in each provisioning profile. Use Xcode automatic signing with a valid developer account. Follow [TestFlight delivery](testflight.md) to archive and upload all four bundles together.

The control navigation intent and its screen enum are compiled directly into both the iPhone app and widget extension from `iOS/Services/OpenCiggyScreenIntent.swift`. Keep this shared source in both Xcode targets so each executable includes the navigation metadata.

Apple references: [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [widget families](https://developer.apple.com/documentation/widgetkit/widgetfamily), [widget refresh behavior](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), and [controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).

## Validation

Use the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The iPhone scheme builds both widget extensions and the embedded Watch app. `WidgetSnapshotTests` cover duplicate IDs, date boundaries, future-event exclusion, corrections, old last-log retention, App Group persistence, and omission of notes/health data. The iOS UI suite includes activity start, restoration after relaunch, and stop. On paired devices, additionally check a Watch log and correction, the widgets' corresponding totals, and the Dynamic Island/Lock Screen layouts with Live Activities enabled and disabled.

The unsigned commands above are compile-only checks. Keep Xcode's normal simulator signing enabled for runtime UI checks: App Intents rejected an unsigned extension for lacking a team identity, causing WidgetKit to assert while constructing a control template. A clean build with default Xcode signing restored normal launches and the final UI tests passed without another widget crash. Custom signing of simulator artifacts was refused by launchd and is not needed for this workflow. Check actual control taps on a physical-device/TestFlight installation; the separately signed Release archive passed signature verification.
