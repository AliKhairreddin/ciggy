# Build 16 background refresh delivery

Ciggy now requests a Watch background refresh with a 15-minute preferred date instead of 30 minutes. Each granted wake prioritizes analyzing and saving cigarette estimates and queuing synchronization before optional calibration extraction. The recent pass checks 15 minutes with up to eight preceding minutes of classifier context; chronological history and unfinished intervals remain available for reconciliation.

Refresh scheduling consumes the old appointment before arming its successor. Foreground cancellation cannot revoke an independent background grant, and a background grant retires longer foreground work before starting its bounded operation. Inactive requests run under delegate-managed background tasks so expiration controls cancellation.

The five-minute motion-and-duration counting rule is unchanged. A 15-minute preferred date is not an exact timer or guaranteed delivery interval. An active-face Ciggy complication improves refresh opportunities; watchOS controls execution and WatchConnectivity delivery. See [background tracking](background-tracking.md) for Apple references and the physical-device test protocol.

## Validation

- Full configured Xcode iOS/watchOS toolchain used.
- Swift package: 293 tests passed, including refresh ordering, cooperative budgets, cancellation ownership, recent-window boundaries, older history recovery, replay and duplicate protection.
- Native iPhone simulator suite: five tests passed.
- Native paired Watch simulator suite: two tests passed.
- Xcode source membership, shared library links, Watch dependency/embedding and companion identifiers verified.
- Signed Release archive succeeded. The iPhone, Watch and both widget extensions have matching version 1.0/build 16 and verified signatures.
- Staged content reviewed for whitespace errors, credentials, private tester evidence and unintended generated files.

These automated checks do not establish physical-device background latency, battery use or recognition accuracy. Those measurements remain necessary.

## Delivery

Product commit `acfe482` was pushed to `main`. App Store Connect accepted and finished processing the signed build 16 upload. The exact 1,488-character build-specific What to Test body was saved and matched after a full page reload. The existing internal tester group is assigned and lists version 1.0 (16) as Testing.

The exact update details are in [the release notes](releases/build-16.md). This is a native app update; no server deployment is required.
