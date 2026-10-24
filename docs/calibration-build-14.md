# Build 14 calibration recovery

## Diagnosis and scope

Symbolicated physical Watch crash reports from earlier releases terminate inside `CMSensorRecorder.accelerometerData(from:to:)`, called by saved-history reconciliation. The same call path remains in build 13. Core Motion asserts that the start is within three days of the current wall clock. Reconciliation derives its retention edge from an analysis end delayed by three minutes; a legacy repair without a capture origin can therefore request data beyond the native limit.

`SensorHistoryQuery` bounds the native read at the moment of each query, including a small boundary margin, finite/ordered dates and the documented maximum request duration. Both Watch readers use it. This changes the sensor-access boundary only: classifiers, thresholds, session separation, counters, review behavior, capture scheduling and cigarette-event transport are untouched. Existing coverage checks still expose missing leading samples.

The iPhone previously discarded delivery-report completions without checking success and throttled based on queue time. Reports now require a valid server receipt, persist retry backoff, honor Retry-After, and hand delayed retries to background URLSession. Reports are queued before raw-file preparation. Old-consent and cancelled callbacks cannot restart sharing. A report failure is visible separately from a motion-file upload error.

The existing hourly Watch release policy and Wi-Fi iPhone uploads remain. No continuous background process, workout session, new motion collection or server deployment is introduced. Opening an updated app once is a release verification step, not the intended recurring delivery workflow.

## Validation

All 316 tests passed: 263 shared Swift tests, 46 dashboard/API tests, five native iPhone tests and two native Watch tests. The native targets used the exact paired simulators. Regression tests cover delayed retention edges, expired/invalid/future requests, unchanged recent windows, saved-gap replay, server acknowledgment, persisted report retry deadlines, provider delays and clock rollback. Native test builds emitted the existing App Intents metadata-skipped warning; the iPhone test host also logged Watch-app-not-installed while the Watch test app was not yet installed. The subsequent paired Watch test run passed.

The signed Release archive passed. The iPhone, embedded Watch app and both widget extensions are version 1.0, build 14; bundle relationships and code signatures were verified. TestFlight verification is recorded after completion. Real-device confirmation after installation remains necessary; earlier crash reports establish the defective call path but are not a crash-free test of the new binary.

Tester-specific crash reports and production metadata stay outside this public repository.
