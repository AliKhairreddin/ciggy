# Motion research and measured-data replay

## Sources and their scope

The [Smoking Event Detection (SED) and SED-FL datasets](https://mug.ee.auth.gr/smoking-event-detection/), by **Athanasios Kirmizis, Konstantinos Kyritsis, and Anastasios Delopoulos**, provide measured wrist acceleration and gyroscope data from a Mobvoi TicWatch E. The [versioned Zenodo release](https://zenodo.org/records/4507451), DOI **10.5281/zenodo.4507451**, is licensed **CC BY 4.0**. Credit these authors and the release when distributing derived results. No research recordings are bundled with Ciggy.

SED labels individual puff cycles inside smoking-session recordings. SED-FL labels complete sessions during daily activity; the labels are not interchangeable. Some people appear in both datasets, so future model evaluation must split by participant rather than random samples or overlapping windows. The benchmark below supports only SED; it does not imply that SED-FL has been evaluated.

[RisQ](https://pmc.ncbi.nlm.nih.gov/articles/PMC4682919/) describes gesture segmentation, discrimination from eating/drinking, and sequence-based session inference using a 9-axis wristband. It informs the evaluation approach but does not provide a validated Apple Watch model for this app. The [2022 Sensors paper](https://www.mdpi.com/1424-8220/22/8/3094) primarily studies **identifying the wearer** from movement. Its user-identification scores are not smoking detection scores.

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

The eight-minute post-detection lockout has been removed. After emitting a candidate, the engine continues observing gesture times and keeps one count for an uninterrupted pattern, even beyond eight minutes. A gap of more than the existing 150-second inter-gesture limit allows a new pattern to accumulate. The rolling eight-minute evidence window and gesture-shape thresholds remain unchanged. Repository deduplication now compares supporting intervals with 30 seconds of timing tolerance instead of blocking every automatic event within eight minutes; corrected intervals remain retained.

Replaying the same pinned release with this rule produced **17 historical candidates in 17/20 recordings** and **18 gyro-assisted proxy candidates in 18/20 recordings**, with the same 257 proxy shape gestures. Participant 11's first recording now emits one proxy candidate rather than two. Historical per-recording output is unchanged. An initial 90-second boundary produced an extra historical candidate for participant 2's first recording and was rejected; production retains the existing 150-second gap. This small, inspected corpus is regression evidence, not independent validation of the session boundary or a measure of free-living accuracy. No model was trained. Two cigarettes without a recognizable gap can still merge; missed gestures or a long pause within one cigarette can split it.

## Background execution constraints

Apple documents [historical recording](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/recordaccelerometer(forduration:)) at 50 Hz for up to 12 hours per request during suspension/termination, with up to three days of retention. [Retrieval](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)) can lag by three minutes.

[Background refresh](https://developer.apple.com/documentation/watchkit/using-background-tasks) is scheduled by watchOS and may be delayed or skipped; adding an active watch-face complication supports background runtime allocation. Only one refresh is pending at a time, and scheduling another replaces it. [Live iPhone messages](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)) do not wake an inactive Watch app. Durable background WatchConnectivity transfers provide another opportunity to renew recording and process recent history, with no immediate-delivery guarantee.

These limits are distinct from recognition quality. A research classifier cannot guarantee indefinite all-day watchOS execution. Extended runtime categories must match the app's intended activity; smoking monitoring is not a workout or physical-therapy session.
