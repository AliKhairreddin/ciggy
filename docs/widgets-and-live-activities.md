# Widgets and Live Activities

Ciggy offers five widgets on iPhone, iPad, and Apple Watch:

| Widget | Shows | Tap opens |
| --- | --- | --- |
| Today | Today's count and progress toward the daily limit | Today |
| Daily Budget | Logs remaining within the daily limit | Goals (Watch: settings) |
| Since Last Log | Elapsed time since the most recent recorded event | Today |
| Your Week | Seven-day total; larger layouts include a daily chart | Reports (Watch: weekly summary) |
| Quick Log | A shortcut to the existing logging form | Log a cigarette |

The elapsed timer measures time **since the last recorded event**, not verified smoke-free time. A fresh installation with no events says **No logs yet**. Automatic events remain included until corrected, as in the app.

## Supported surfaces

- iPhone/iPad Home Screen: small, medium, large, and extra large where the device supports it. Extra-large portrait is included on iPadOS 27 and later.
- iPhone/iPad Lock Screen: circular, rectangular, and inline.
- StandBy: the system uses the Home Screen widget layouts.
- Apple Watch: circular, rectangular, inline, and corner complications, on compatible watch faces. Rectangular widgets also appear in the Smart Stack.
- iOS 18 and later: **Quick Log**, **Ciggy Today**, and **Ciggy Reports** controls can be added to Control Center, compatible Lock Screen controls, or the Action button.
- Live Activity: Lock Screen plus compact, minimal, and expanded Dynamic Island presentations on compatible iPhones.

To add a Home Screen widget, hold an empty area, choose **Edit → Add Widget**, and search for **Ciggy**. To add a Lock Screen widget, customize the Lock Screen and select Ciggy. On Watch, edit a compatible complication slot or add Ciggy in the Smart Stack. Controls appear under Ciggy in the control gallery. Open Ciggy once after installing so it publishes its initial snapshot.

## Live Activity

On **Today**, choose **Start Live Activity**. The activity shows the day's count, daily limit, remaining budget, and a running time since the last log. The **Log** link opens the logging form; saving still requires an explicit tap. Tap the activity itself to open Today. **Stop Live Activity** removes it. The app restores an existing activity after relaunch and respects dismissal by the user; opening the app or receiving a Watch event does not silently create another one.

ActivityKit permits up to eight active hours. Ciggy marks a session stale at the earlier of eight hours or local midnight. Stale layouts say **Session ended** instead of showing yesterday's count. When the app next runs, it ends the expired activity. iOS can retain an ended activity on the Lock Screen temporarily. Start another session when needed. If activities are disabled, enable **Live Activities** for Ciggy in iPhone Settings.

## Data, updates, and signing

Both apps publish a small snapshot to the App Group `group.That-Canadian-Software-Services.ciggy`. The snapshot contains only recent log timestamps, the latest older log when needed for the timer, and the daily limit. Notes and HealthKit data are excluded. Sensitive values use SwiftUI's privacy redaction. Each device uses its own local App Group; WatchConnectivity continues to synchronize repository mutations between devices with existing duplicate protection and deletion tombstones.

Logging, deletion/undo, count adjustments, and goal changes request widget timeline reloads. Midnight timeline entries reset totals without needing to open the app. WidgetKit decides when requested reloads appear, so widgets are not guaranteed to refresh instantly. An existing Live Activity updates when the iPhone receives repository/goal changes, including Watch events delivered in the background. This does not provide server push updates or guarantee immediate delivery while the iPhone app is terminated.

The `ciggy` target embeds **CiggyWidgets** and the Watch app; the Watch app embeds **CiggyWatchWidgets**. All four targets use the same App Group entitlement and existing development team. A physical-device installation requires the App Group to be registered for that team and available in each provisioning profile. Use Xcode automatic signing with a valid developer account. There is no TestFlight/App Store deployment workflow configured in this repository.

Apple references: [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [widget families](https://developer.apple.com/documentation/widgetkit/widgetfamily), [widget refresh behavior](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), and [controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).

## Validation

Use the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild -project ciggy/ciggy.xcodeproj -scheme ciggy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The iPhone scheme builds both widget extensions and the embedded Watch app. `WidgetSnapshotTests` cover duplicate IDs, date boundaries, future-event exclusion, corrections, old last-log retention, App Group persistence, and omission of notes/health data. The iOS UI suite includes activity start, restoration after relaunch, and stop. On paired devices, additionally check a Watch log and correction, the widgets' corresponding totals, and the Dynamic Island/Lock Screen layouts with Live Activities enabled and disabled.
