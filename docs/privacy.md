# Ciggy privacy policy

Effective October 23, 2026.

Ciggy is an iPhone and Apple Watch smoking-awareness app developed by Ali Khairreddin. Ordinary cigarette tracking stays on your devices and does not require an account. Ciggy has no advertising or third-party analytics SDK. An optional, separately consented calibration feature sends wrist-motion recordings to the private Ciggy dashboard described below.

## Information on your devices

Ciggy stores smoking events, optional notes, goals, settings, detection summaries, and corrections locally. If you enable assisted detection, it uses wrist motion to identify possible smoking gestures. If you grant HealthKit permission, it can read heart-rate samples as optional context. Ciggy does not write health data to HealthKit. Automatic detection is experimental and is not a medical measurement.

Opt-in calibration recordings contain motion samples and the label you select. Ciggy saves these recordings in its private app storage. Background motion recording is managed by Apple's Core Motion services; its availability and retention are controlled by the operating system.

## Sharing between your devices

Ciggy uses Apple's WatchConnectivity framework to synchronize events, settings, corrections, detection feedback, and calibration recordings between your paired iPhone and Apple Watch. Widgets and complications read a local summary shared with the app. Live Activities and notifications may display counts or summaries on your Lock Screen or Watch, depending on your device settings.

If you explicitly export or share a calibration recording, the destination you choose receives that file. Device backups and transfers may also contain app data according to your Apple settings.

## Optional private calibration dashboard

Calibration sharing is off by default. Each tester must pair their own iPhone with a single-use code from `https://ciggy.thatcanadian.dev` and explicitly agree before sharing starts. A name or nickname identifies that tester. The upload credential is saved in that iPhone’s Keychain, not the Watch, source code, or widgets.

After consent, Ciggy can collect recorded wrist acceleration, estimated gravity, source labels, and precise timestamps in five-minute chunks. Background recordings have no gyroscope; the interface distinguishes them from intentional live calibration recordings. Only recordings starting after the current consent time are eligible for automatic upload. Ciggy does not upload heart rate, cigarette notes, or location through this feature.

While calibration sharing is enabled, Ciggy also sends small delivery reports containing queue counts, capture/transfer/upload timestamps, and app build numbers. Reports help distinguish delays on the Watch, iPhone, or server; they contain no cigarette events, free-form device errors, credentials, or heart-rate values. Only the latest report per participant is retained, for at most 14 days, under the same private access and deletion controls. Reports are snapshots and may themselves arrive late.

Recordings travel from the Watch to its paired iPhone and upload over Wi-Fi using Apple’s background networking service. watchOS controls recording availability and background runtime, so the dashboard may have gaps or delayed data; it is not a complete account of a person’s activity. Unsent calibration files on the Watch are limited to 48 hours and 80 MB. The iPhone removes acknowledged uploads and expires unsent recordings after 48 hours when the queue next runs.

The dashboard runs on the developer’s Cloudflare account with private R2 storage and D1 metadata. Cloudflare Access sign-in and an email allowlist restrict the dashboard to authorized testers. Those testers can see shared recordings and add or correct labels for smoking and other activity. App upload credentials allow only the paired tester’s uploads and deletion; they cannot read other testers’ motion. Raw recordings and labels expire 14 days after their first upload; an hourly cleanup removes expired storage. Expired records are excluded from reads immediately. Device connections expire after 30 days and can be paired again. Minimal deletion markers prevent delayed duplicate uploads from restoring removed recordings. Cloudflare-managed database backups follow Cloudflare’s separate backup retention, so confirmed deletion removes live data without promising immediate erasure of provider backups.

You can pause sharing in iPhone Settings → Private motion calibration. A pause stops new uploads and tells the paired Watch to stop calibration capture when settings synchronize. A transfer already received by the server cannot be recalled by cancelling its network request. “Delete my shared calibration data” pauses sharing, revokes the pairing, and removes that tester’s shared recordings and labels after the server confirms deletion. Your cigarette history is separate and is kept. Existing local files are never uploaded under a later consent period.

The recordings and labels support evaluation and improvement of smoking detection. Labelling an interval does not itself train a model or change the detector on your devices. Exporting a labeled dataset creates an additional copy under your control.

## TestFlight and feedback

Apple operates TestFlight and may provide the developer with beta-testing diagnostics, crash reports, and feedback you submit. Apple's privacy policies and your TestFlight settings govern that service. Feedback you send to the developer may contain contact information or other details that you choose to include; it is used to investigate and respond to your report.

## Your controls

You can decline or revoke Motion & Fitness, HealthKit, and notification permissions in your device settings. You can correct recorded counts in Ciggy. Removing Ciggy and its associated extensions from both devices removes their local app storage; backups and any copies you exported remain under your control. Removing Ciggy does not delete the original heart-rate samples in Apple Health.

## Contact and updates

For a privacy question, use the feedback contact shown in Ciggy's TestFlight listing. General questions can also be raised at the [Ciggy project](https://github.com/AliKhairreddin/ciggy/issues). Do not post health data, smoking history, or private contact details in public issues.

This policy will be updated if Ciggy's data practices change.
