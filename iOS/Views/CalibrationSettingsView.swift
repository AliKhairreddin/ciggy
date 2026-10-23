#if os(iOS)
import CiggyShared
import SwiftUI

struct CalibrationSettingsView: View {
    @EnvironmentObject private var settings: UserSettingsStore
    @ObservedObject private var uploads = CalibrationUploadManager.shared
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
                Text("Optional calibration shares recorded wrist motion and its timestamps with your private dashboard at ciggy.thatcanadian.dev. You and the other authorized testers can label smoking, eating, drinking, and other activity. No heart rate, notes, or location is uploaded.")
                Link("Open private dashboard", destination: CalibrationUploadManager.origin)
            }
            Section("What gets shared") {
                Text("Only motion recorded after you opt in is eligible. Recording continues while Ciggy is closed when watchOS permits; gaps remain visible. Uploads travel through your paired iPhone over Wi-Fi and may arrive later.")
                Text("Shared recordings and labels are kept for 14 days. Unsent recordings expire after 48 hours and are cleared when Ciggy next runs. Pausing stops new sharing; you can also delete data already shared by this iPhone.")
            }
            if uploads.isEnrolled {
                Section("This iPhone") {
                    LabeledContent("Tester", value: uploads.alias)
                    LabeledContent("Sharing", value: settings.settings.calibrationEnabledAt == nil ? "Paused" : "Enabled")
                    if let date = uploads.lastUploadedAt { LabeledContent("Last upload", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Text("\(uploads.pendingCount) saved recordings waiting to upload")
                    if uploads.requiresPairing {
                        Text("This pairing needs to be replaced. Forget it below, then enter a new code from the dashboard.")
                            .foregroundStyle(.orange)
                    }
                    Button(settings.settings.calibrationEnabledAt == nil ? "Resume sharing from now" : "Pause sharing") {
                        if settings.settings.calibrationEnabledAt == nil { uploads.resume() } else { uploads.pause() }
                    }.disabled(uploads.requiresPairing)
                    Button("Retry uploads") { uploads.flush() }
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
