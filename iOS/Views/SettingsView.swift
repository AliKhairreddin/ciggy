#if os(iOS)
import CiggyShared
import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@StateObject private var viewModel = SettingsViewModel()
	@State private var isSaving = false
	@State private var didSave = false

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					header
					detectionCard
					notificationCard
					#if DEBUG
					detectionPreviewCard
					#endif
					privacyCard
					saveButton
					versionFooter
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				.padding(.bottom, 28)
			}
		}
		.toolbar(.hidden, for: .navigationBar)
		.onAppear { viewModel.bind(settings: settings) }
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text("Tune Ciggy")
				.font(.system(size: 34, weight: .black, design: .rounded))
				.foregroundStyle(.white)
			Text("Choose how the app listens and when it speaks up.")
				.font(.subheadline)
				.foregroundStyle(CiggyTheme.secondaryText)
		}
	}

	private var detectionCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 16) {
				HStack(spacing: 12) {
					Image(systemName: "hand.raised.fingers.spread.fill")
						.foregroundStyle(CiggyTheme.deepInk)
						.frame(width: 42, height: 42)
						.background(CiggyTheme.brandGradient, in: Circle())
					VStack(alignment: .leading, spacing: 2) {
						Text("Motion detection")
							.font(.headline)
							.foregroundStyle(.white)
						Text("Repeated hand-to-mouth movement")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer()
					Text(sensitivityName)
						.font(.caption.weight(.bold))
						.foregroundStyle(CiggyTheme.mint)
				}

				Slider(value: $viewModel.sensitivity, in: 0...1, step: 0.01)
					.tint(CiggyTheme.mint)
					.accessibilityLabel("Motion detection sensitivity")

				HStack {
					Text("Fewer false detections")
					Spacer()
					Text("Earlier detections")
				}
				.font(.caption2)
				.foregroundStyle(CiggyTheme.secondaryText)

				Text(sensitivityDescription)
					.font(.caption)
					.foregroundStyle(CiggyTheme.secondaryText)
					.padding(.top, 2)
			}
		}
	}

	private var notificationCard: some View {
		CiggyPanel {
			Toggle(isOn: $viewModel.notificationsEnabled) {
				HStack(spacing: 12) {
					Image(systemName: "bell.badge.fill")
						.foregroundStyle(CiggyTheme.sunlight)
					VStack(alignment: .leading, spacing: 2) {
						Text("Detection summaries")
							.font(.headline)
							.foregroundStyle(.white)
						Text("Notify me after Watch history is checked")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
				}
			}
			.tint(CiggyTheme.mint)
		}
	}

	#if DEBUG
	private var detectionPreviewCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				Label("Try the history experience", systemImage: "sparkles")
					.font(.headline)
					.foregroundStyle(.white)
				Text("Adds a clearly labeled debug preview of 6 detections across the last 8 hours and syncs it to the paired Watch.")
					.font(.caption)
					.foregroundStyle(CiggyTheme.secondaryText)
				Button("Preview 6 detected in 8 hours") {
					DetectionReviewWorkflow.createHistoricalPreview(
						repository: repository,
						store: reviewStore
					)
				}
				.font(.subheadline.weight(.bold))
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 12)
				.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				.buttonStyle(.plain)
			}
		}
	}
	#endif

	private var privacyCard: some View {
		NavigationLink(destination: PrivacyInfoView()) {
			HStack(spacing: 14) {
				Image(systemName: "lock.shield.fill")
					.foregroundStyle(CiggyTheme.lavender)
				VStack(alignment: .leading, spacing: 2) {
					Text("Your data")
						.font(.headline)
						.foregroundStyle(.white)
					Text("See what is stored and shared")
						.font(.caption)
						.foregroundStyle(CiggyTheme.secondaryText)
				}
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption.weight(.bold))
					.foregroundStyle(CiggyTheme.secondaryText)
			}
			.padding()
			.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.stroke(CiggyTheme.border, lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
	}

	private var saveButton: some View {
		Button {
			guard isSaving == false else { return }
			isSaving = true
			Task {
				await viewModel.save(settings: settings)
				isSaving = false
				withAnimation(.spring(response: 0.3)) { didSave = true }
				try? await Task.sleep(nanoseconds: 2_000_000_000)
				withAnimation { didSave = false }
			}
		} label: {
			Label(
				didSave ? "Settings saved" : (isSaving ? "Saving…" : "Save settings"),
				systemImage: didSave ? "checkmark" : "slider.horizontal.3"
			)
			.font(.headline)
			.foregroundStyle(CiggyTheme.deepInk)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 16)
			.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
	}

	private var versionFooter: some View {
		HStack(spacing: 8) {
			CiggyBrandMark(size: 24)
			Text("ciggy · built for awareness, never judgment")
		}
		.font(.caption2)
		.foregroundStyle(CiggyTheme.secondaryText)
		.frame(maxWidth: .infinity)
	}

	private var sensitivityName: String {
		switch viewModel.sensitivity {
		case ..<0.34: return "Conservative"
		case 0.67...: return "Responsive"
		default: return "Balanced"
		}
	}

	private var sensitivityDescription: String {
		switch viewModel.sensitivity {
		case ..<0.34:
			return "Waits for about seven matching movements before recording a detection."
		case 0.67...:
			return "Can detect after about four matching movements; more false detections are possible."
		default:
			return "Looks for about five matching movements within one short session."
		}
	}
}

private struct PrivacyInfoView: View {
	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(spacing: 14) {
					privacyRow(
						icon: "iphone.gen3",
						title: "Stored on your devices",
						body: "Smoking events, optional notes, settings, and detection reviews stay locally on your iPhone and Apple Watch."
					)
					privacyRow(
						icon: "applewatch.radiowaves.left.and.right",
						title: "Watch sync",
						body: "Automatic events, count corrections, review feedback, and settings move between your paired devices with WatchConnectivity."
					)
					privacyRow(
						icon: "waveform.path.ecg",
						title: "Health context",
						body: "If you grant access, Ciggy can attach heart-rate context. Motion detection still works without it. Ciggy never writes HealthKit data."
					)
					privacyRow(
						icon: "cloud.slash.fill",
						title: "No cloud upload",
						body: "This prototype does not upload events, notes, settings, or detection reviews to a cloud service."
					)
				}
				.padding(18)
			}
		}
		.navigationTitle("Your data")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(CiggyTheme.ink, for: .navigationBar)
		.toolbarBackground(.visible, for: .navigationBar)
		.toolbarColorScheme(.dark, for: .navigationBar)
	}

	private func privacyRow(icon: String, title: String, body: String) -> some View {
		CiggyPanel {
			HStack(alignment: .top, spacing: 14) {
				Image(systemName: icon)
					.font(.title3)
					.foregroundStyle(CiggyTheme.mint)
					.frame(width: 28)
				VStack(alignment: .leading, spacing: 5) {
					Text(title)
						.font(.headline)
						.foregroundStyle(.white)
					Text(body)
						.font(.subheadline)
						.foregroundStyle(CiggyTheme.secondaryText)
				}
				Spacer(minLength: 0)
			}
		}
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack { SettingsView().environmentObject(UserSettingsStore()) }
			.environmentObject(EventRepository())
			.environmentObject(DetectionReviewStore())
	}
}
#endif
