# Ciggy Repository Instructions

## Delivery

- After completing repository changes, commit and push them unless the user explicitly asks not to.
- Use a focused `codex/` branch when work starts from the default branch.
- Stage only product code, tests, documentation, and intentional project configuration. Never commit secrets, `.DS_Store`, build output, or user-specific Xcode state.

## Xcode project integrity

- Keep `ciggy/ciggy.xcodeproj` synchronized with the Swift package and source tree whenever files, targets, capabilities, bundle identifiers, deployment targets, or app relationships change.
- Before committing, verify that the iOS target includes `iOS/`, the watchOS target includes `watchOS/`, both link `CiggyShared`, and the iOS target embeds and depends on the Watch app target.
- Keep the Watch app's `WKCompanionAppBundleIdentifier` exactly equal to the iOS app's bundle identifier.
- Validate with the full iOS/watchOS Xcode toolchain when it is installed. If only Command Line Tools are available, run the strongest package and syntax checks possible and report that limitation.

## Watch and iPhone synchronization

- Treat WatchConnectivity delivery as at-least-once and keep repository writes idempotent by event ID.
- Use live messages for immediate foreground sync and background user-info transfer for durable delivery.
- Preserve simulator support: the Watch simulator must be paired with the exact iPhone simulator running the companion app.
