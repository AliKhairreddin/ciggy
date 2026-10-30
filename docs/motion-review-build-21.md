# Motion review delivery — build 21

Product commit `f8edf68` is pushed to `origin/main`. Build 1.0 (21) shows each original detection's motion evidence window on iPhone and Watch, and opens an in-app private dashboard from iPhone reviews. The dashboard supports interval feedback and evidence exports, including intervals with no uploaded motion. [Workflow and limitations](motion-review.md) and [build-specific testing notes](releases/build-21.md) describe the shipped behavior.

## Verification

- 323 shared Swift tests passed with the full Xcode toolchain, including seven new tests for individual windows, missing legacy timestamps, corrections, transport precision, midnight boundaries and review links. An initial full run stalled in an existing scheduling test; the complete rerun passed.
- 69 dashboard tests passed. A final targeted run also passed all four feedback/API cases after strengthening deletion tombstones. The tests cover authorization, tester isolation, same-origin writes, validation, retries, deletion, retention, review-link filtering, coverage gaps and exports without samples. Type checking and the Worker deployment dry run passed.
- Five native iPhone unit tests passed. The review creation and correction/relaunch UI tests passed; a further UI run verified individual windows, opening the Safari browser inside Ciggy, and returning with Done. Two native Watch unit tests passed on the exact simulator paired with the iPhone.
- Inspected the rendered iPhone review. Exercised the dashboard at iPhone width using synthetic data: review preselection, motion/gap selection, saving reports and preparing exports both with samples and with no samples. Production smoke checks verified same-origin sign-in redirects preserving review scope and rejection of unauthenticated private API access. No real tester data was created or altered for verification.
- Verified source membership, both shared-library links, the Watch target dependency and embedding, and the exact companion bundle identifier. The signed Release archive succeeded, with iPhone, Watch and both widget extensions reporting 1.0 (21) and valid signatures.
- Reviewed staged content for secrets, real tester data, whitespace errors and generated files.

These checks verify software behavior and delivery, not physical-device detection accuracy or background latency. Detector thresholds are unchanged. Missing uploaded motion is not proof of absent tracking.

## Deployment

Migration `0006_review_feedback.sql` applied successfully to the existing production D1 database. The configured Worker and its authenticated assets deployed to [the private dashboard](https://ciggy.thatcanadian.dev), version `b6e978f5-7ea0-447b-9b33-1b84d43cea0c`. Existing recordings and labels were preserved.

Xcode reported `EXPORT SUCCEEDED` for [TestFlight 1.0 (21)](https://appstoreconnect.apple.com/teams/a4ef6364-db9c-4a79-817d-bf54fd43e9da/apps/6824809527/testflight/ios/a67ff2f8-b442-4ba5-8730-dcce726fe994). Apple processing completed. The exact 1,775-character English (Canada) What to Test body was saved and matched after a full page reload. The existing internal group is assigned, and its build list shows this exact build as **Testing**, confirming tester availability. External testing was not changed.
