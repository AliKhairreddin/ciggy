# Keyboard and rotation follow-up — TestFlight 1.0 (12)

The unresolved SwiftUI frame warning from [build 11](reliability-build-11.md) was reproduced on unchanged commit `a43d491`: the folded note-entry/rotation UI test passed while its result bundle contained “Invalid frame dimension (negative or non-finite).”

The trigger was isolated to the manual form's keyboard accessory toolbar. The logging sheet now owns note focus and puts Done in its navigation bar while editing. Done dismisses the keyboard without saving or clearing the note. This avoids the problematic accessory layout while retaining an accessible dismissal action in portrait and landscape.

Three added UI regressions rotate with the keyboard still visible through landscape left, landscape right, and portrait, then dismiss/reopen the keyboard, check the draft, and verify one Save followed by Undo. They exercise the normal layout, simulated folded layout, and largest accessibility text size.

`Tools/Validation/check_ui_test_result.py` rejects failed or empty runs and any runtime warnings in an Xcode result bundle. It was checked against the original passing-but-warning baseline (rejected) and the corrected reproduction (accepted with zero warnings).

## Validation

- Original reproduction: one passing test, one runtime warning.
- Corrected reproduction: one passing test, zero runtime warnings.
- **251 shared Swift tests passed** against the isolated build 12 source, including the existing 800-trace motion sweep.
- The broader run passed **14 native tests** (5 iOS unit tests and 9 UI scenarios), with zero failures, skips, or runtime warnings. It covers existing folded drafts, goal/report rotation, manual Save/Undo, Cancel, large text, and the two new standard/folded keyboard scenarios.
- The added largest-text keyboard scenario initially used short drags that could not expand the medium sheet. The test now uses a full upward swipe to expand it, and permits a partially visible multiline field to receive focus while retaining full-visibility checks for buttons. The corrected case passed with zero runtime warnings, including both landscape rotations with the keyboard open, dismissal/reopening, draft preservation, Save, and Undo. Across the broader run and focused rerun, all **15 targeted native tests** passed (5 unit tests and 10 UI scenarios).
- Project checks verified source membership, CiggyShared links, Watch embedding/dependency, matching companion bundle IDs, and all 16 build-number configurations at 12.

## Delivery

Validation is complete; release archive and TestFlight delivery are in progress. The build-specific [What to Test](releases/build-12.md) will be saved and read back in App Store Connect before delivery is marked complete.
