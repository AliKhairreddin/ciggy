#if os(iOS)
import CiggyShared
import SwiftUI

struct GoalsView: View {
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = GoalsViewModel()
	@State private var didSave = false

	var body: some View {
		ZStack {
			CiggyTheme.appBackground.ignoresSafeArea()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					header
					limitCard
					quitDateCard
					saveButton
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
			Text("Make it yours")
				.font(.system(size: 34, weight: .black, design: .rounded))
				.foregroundStyle(.white)
			Text("Small limits are useful when they feel realistic.")
				.font(.subheadline)
				.foregroundStyle(CiggyTheme.secondaryText)
		}
	}

	private var limitCard: some View {
		CiggyPanel {
			VStack(spacing: 20) {
				HStack {
					VStack(alignment: .leading, spacing: 3) {
						Text("Daily limit")
							.font(.headline)
							.foregroundStyle(.white)
						Text("Your target for each day")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer()
					Image(systemName: "target")
						.font(.title2)
						.foregroundStyle(CiggyTheme.mint)
				}

				HStack(spacing: 24) {
					Button { viewModel.dailyLimit = max(1, viewModel.dailyLimit - 1) } label: {
						Image(systemName: "minus")
							.font(.headline)
							.frame(width: 48, height: 48)
							.background(CiggyTheme.elevatedSurface, in: Circle())
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Decrease daily limit")

					VStack(spacing: 0) {
						Text("\(viewModel.dailyLimit)")
							.font(.system(size: 58, weight: .black, design: .rounded))
							.foregroundStyle(.white)
						Text("cigarettes")
							.font(.caption.weight(.semibold))
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					.frame(minWidth: 116)

					Button { viewModel.dailyLimit = min(100, viewModel.dailyLimit + 1) } label: {
						Image(systemName: "plus")
							.font(.headline)
							.foregroundStyle(CiggyTheme.deepInk)
							.frame(width: 48, height: 48)
							.background(CiggyTheme.brandGradient, in: Circle())
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Increase daily limit")
				}
			}
		}
	}

	private var quitDateCard: some View {
		CiggyPanel {
			VStack(alignment: .leading, spacing: 16) {
				Toggle(isOn: $viewModel.hasQuitDate) {
					HStack(spacing: 12) {
						Image(systemName: "flag.checkered")
							.foregroundStyle(CiggyTheme.sunlight)
						VStack(alignment: .leading, spacing: 2) {
							Text("Set a quit date")
								.font(.headline)
								.foregroundStyle(.white)
							Text("Give the journey a destination")
								.font(.caption)
								.foregroundStyle(CiggyTheme.secondaryText)
						}
					}
				}
				.tint(CiggyTheme.mint)

				if viewModel.hasQuitDate {
					Divider().overlay(CiggyTheme.border)
					DatePicker(
						"Target date",
						selection: Binding(
							get: { viewModel.quitDate ?? Date() },
							set: { viewModel.quitDate = $0 }
						),
						displayedComponents: .date
					)
					.foregroundStyle(.white)
					.tint(CiggyTheme.mint)
				}
			}
		}
	}

	private var saveButton: some View {
		Button {
			viewModel.save(settings: settings)
			withAnimation(.spring(response: 0.3)) { didSave = true }
			Task {
				try? await Task.sleep(nanoseconds: 2_000_000_000)
				await MainActor.run { withAnimation { didSave = false } }
			}
		} label: {
			Label(didSave ? "Goals saved" : "Save my goals", systemImage: didSave ? "checkmark" : "arrow.right")
				.font(.headline)
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
				.background(CiggyTheme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
	}
}

struct GoalsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack { GoalsView().environmentObject(UserSettingsStore()) }
	}
}
#endif
