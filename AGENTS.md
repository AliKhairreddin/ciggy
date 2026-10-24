# Ciggy Repository Instructions

## Delivery

- Work directly on `main`. Do not create or switch to another branch unless the user explicitly asks.
- Before making changes, confirm `main` is checked out and fast-forward it from `origin/main` when safe.
- After completing repository changes, commit and push directly to `origin/main` unless the user explicitly asks not to.
- Keep `main` as the only local and remote branch; delete other branches after their work is safely present on and pushed to `main`.
- Stage only product code, tests, documentation, and intentional project configuration. Never commit secrets, `.DS_Store`, build output, or user-specific Xcode state.

## TestFlight update details

- Every uploaded build must have build-specific update details saved in App Store Connect's **What to Test** field. This is required for every build, including small fixes and follow-up builds.
- Explain the user-visible changes, relevant fixes, what testers should check, and any material known limitations. Match the notes to that exact version/build; do not leave the field blank or reuse unrelated notes.
- As soon as Apple makes an uploaded build editable, save its notes and read them back to verify persistence. Verify the final build's tester-group assignment as part of delivery.
- Do not report TestFlight delivery as complete until processing, tester availability, and saved update details are verified. If Apple processing or account access blocks verification, report the build number and the outstanding step explicitly.

## Xcode project integrity

- Full Xcode is installed at `/Applications/dev/Xcode.app`, outside the standard `/Applications` location. Do not infer that Xcode is unavailable from `xcode-select -p` reporting Command Line Tools.
- Run Xcode commands with `DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer` (for example, `DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcodebuild ...`) so builds, tests, `xcrun`, and simulator tooling use the full iOS/watchOS toolchain.
- Keep `ciggy/ciggy.xcodeproj` synchronized with the Swift package and source tree whenever files, targets, capabilities, bundle identifiers, deployment targets, or app relationships change.
- Before committing, verify that the iOS target includes `iOS/`, the watchOS target includes `watchOS/`, both link `CiggyShared`, and the iOS target embeds and depends on the Watch app target.
- Keep the Watch app's `WKCompanionAppBundleIdentifier` exactly equal to the iOS app's bundle identifier.
- Validate with the full iOS/watchOS Xcode toolchain when it is installed. If only Command Line Tools are available, run the strongest package and syntax checks possible and report that limitation.

## Watch and iPhone synchronization

- Treat WatchConnectivity delivery as at-least-once and keep repository writes idempotent by event ID.
- Use live messages for immediate foreground sync and background user-info transfer for durable delivery.
- Preserve simulator support: the Watch simulator must be paired with the exact iPhone simulator running the companion app.

## Calibration data privacy

- Keep real tester motion, timestamps, upload/sample totals, private labels, screenshots and account details out of repository files, release notes and test fixtures. This repository is public. Use synthetic fixtures and generic diagnoses; keep tester-specific evidence in the private dashboard or local temporary files.
- Before committing diagnostic documentation, review staged content for tester data as well as credentials.
