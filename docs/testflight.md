# TestFlight delivery

The `ciggy` Xcode scheme archives the iPhone app, its widget extension, the embedded Watch app, and the Watch widget extension together. Upload the iPhone archive; do not create a separate App Store Connect app for the companion Watch app.

Use the full Xcode installation:

```sh
export DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer
swift test
xcodebuild archive \
  -project ciggy/ciggy.xcodeproj \
  -scheme ciggy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Ciggy.xcarchive \
  -allowProvisioningUpdates
```

Xcode must have a current Apple Account session for the project's developer team. If automatic provisioning reports “No Accounts”, open Xcode → Settings → Apple Accounts and reauthenticate. Install required Xcode components when prompted.

Export with `xcodebuild -exportArchive`, automatic signing, `method=app-store-connect`, and `destination=upload`. Use the existing team identifier from the project. Keep `testFlightInternalTestingOnly=false` so the same build remains eligible for external testing. Apple can manage the next build number during export; all embedded targets must retain matching versions.

After upload, verify processing in App Store Connect → Ciggy → TestFlight. Add the processed build to an internal testing group for the account holder. External testers require a separate group and Apple's beta review; an upload alone does not mean testers can install it.

For **every uploaded build**, open that exact version/build's Test Information and save its **What to Test** update details as soon as Apple makes the build editable. Include the user-visible changes, fixes, what to check, and material limitations. Read the saved notes back and verify the testing-group assignment before reporting delivery complete. Small fixes and follow-up builds need their own notes too; do not leave the field blank or copy unrelated release details. If processing or account access prevents saving or verification, report that outstanding step with the build number.

If a successful upload does not appear, check the account holder's Apple processing email as well. Apple can reject a binary after the upload step. The initial build was rejected for missing iPhone HealthKit purpose strings; both app bundles now include read and write purpose descriptions because the shared library references HealthKit. Ciggy requests read access only and does not write Health data.

## Submission declarations

Each executable bundle includes `PrivacyInfo.xcprivacy`. Xcode's synchronized source groups copy these files into the corresponding apps and extensions; the Swift package declares the app manifests as resources as well.

| API | Reason | Use |
| --- | --- | --- |
| User defaults | `CA92.1` | Private settings, history, and synchronization state |
| App-group user defaults | `1C8F.1` | Widget snapshots and navigation shared with Ciggy extensions |
| File timestamps | `C617.1` | Find calibration recordings inside app storage |
| System boot time | `8FFB.1` | Convert Core Motion event timestamps into absolute dates for logging and paired-device synchronization |

The app manifests declare no tracking or developer collection of app data. Apple-hosted TestFlight diagnostics and feedback are described separately in the [privacy policy](privacy.md).

Both app property lists set `ITSAppUsesNonExemptEncryption=false`: Ciggy uses Apple's CryptoKit SHA-256 only to derive stable event IDs and Apple's system services for paired-device transport. It has no custom encryption implementation or third-party SDKs.

Reassess these declarations when adding SDKs, networking, data collection, or required-reason APIs. See Apple's [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), and [encryption export guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
