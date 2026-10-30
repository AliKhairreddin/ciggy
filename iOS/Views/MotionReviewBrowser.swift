#if os(iOS)
import CiggyShared
import SafariServices
import SwiftUI

/// Safari's authenticated browser stays inside Ciggy and supports downloads/sharing.
struct MotionReviewBrowser: View {
    let review: DetectionReview
    @State private var url: URL?
    var body: some View {
        Group {
            if let url { PrivateMotionBrowser(url: url).ignoresSafeArea() }
            else { ProgressView("Opening motion review…") }
        }
        .task {
            let participant = await CalibrationUploadManager.shared.dashboardParticipantID()
            url = review.motionDashboardURL(participantID: participant)
        }
    }
}

struct PrivateMotionBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
