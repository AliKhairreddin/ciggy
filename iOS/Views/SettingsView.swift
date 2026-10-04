#if os(iOS)
import CiggyShared
import SwiftUI

struct SettingsView: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	var showsNavigationBar = false
	@EnvironmentObject private var repository: EventRepository
	@EnvironmentObject private var settings: UserSettingsStore
	@EnvironmentObject private var reviewStore: DetectionReviewStore
	@StateObject private var viewModel = SettingsViewModel()
	@State private var isSaving = false
	@State private var didSave = false
	@State private var roastPreviewIndex = Int.random(in: 0..<DailyRoastCopy.previews.count)
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		CiggyAdaptiveScreen {
			header
			appearanceCard
			story
			settingsControls
			privacyCard
			saveButton
			versionFooter
		} overview: { _ in
			header
			story
			CiggyPanel {
				VStack(alignment: .leading, spacing: 12) {
					Label(sensitivityName, systemImage: "hand.raised.fingers.spread.fill")
						.font(.title2.weight(.bold))
					Text(sensitivityDescription).font(.subheadline)
					Label(viewModel.notificationsEnabled ? "Summaries enabled" : "Quiet summaries",
						  systemImage: viewModel.notificationsEnabled ? "bell" : "bell.slash")
						.font(.subheadline.weight(.semibold))
				}.foregroundStyle(palette.primaryText)
			}
			privacyCard
		} controls: { _ in
			appearanceCard
			settingsControls
			saveButton
			versionFooter
		}
		.navigationTitle("Settings")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
		.onAppear { viewModel.bind(settings: settings) }
		.sensoryFeedback(.success, trigger: didSave)
	}

	private var appearanceCard: some View { CiggyPanel { CiggyAppearanceSettings() } }

	private var story: some View {
		CiggyStoryCard("A sidekick, on your terms.", subtitle: "You choose how Ciggy pays attention.", color: CiggyTheme.softMint)
	}

	@ViewBuilder
	private var settingsControls: some View {
		detectionCard
		notificationCard
		#if DEBUG
		detectionPreviewCard
		#endif
	}

	private var header: some View {
		CiggyScreenHeader("The control room", title: "A little fine-tuning.", subtitle: "Make yourself at home.")
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
							.foregroundStyle(palette.primaryText)
						Text("Repeated hand-to-mouth movement")
							.font(.caption)
							.foregroundStyle(palette.secondaryText)
					}
					Spacer()
					Text(sensitivityName)
						.font(.caption.weight(.bold))
						.foregroundStyle(palette.mint)
				}

				Slider(value: $viewModel.sensitivity, in: 0...1, step: 0.01)
					.tint(CiggyTheme.ember)
					.accessibilityLabel("Motion detection sensitivity")

				HStack {
					Text("Fewer false detections")
					Spacer()
					Text("Earlier detections")
				}
				.font(.caption2)
				.foregroundStyle(palette.secondaryText)

				Text(sensitivityDescription)
					.font(.caption)
					.foregroundStyle(palette.secondaryText)
					.padding(.top, 2)
			}
		}
	}

	private var notificationCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 14) {
				Toggle(isOn: $viewModel.notificationsEnabled) {
					HStack(spacing: 12) {
						Image(systemName: "bell.badge.fill")
							.foregroundStyle(CiggyTheme.sunlight)
						VStack(alignment: .leading, spacing: 2) {
							Text("Daily roasts & summaries")
								.font(.headline)
								.foregroundStyle(palette.primaryText)
							Text("Sarcastic milestones. Honest counts.")
								.font(.caption)
								.foregroundStyle(palette.secondaryText)
						}
					}
				}
				.tint(CiggyTheme.ember)
				.accessibilityIdentifier("notifications-toggle")

				Text("\"10 cigarettes today. Your lungs would like to unsubscribe.\"")
					.font(.subheadline)
					.foregroundStyle(palette.primaryText)
				Text("110 rotating messages for daily milestones, reaching or exceeding your limit, cutting down, and smoke-free days. Watch logs count once they sync to iPhone. Includes Watch history summaries.")
					.font(.caption)
					.foregroundStyle(palette.secondaryText)
				Button("Preview a roast") {
					let previews = DailyRoastCopy.previews
					NotificationManager.scheduleDailyRoast(previews[roastPreviewIndex], preview: true)
					roastPreviewIndex = (roastPreviewIndex + 1) % previews.count
				}
				.font(.subheadline.weight(.bold))
				.disabled(settings.settings.notificationsEnabled == false || viewModel.notificationsEnabled == false)
				.accessibilityIdentifier("preview-daily-roast")
				if settings.settings.notificationsEnabled == false {
					Text("Enable and save notifications to try a preview.")
						.font(.caption2)
						.foregroundStyle(palette.secondaryText)
				}
			}
		}
	}

	#if DEBUG
	private var detectionPreviewCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 12) {
				Label("Try the history experience", systemImage: "sparkles")
					.font(.headline)
					.foregroundStyle(palette.primaryText)
				Text("Adds a clearly labeled debug preview of 6 detections across the last 8 hours and syncs it to the paired Watch.")
					.font(.caption)
					.foregroundStyle(palette.secondaryText)
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
						.foregroundStyle(palette.primaryText)
					Text("See what is stored and shared")
						.font(.caption)
						.foregroundStyle(palette.secondaryText)
				}
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption.weight(.bold))
					.foregroundStyle(palette.secondaryText)
			}
			.padding()
			.background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.stroke(palette.border, lineWidth: 1)
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
				withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { didSave = true }
				try? await Task.sleep(nanoseconds: 2_000_000_000)
				withAnimation(reduceMotion ? nil : .default) { didSave = false }
			}
		} label: {
			Label(
				didSave ? "Settings saved" : (isSaving ? "Saving…" : "Save settings"),
				systemImage: didSave ? "checkmark" : "slider.horizontal.3"
			)
			.font(.headline)
			.foregroundStyle(palette.primaryText)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 16)
			.ciggyGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
		}
		.buttonStyle(.plain)
	}

	private var versionFooter: some View {
		HStack(spacing: 8) {
			CiggyBrandMark(size: 24)
			Text("ciggy · built for awareness, never judgment")
		}
		.font(.caption2)
		.foregroundStyle(palette.secondaryText)
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
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	var body: some View {
		ZStack {
			CiggyBackdrop()
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
	}

	private func privacyRow(icon: String, title: String, body: String) -> some View {
		CiggyPanel {
			HStack(alignment: .top, spacing: 14) {
				Image(systemName: icon)
					.font(.title3)
					.foregroundStyle(palette.mint)
					.frame(width: 28)
				VStack(alignment: .leading, spacing: 5) {
					Text(title)
						.font(.headline)
						.foregroundStyle(palette.primaryText)
					Text(body)
						.font(.subheadline)
						.foregroundStyle(palette.secondaryText)
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
