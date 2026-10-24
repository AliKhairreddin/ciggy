# TestFlight 1.0 (12) — What to Test

This build fixes the layout warning triggered by the keyboard accessory toolbar in the iPhone manual logging sheet. While editing a note, Done now appears at the top right of the sheet and dismisses the keyboard without saving or clearing the draft.

Open Add missed cigarette, enter a note, and rotate between portrait and both landscape orientations while the keyboard is open. Check that the note survives, Done stays reachable, and the keyboard can be dismissed and reopened. Then save once and verify the count increases by one; Undo should restore the previous count. Also check Cancel and logging with the largest accessibility text sizes.

The automated checks now inspect runtime warnings as well as test failures, so a passing UI test cannot conceal a layout warning. This build includes build 11's reliable offline corrections, interrupted-save recovery, and motion-history replay safeguards; update both companion apps.

Known limitations: real Duo hinge hardware was not tested; folded-layout checks use the simulator preview. Existing experimental motion-detection limitations and unrecoverable or ambiguous older history still apply.
