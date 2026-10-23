# Ciggy on iPhone Duo

The same Ciggy app adapts to its window and the system's reserved regions. There is no separate app, data store, or device-name check. Existing iPhones and iPads retain support back to iOS 17.

- **Cover display and narrow Split View:** one scrollable column.
- **Open portrait and landscape:** today and progress beside trends, Watch reviews, and recent check-ins. Reports place charts beside their range controls; Goals and Settings use overview and editing panels.
- **Partially folded like a book:** a dedicated daily summary and weekly chart on the leading half, with check-in and Watch review controls at the top of the trailing half. Neither pane crosses the system's hinge frame or interactive margins.
- **Desk mode, half open like a laptop:** Today becomes an immersive Easter egg. An ashtray with resting cigarettes and drifting smoke fills the entire upper half. The working **Ciggy FM** ambient player fills the entire lower half. There are no cards, margins, tracking information, profile controls, status bar, tabs, or exit button. Flatten/close the hinge or rotate into book mode to return to normal tracking. Reports, Goals, and Settings retain their ordinary overview/controls layouts.

The lounge requires both a native partially-open hinge reading and an active horizontal division. It never appears on a flat/closed Duo, in book mode, or on an ordinary iPhone/iPad. A simulated division alone cannot unlock it; a native hinge reading is required. Pane frames use the actual reserved region and update with the hinge's interactive margins. Normal layouts display native hinge status and angle; the immersive scene exposes this information to accessibility without adding visible chrome.

Each new desk-mode session randomly chooses one of ten full-bleed vector landscapes: **Alpine morning, Above the clouds, Open ocean, Golden beach, Misty pines, Desert sunset, Northern lights, Moonlit lake, Lavender fields, and Rainy city**. The previous selection is excluded, and the background stays stable throughout that session. Only the last scenery identifier is saved.

Music starts only after tapping Play and pauses on leaving desk mode, backgrounding, interruptions, or headphone disconnection. Three original ambient loops are synthesized locally, with previous/next, playback progress, play/pause, and volume. No account, network, streaming subscription, or microphone access is needed. Decorative artwork never creates smoking events. Tapping the ashtray pauses/resumes smoke without an extra visible button. Smoke respects Reduce Motion and stops when hidden or inactive.

All four interface orientations are supported. Rotations are validated with Device Hub's physical-display controls. Camera avoidance in normal layouts reserves the nearest edge, including when the camera is at the bottom or side.

Outside the immersive lounge, both panes scroll independently. Screen-level state holds notes, unsaved goals, settings, and the report range across geometry changes. Logging uses the same repository and WatchConnectivity path as the phone's existing log sheet. Right-to-left layouts reverse the book's reading order. Accessibility text sizes use a single column when the display is flat, while folded displays retain independently scrollable halves.

## SDK requirement

Native hinge and camera avoidance requires building with the **iOS 27.1 SDK in Xcode 27.1 or newer** and running on iOS 27.1. `CiggyAdaptiveScreen` queries active division and occlusion regions using their fixed coordinate space. Their frames include Apple's reserved margins; the layout uses these actual frames rather than guessing a midpoint or interpreting phone tilt as a hinge angle.

The compile-time SwiftUI module-version guard excludes Duo symbols from Xcode 27.0 (SwiftUI 8.0.84). Older builds still adapt to portrait, landscape, and window resizing, but cannot detect the hinge or provide the SDK 27.1 display integration. Runtime availability preserves compatibility with older iOS versions when using the new SDK.

Apple references: [Preparing your app](https://developer.apple.com/videos/play/tech-talks/111461/), [adaptive layouts and reserved regions](https://developer.apple.com/videos/play/tech-talks/111463/), and [the reserved-region query](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)).

## Verification

Run shared tests with the installed full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test
```

`CiggyLayoutPlanTests` covers the cover display, open portrait and landscape, narrow multitasking, off-center hinges, changing interactive margins, right-to-left reading order, large text, rotated camera occlusions, and inactive or unusable divisions.

`CiggyAdaptiveUITests` checks rotation, logging/undo, note and goal drafts, report range, and large-text controls. In Debug only, `--ciggy-preview-fold` injects a 24-point division region, horizontal in portrait and vertical in landscape. This exercises the pane geometry on existing simulators; it does **not** validate hardware hinge detection or the iOS 27.1 API branch.

`CiggyNativeDuoUITests` runs on the actual iPhone Duo simulator device type with **no fold-preview launch argument**. Select Closed, Open, or Partially Open in Device Hub before each run. The pose test requires a native hinge reading, checks separated panes in the currently selected native pose, verifies that the immersive surfaces cover the display edges with tracking controls and tabs absent, verifies that the lounge is exclusive to desk mode, and attaches a screenshot. Use Device Hub to rotate the actual displays and rerun it for other orientations. On this runtime, `XCUIDevice.orientation` reports changes without rotating Duo's display surfaces, so it is not evidence of native rotation. The playback test runs in the native Partially Open desk pose and checks actual playback progress, track changes, pause, and pausing when backgrounded. Rotation out of desk mode is checked directly in Device Hub. For example:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild test \
  -project ciggy/ciggy.xcodeproj -scheme ciggy \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' \
  -only-testing:ciggyUITests/CiggyNativeDuoUITests \
  -parallel-testing-enabled NO
```

If multiple Duo simulators exist, use the selected device's UUID instead of its name. Use the existing adaptive UI tests to check logging/undo, drafts, reports, goals, and large text. Also check a physical Duo when available.

App Store/TestFlight distribution requires an existing signing and publishing workflow. Simulator installation alone is not a production release.

## Validation on this Mac

Native validation now uses **Xcode 27.1 (27A9275)** and the **iPhone Duo / iOS 27.1** simulator selected in Device Hub. Both native API branches compile, and the app receives real hinge readings and active division regions (the partially open preset reports 128°). No iPad device or synthetic fold argument is used for native validation or delivered screenshots.

The shared package suite passes **116 tests**, including rotated camera avoidance, varying hinge clearance, and valid, non-silent, unclipped ambient audio with quiet loop boundaries. The normal iOS Simulator build includes the correctly built and embedded watchOS companion and both widget extensions. Use normal Xcode simulator signing and a destination UUID; overriding every target with `-sdk iphonesimulator` incorrectly builds the Watch app for iOS.

The native full-screen pose test passes: the ashtray reaches the upper display edges, the player reaches the lower display edges, neither pane crosses the fold, and profile/logging/tab controls are absent. The native audio test passes actual clock advancement, track switching, pause/resume, and pausing after another app puts Ciggy in the background. Device Hub supplies physical pose/rotation changes; XCTest orientation or Home-button reports alone are not used as proof of Duo display transitions.

A signed Release archive for **1.0 (4)** succeeds with all four executable bundles. The Watch companion identifier matches the iPhone app. Project source membership, shared links, Watch embedding/dependency, property-list syntax, and whitespace checks pass. Physical Duo hardware has not been tested.

Product commit `f542654` is pushed to `origin/main`. The existing App Store Connect workflow successfully uploaded **1.0 (4)** on **22 October 2026 at 22:47 Toronto time** (`EXPORT SUCCEEDED`). Authenticated App Store Connect confirms build 4 is **Processing**. Apple processing and tester availability remain pending; no second upload is needed.
