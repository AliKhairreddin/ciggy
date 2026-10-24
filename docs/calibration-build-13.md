# Build 13 delivery verification

## Shipped scope

Optional calibration only: Watch extraction time, durable hourly outbox recovery after updates, bounded system-managed file batches, iPhone background staging/retry recovery, and private delivery-status snapshots. Cigarette classifiers, count/review behavior, event transport and existing Watch refresh scheduling are unchanged from build 12. Native app sources correspond to `2519c8d`; the later backend clock-skew correction is in `0ab405f`.

## Validation

- 256 shared Swift tests passed, including legacy status decoding, consent-scoped diagnostics, restored sandbox paths, delayed hourly release and persisted retry deadlines.
- 46 dashboard/API tests passed. Coverage includes private access, allowlisted report fields, stale-update ordering, small device-clock differences, expiry, revocation and deletion. TypeScript and JavaScript syntax checks passed.
- The iPhone simulator native suite passed all 5 tests on the exact paired iPhone simulator. The first attempt was cancelled during simulator startup; a serial retry completed successfully. This is not evidence of a physical-device crash or successful all-day background delivery.
- Combined iPhone/watchOS simulator compilation and the Release archive succeeded. All four app/widget bundles have valid signatures and version 1.0 (13). The companion identifier matches the iPhone identifier; both apps link CiggyShared, and the iPhone embeds/depends on Watch. Background-processing registration and the delivery-diagnostics privacy declarations were verified in the archive.
- Dashboard delivery rows rendered correctly with synthetic local fixtures. The deployed private dashboard loaded existing motion automatically and displayed the waiting-for-report state for an older app. Unauthenticated delivery and upload API requests returned 401.
- Production D1 migration `0004_delivery_reports.sql` applied successfully. The configured Worker serves https://ciggy.thatcanadian.dev; authentication, private storage and existing retention remain in place.

## TestFlight

Build 1.0 (13), App Store Connect build ID `4635af78-63d2-417b-8923-46d33e169962`, finished processing and is **Testing** in the existing Ciggy Internal group. The exact 1,853-character English (Canada) notes from `docs/releases/build-13.md` were saved in What to Test and compared after a full page reload. Group assignment was verified separately on its Builds page.

## Remaining real-device verification

Both companion apps need the update. System scheduling, Wi-Fi availability, battery conditions and force-quit behavior still affect delivery. These checks cannot establish an hourly arrival guarantee or recover expired source data. The next real-device report should identify the latest Watch preparation/queue state and iPhone receipt/upload stage; until it arrives, existing production metadata cannot establish every earlier delay's cause. Keep tester-specific diagnostic evidence out of this public repository.
