#if os(iOS)
import CiggyShared
import SwiftUI

struct CalibrationSettingsView: View {
    @EnvironmentObject private var settings: UserSettingsStore
    @ObservedObject private var uploads = CalibrationUploadManager.shared
    @ObservedObject private var watchStatus = TrackingStatusStore.shared
    @ObservedObject private var sync = ConnectivityManager.shared
    @State private var alias = ""
    @State private var code = ""
    @State private var consent = false
    @State private var error: String?
    @State private var deleting = false
    @State private var forgetting = false

    var body: some View {
        Form {
            Section {
                Text("Help Ciggy recognize your smoking movements")
                    .font(.headline)
                Text("Optional calibration shares recorded wrist motion, its timestamps, and delivery status (queue counts, transfer times and app builds) with your private dashboard at ciggy.thatcanadian.dev. You and the other authorized testers can label smoking, eating, drinking, and other activity. No heart rate, notes, or location is uploaded.")
                Link("Open private dashboard", destination: CalibrationUploadManager.origin)
            }
            Section("What gets shared") {
                Text("Only motion recorded after you opt in is eligible. The Watch saves motion locally and releases hourly batches to your iPhone. Both devices hand a bounded queue to Apple’s background transfer service, so files can continue while the apps are in the background. Your iPhone uploads over Wi-Fi with two network connections at most. Recordings are motion chunks, not one file per cigarette.")
                Text("Delivery happens when watchOS gives Ciggy time to run; it can take longer than an hour. Background history also needs time to become available. The dashboard shows the latest received motion and any gaps. Cigarette tracking and count sync keep working independently.")
                Text("Shared recordings and labels are kept for 14 days. The Watch queue is limited to 80 MB and 48 hours; the oldest unsent files are cleared first when either limit is reached. Pausing stops new sharing; you can also delete data already shared by this iPhone.")
            }
            if uploads.isEnrolled {
                Section("This iPhone") {
                    LabeledContent("Tester", value: uploads.alias)
                    LabeledContent("Sharing", value: settings.settings.calibrationEnabledAt == nil ? "Paused" : "Enabled")
                    if let date = uploads.lastUploadedAt { LabeledContent("Last upload", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Text("\(uploads.pendingCount) saved recordings waiting to upload")
                    Text("\(uploads.scheduledCount) recordings handed to background uploads")
                    if let received = MotionRecordingStore.shared.lastReceivedAt {
                        LabeledContent("Last received from Watch", value: received.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let retry = uploads.nextRetryAt {
                        LabeledContent("Retry eligible after", value: retry.formatted(date: .abbreviated, time: .shortened))
                    }
                    if uploads.requiresPairing {
                        Text("This pairing needs to be replaced. Forget it below, then enter a new code from the dashboard.")
                            .foregroundStyle(.orange)
                    }
                    Button(settings.settings.calibrationEnabledAt == nil ? "Resume sharing from now" : "Pause sharing") {
                        if settings.settings.calibrationEnabledAt == nil { uploads.resume() } else { uploads.pause() }
                    }.disabled(uploads.requiresPairing)
                    if let consent = settings.settings.calibrationEnabledAt {
                        if let status = watchStatus.status?.calibration {
                            Text(status.detail(consent: consent)).font(.footnote)
                            if let checked = status.checkedAt {
                                LabeledContent("Watch last checked", value: checked.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let batch = status.lastBatchAt { LabeledContent("Watch last batch", value: batch.formatted(date: .abbreviated, time: .shortened)) }
                            if let due = status.nextBatchAt { LabeledContent("Watch batch eligible after", value: due.formatted(date: .abbreviated, time: .shortened)) }
                        } else {
                            Text("Waiting for sharing status from Watch. Make sure both apps are updated. A check is requested below; watchOS decides when it runs.")
                                .font(.footnote)
                        }
                    }
                    Button("Check Watch and retry uploads") {
                        ConnectivityManager.shared.send(settings: settings.settings)
                        ConnectivityManager.shared.requestHistoryRefresh()
                        ConnectivityManager.shared.resumeSync()
                        uploads.flush()
                    }
                    Text("Sharing is automatic. This button requests an extra check; you do not need to press it for each batch.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let issue = sync.lastSyncError {
                        Text("Live Watch check: \(issue) Background file delivery can continue without a live connection.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Delete my shared calibration data", role: .destructive) { deleting = true }
                    Button("Forget pairing and pair again", role: .destructive) { forgetting = true }
                }
            } else {
                Section("Pair with the dashboard") {
                    Text("Sign in to the dashboard and create a pairing code for this tester. Each tester pairs their own iPhone.")
                    TextField("Your name or nickname", text: $alias)
                        .textContentType(.nickname)
                    TextField("Pairing code", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Toggle("I agree to share my motion for calibration", isOn: $consent)
                    Button("Pair and start sharing") {
                        Task {
                            do { try await uploads.enroll(code: code, alias: alias); code = ""; error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(!consent || code.isEmpty || alias.isEmpty || uploads.isWorking)
                }
            }
            if let message = error ?? uploads.lastError {
                Section { Text(message).foregroundStyle(.orange) }
            }
            if let message = uploads.lastDeliveryError {
                Section("Delivery status") { Text(message).foregroundStyle(.orange) }
            }
        }
        .disabled(uploads.isWorking)
        .navigationTitle("Motion calibration")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this tester’s shared recordings and labels?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete my shared data", role: .destructive) {
                Task {
                    do { try await uploads.deleteSharedData(); error = nil; consent = false; code = "" }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("This pauses sharing and revokes this iPhone’s pairing. Your cigarette history is kept.")
        }
        .confirmationDialog("Forget this iPhone’s pairing?", isPresented: $forgetting, titleVisibility: .visible) {
            Button("Forget pairing", role: .destructive) {
                do { try uploads.forgetPairing(); error = nil; consent = false; code = "" }
                catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("This stops sharing and removes the credential from this iPhone. It does not delete previously shared data. Delete that data on the private dashboard, or let its 14-day retention expire.")
        }
    }
}
#endif
