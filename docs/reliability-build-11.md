# Reliability follow-up — TestFlight 1.0 (11)

This release addresses the three code-level risks left by the [build 10 audit](reliability-audit-2026-10-23.md): competing offline corrections, interrupted correction writes, and replay of motion whose earlier session state is outside the recent window.

## Correction consistency

A review now carries its original event snapshots, an operation ID, and an exact numeric decision timestamp. Terminal decisions use one deterministic order on both devices. The event repository preserves original records and derives the visible log from the winning corrections. Reductions are reversible review effects, while explicit user deletions retain their tombstones. Added correction events use stable review/slot IDs. Continuations and overlapping summaries resolve ownership of original events so a superseded correction cannot leave duplicate additions or independently change the same scope.

The review decision and its pending delivery intent are saved together before deriving event effects or enqueueing transport. Replaying the saved journal repairs any unfinished stage. The transport acknowledges a correction only after saving its inbox, and retains that inbox entry until the review journal and derived event log succeed. The transport inbox and outbox also use atomic files; a system background-transfer completion no longer retires a critical mutation without the companion's persistence receipt. A legacy companion cannot falsely acknowledge the new correction protocol.

## Interrupted saves

The snapshot writer writes and synchronizes a temporary file before atomically replacing the destination. A failure before replacement preserves the previous snapshot and in-memory state. Unreadable authoritative files are preserved and reported rather than silently replaced by empty history.

Manual events and explicit deletions save their outbound intent in the same repository snapshot as the local mutation. Startup and foreground recovery queue those intents and retire them only after the transport outbox is durable. Incoming events/deletions bypass local publication to prevent echo loops. Manual forms keep their drafts on failed local writes, and failed Undo keeps its confirmation available for retry.

Automatic detection has a separate write-ahead ingestion journal. After a restart it completes the event, daily review, and outgoing queue before retiring that job. Replaying an already hidden or reviewed detection does not reopen a review. Live detector progress and the historical cursor/classifier/source origin also use atomic snapshots. Historical progress advances only after candidate ingestion succeeds.

The compact iPhone dashboard now puts manual logging directly after tracking freshness and before accumulated review cards. Native large-text testing exposed that the growing review list could otherwise bury the logging control. The folded layout already kept its check-in control ahead of reviews.

The adjustment sheets preserve the selected count and show an error when saving fails. Retrying a previously journaled decision reuses the same operation instead of creating another correction.

## Motion history continuity

A cold replay cannot infer whether the first partial episode was counted before its left edge. It now defers that ambiguous episode until it can replay from a known source origin or saved classifier, or observes a continuous valid quiet interval longer than the existing 150-second session boundary. Missing and malformed samples cannot prove quiet. Later episodes with a proven boundary may still appear in the priority pass.

Missing intervals retain resumable classifier checkpoints. Reconciliation reads forward from that state and adopts the repaired chronological state only after verifying the source. Pending and expired coverage remain visible. Detection thresholds have not changed.

## Validation

- **251 shared Swift tests passed**, including 58 additional regressions. The two duplicate-history scenarios were first reproduced against untouched build-10 commit `a6a8594`, where a two-episode trace produced three distinct event IDs.
- Tests exercise actual snapshot files with preferences removed, injected failures at transaction boundaries, opposing offline corrections, duplicate/reordered deliveries, overlapping review scopes, missing originals, and explicit deletions arriving before alias discovery. These are disk-reload and failure-injection tests; they do not simulate every possible hardware failure.
- Motion tests cover long dense/sparse/dense episodes, source holes, empty and clipped queries, exact quiet-boundary limits, expired prefixes, resumed classifier checkpoints, and ambiguous history that remains pending. The existing 800-trace synthetic sweep still runs 974,648 samples through each pipeline. These invented traces do not measure real-world recognition accuracy.
- **41 dashboard/backend tests**, TypeScript checks, and **5 Python dataset-decoder tests passed**. No dashboard/backend source changed and no duplicate service deployment is required.
- **5 iOS unit tests and all 18 executable iPhone UI scenarios passed across the full run and focused reruns.** Two hardware-specific Duo scenarios were skipped on the standard iPhone simulator. The initial run exposed the buried manual-log control plus two UI automation issues (scroll overshoot and the stepper's accessibility identifier); these were corrected and the affected scenarios passed. A final manual-save/Undo run passed after adding the event-delivery journal.
- **2 Watch unit tests and all 5 Watch UI scenarios passed**, including logging exactly one event through relaunch, appearance, and launch checks. The Watch simulator was paired with the exact companion iPhone simulator. The final journal-enabled Watch save/relaunch check and both unit tests passed. An initial rerun received delayed iPhone test history during its count assertion; after synchronization settled, one save added exactly one event. On-disk inspection verified 49 unique event IDs, matching deletion IDs, and no pending event intents on each device.
- Xcode project checks verified iOS/watchOS source membership, both shared-package links, Watch embedding/dependency, matching companion identifiers, and all build-number configurations at 11. Release archive and TestFlight distribution verification are recorded below once complete.

## Limits

Both apps must be updated for correction protocol v2. Earlier builds' already-applied independent additions/deletions lack enough provenance to reconstruct every past conflict safely; this release preserves that history rather than inventing reversals. Motion that was never recorded or has expired cannot be recovered, and a truncated ambiguous episode may remain incomplete. Physical Watch background timing, battery use, and smoking/eating/drinking discrimination still require real-device observation.
