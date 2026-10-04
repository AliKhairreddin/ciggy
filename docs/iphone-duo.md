# Ciggy on iPhone Duo

The same Ciggy app adapts to its window and the system's reserved regions. There is no separate app, data store, or device-name check. Existing iPhones and iPads retain support back to iOS 17.

- **Cover display and narrow Split View:** one scrollable column.
- **Open portrait and landscape:** today and progress beside trends, Watch reviews, and recent check-ins. Reports place charts beside their range controls; Goals and Settings use overview and editing panels.
- **Partially folded like a book:** overview on the leading half, controls on the trailing half, with neither pane crossing the system's hinge frame or interactive margins.
- **Seated, like a Nintendo DS:** the upper half shows today's count and weekly activity; the lower half provides an inline note, cigarette logging, undo, and Watch review controls. Reports, Goals, and Settings follow the same overview-above, controls-below pattern.

Both panes scroll independently. Screen-level state holds notes, unsaved goals, settings, and the report range across geometry changes. Logging uses the same repository and WatchConnectivity path as the phone's existing log sheet. Right-to-left layouts reverse the book's reading order. Accessibility text sizes use a single column when the display is flat, while folded displays retain independently scrollable halves.

## SDK requirement

Native hinge and camera avoidance requires building with the **iOS 27.1 SDK in Xcode 27.1 or newer** and running on iOS 27.1. `CiggyAdaptiveScreen` queries active division and occlusion regions using their fixed coordinate space. Their frames include Apple's reserved margins; the layout uses these actual frames rather than guessing a midpoint or interpreting phone tilt as a hinge angle.

The compile-time SwiftUI module-version guard excludes Duo symbols from Xcode 27.0 (SwiftUI 8.0.84). Older builds still adapt to portrait, landscape, and window resizing, but cannot detect the hinge or provide the SDK 27.1 display integration. Runtime availability preserves compatibility with older iOS versions when using the new SDK.

Apple references: [Preparing your app](https://developer.apple.com/videos/play/tech-talks/111461/), [adaptive layouts and reserved regions](https://developer.apple.com/videos/play/tech-talks/111463/), and [the reserved-region query](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)).

## Verification

Run shared tests with the installed full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer swift test
```

`CiggyLayoutPlanTests` covers the cover display, open portrait and landscape, narrow multitasking, off-center hinges, interactive margins, right-to-left reading order, large text, and inactive or unusable divisions.

`CiggyAdaptiveUITests` checks rotation, logging/undo, note and goal drafts, report range, and large-text controls. In Debug only, `--ciggy-preview-fold` injects a 24-point division region, horizontal in portrait and vertical in landscape. This exercises the pane geometry on existing simulators; it does **not** validate hardware hinge detection or the iOS 27.1 API branch.

Before a Duo release, build with Xcode 27.1 and use the Duo Simulator's controls to test closed, fully open, book, and seated poses in both orientations. Confirm the native reserved-region branch compiles, the panels stay clear of the hinge and active camera, sheets remain accessible, drafts survive opening and closing, and narrow Split View falls back to one column. Also check a physical Duo when available.

App Store/TestFlight distribution requires an existing signing and publishing workflow. Simulator installation alone is not a production release.

## Validation on this Mac

The Duo changes passed 50 shared tests and the complete iOS Simulator build, including the embedded watchOS app, using Xcode 27.0. UI test bundles compiled, but two execution attempts could not start: CoreSimulator lost its service connection and the runner exited before bootstrapping. No passing UI-runtime or physical-Duo test is claimed.

A release archive was attempted with automatic provisioning updates. Xcode rejected the saved developer-account login and could not obtain the iPhone or Watch signing profiles. Native Duo validation also remains blocked by the missing Xcode 27.1 SDK; Apple's beta download endpoint requires authentication.
