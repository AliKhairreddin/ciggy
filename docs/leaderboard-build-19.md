# Ashtray League — build 19

Build 1.0 (19) adds a global weekly cigarette-count leaderboard. The highest saved weekly total ranks first, equal totals share a rank, and members can browse the current and previous UTC weeks. A generated alias, optional public sharing, a personal standing outside the top 50, correction synchronization, and confirmed deletion complete the flow. The League tab and its cigarette-podium symbol follow Ciggy's existing parody styling.

Product commit: `9f42cb9`, pushed to `origin/main`. This builds on the consumer polish in build 18. The standing instructions in `AGENTS.md` now explicitly embrace the parody and preserve the requested cigarette-count ranking.

## Validation

- Full shared Swift package suite: 309 tests passed. The 13 league-specific tests also passed after the final synchronization change.
- Dashboard/Worker suite: 55 tests passed, including descending ranks, ties, current/previous seasons, corrections, idempotent retries, retention, credential isolation, rate limits, and deletion races.
- TypeScript checking and Worker deployment dry run passed.
- Two iPhone UI checks passed for browsing without joining, default-off consent, week switching, expandable rules, and large text. Native screenshots were reviewed. The initial fresh simulator stalled in Apple's notification-service XPC; the completed checks used the established paired iPhone simulator without erasing its data.
- Xcode archived the iPhone app, Watch companion, and both widget extensions. All four signed bundles report version 1.0 (19); companion identifiers, the custom League symbol, and the iPhone privacy manifest were verified.

## Service deployment

Migration `0005_ashtray_league.sql` was applied to the existing production D1 database. Worker version `f660f2f3-9724-4f14-aed1-ac75034ed490` is deployed at the existing custom domain. Live checks passed for both week views, enrollment retries, aggregate revision handling, unranked zero totals, deletion/revocation, and continued protection of private calibration routes. The temporary zero-score verification membership was deleted.

The service is available at [the league endpoint](https://ciggy.thatcanadian.dev/api/league). It stores aggregate totals; no cigarette-event timestamps, notes, motion, heart rate, or location are uploaded to the league.

## TestFlight delivery

The signed build uploaded successfully and Apple processing completed. The exact 1,184-character English (Canada) What to Test notes were saved and matched after a full reload. The existing internal tester group lists 1.0 (19) as Testing. The saved notes are in [build-19.md](releases/build-19.md).
