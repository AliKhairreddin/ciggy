# Motion research and measured-data replay

## Sources and their scope

The [Smoking Event Detection (SED) and SED-FL datasets](https://mug.ee.auth.gr/smoking-event-detection/), by **Athanasios Kirmizis, Konstantinos Kyritsis, and Anastasios Delopoulos**, provide measured wrist acceleration and gyroscope data from a Mobvoi TicWatch E. The [versioned Zenodo release](https://zenodo.org/records/4507451), DOI **10.5281/zenodo.4507451**, is licensed **CC BY 4.0**. Credit these authors and the release when distributing derived results. No research recordings are bundled with Ciggy.

SED labels individual puff cycles inside smoking-session recordings. SED-FL labels complete sessions during daily activity; the labels are not interchangeable. Some people appear in both datasets, so future model evaluation must split by participant rather than random samples or overlapping windows. The benchmark below supports only SED; it does not imply that SED-FL has been evaluated.

[RisQ](https://pmc.ncbi.nlm.nih.gov/articles/PMC4682919/) describes gesture segmentation, discrimination from eating/drinking, and sequence-based session inference using a 9-axis wristband. It informs the evaluation approach but does not provide a validated Apple Watch model for this app. The [2022 Sensors paper](https://www.mdpi.com/1424-8220/22/8/3094) primarily studies **identifying the wearer** from movement. Its user-identification scores are not smoking detection scores.

The current detector also uses a [five-minute cigarette-duration estimate](cigarette-duration.md), documented separately with measured smoking-duration studies. No representative global average was established. That duration is an engineering default combined with motion evidence, not a trained classifier or a validated way to identify physical cigarette boundaries.

## Reproduce the SED baseline

Python 3.9+ and the full Xcode Swift toolchain are sufficient. The exporter uses only the Python standard library. Keep downloads, exported CSVs, and generated reports outside the repository:

```sh
python3 Tools/MotionBenchmark/export_sed.py \
  --download --pickle /tmp/Ciggy-SED.pkl --output /tmp/Ciggy-SED-CSV

DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer \
  swift run CiggyMotionBenchmark /tmp/Ciggy-SED-CSV > /tmp/Ciggy-SED-benchmark.json

python3 -m unittest discover -s Tools/MotionBenchmark -p 'test_*.py'
```

The output directory must not already exist. Omitting `--download` reuses a previously downloaded file. The exporter verifies the exact 30,686,808-byte release and SHA-256 `0c21f6a78dc1c2c2814f596bdcc9339c229255dd860d5c1ae92c3836b65fa414` before decoding. It interprets a small allowlist of pickle operations as **inert data descriptors**. It never invokes pickle globals/reducers, imports NumPy/Pandas, or uses `pickle.load`. Numeric blocks accept only float64/int64 byte arrays. The release's object-array metadata is restricted to the eight known column-name strings; object sample arrays and unknown globals/opcodes are rejected.

The Swift executable converts raw acceleration from m/s² to g by dividing by 9.80665. Gyroscope input remains rad/s. It starts independent classifier state for each recording, preserves relative timestamps, and checks row counts, monotonic time, labels, and duration against the manifest. It exercises:

- Production `RecordedMotionAnalyzer`, with its existing acceleration-only processing and default 10 Hz analysis interval.
- `MotionGestureEngine` plus `DetectionFusionEngine` using measured gyro and gravity estimated with a 0.25-second filter. This is a **gyro-assisted proxy**, not actual Apple `CMDeviceMotion` fusion or its 30 Hz sampling schedule.

An optional second executable argument selects sensitivity in `0...1`; the documented baseline uses the unchanged default **0.5**. No classifier thresholds were trained or tuned on this corpus.

## Measured baseline, October 23, 2026

**Historical result:** this baseline and the build 6 comparison below predate the five-minute duration rule. They remain records of those earlier implementations. Running the replay command with current code measures the current detector and may produce different counts; the numbers below must not be presented as current duration-model validation.

The pinned release exported **479,251 samples**, **20 smoking recordings**, **11 participants**, **276 annotated puff cycles**, and **9,584.62 seconds** of recording (~159.74 minutes).

| Output at default sensitivity | Measured result |
| --- | ---: |
| Historical pipeline cigarette/session candidates | 17 |
| Recordings with at least one historical candidate | 17 / 20 |
| Gyro-assisted proxy completed shape gestures | 257 |
| Gyro-assisted proxy cigarette/session candidates | 19 |
| Recordings with at least one proxy candidate | 18 / 20 |

The proxy emitted two candidates for participant 11's first recording, while other recordings were missed. Historical processing missed both participant 4 recordings and participant 7's recording. A total candidate count close to 20 can therefore hide both missed and duplicate sessions.

These are **positive-recording coverage and raw output counts**, not daily accuracy, puff precision/recall, or free-living false-positive rates. Detected shape gestures are not matched one-to-one to annotated puffs. SED contains no representative non-smoking day, the hardware differs, and the publisher normalized hand/orientation. Claims about background reliability also require suspension, renewal, transport, energy, and actual smoking tests on physical Apple Watch hardware.

## Session-boundary update, build 6

Build 6 removed the eight-minute post-detection lockout. After emitting a candidate, that implementation continued observing gesture times and kept one count for an uninterrupted pattern, even beyond eight minutes. A gap of more than the existing 150-second inter-gesture limit allowed a new pattern to accumulate. The rolling eight-minute evidence window and gesture-shape thresholds remained unchanged. Repository deduplication compared supporting intervals with 30 seconds of timing tolerance instead of blocking every automatic event within eight minutes; corrected intervals remained retained.

Replaying the same pinned release with that rule produced **17 historical candidates in 17/20 recordings** and **18 gyro-assisted proxy candidates in 18/20 recordings**, with the same 257 proxy shape gestures. Participant 11's first recording emitted one proxy candidate rather than two. Historical per-recording output was unchanged. An initial 90-second boundary produced an extra historical candidate for participant 2's first recording and was rejected; build 6 retained the 150-second gap. This small, inspected corpus was regression evidence, not independent validation of the session boundary or a measure of free-living accuracy. No model was trained. Under that rule, two cigarettes without a recognizable gap could merge; missed gestures or a long pause within one cigarette could split it.

## Duration-based counting update

The current engine requires at least five minutes of qualifying activity and the sensitivity-dependent gesture count before the first estimate. Continued qualifying activity can produce another estimate after each further five-minute segment with fresh gesture evidence. A quiet gap is no longer required between counts. More than 150 seconds without an accepted gesture still breaks incomplete evidence, and missing source intervals cannot prove continuity. Historical duration state persists with the analyzer across batch boundaries and relaunches. Live sampling stops, restarts and gaps clear incomplete live evidence; a saved checkpoint does not grant credit for unobserved time. Initial detection requires five minutes of evidence plus any watchOS availability, execution and delivery delays, so a five-minute update is not guaranteed.

This changes the meaning of the estimate: sustained activity is divided into duration segments rather than assigned one count until a pause. A shorter cigarette may be missed and a long cigarette may be divided; real-device validation is needed for both. See [the evidence, exact counting rule and limitations](cigarette-duration.md). Neither the old SED counts nor the older synthetic sweep establish the accuracy of this change.

## Background execution constraints

Apple documents [historical recording](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/recordaccelerometer(forduration:)) at 50 Hz for up to 12 hours per request during suspension/termination, with up to three days of retention. [Retrieval](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)) can lag by three minutes.

[Background refresh](https://developer.apple.com/documentation/watchkit/using-background-tasks) is scheduled by watchOS and may be delayed or skipped; adding an active watch-face complication supports background runtime allocation. Only one refresh is pending at a time, and scheduling another replaces it. [Live iPhone messages](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)) do not wake an inactive Watch app. Durable background WatchConnectivity transfers provide another opportunity to renew recording and process recent history, with no immediate-delivery guarantee.

These limits are distinct from recognition quality. A research classifier cannot guarantee indefinite all-day watchOS execution. Extended runtime categories must match the app's intended activity; smoking monitoring is not a workout or physical-therapy session.
