#if os(iOS)
import CiggyShared
import SwiftUI

struct GoalsView: View {
	var showsNavigationBar = false
	@EnvironmentObject private var settings: UserSettingsStore
	@StateObject private var viewModel = GoalsViewModel()
	@State private var didSave = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			CiggyBackdrop()
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					header
					CiggyStoryCard("Less pressure. More you.", subtitle: "A realistic limit is a good place to start.", color: CiggyTheme.peach)
					limitCard
					quitDateCard
					saveButton
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				.padding(.bottom, 28)
			}
		}
		.navigationTitle("Goals")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
		.onAppear { viewModel.bind(settings: settings) }
		.sensoryFeedback(.success, trigger: didSave)
	}

	private var header: some View {
		CiggyScreenHeader("The little plan", title: "Your pace. Your rules.", subtitle: "Small steps still move you forward.")
	}

	private var limitCard: some View {
		CiggyPanel {
			VStack(spacing: 20) {
				HStack {
					VStack(alignment: .leading, spacing: 3) {
						Text("Daily limit")
							.font(.headline)
							.foregroundStyle(CiggyTheme.primaryText)
						Text("Your target for each day")
							.font(.caption)
							.foregroundStyle(CiggyTheme.secondaryText)
					}
					Spacer()
					Image(systemName: "target")
						.font(.title2)
						.foregroundStyle(CiggyTheme.mint)
				}

				CiggyPackMeter(count: 0, limit: viewModel.dailyLimit)

				HStack(spacing: 24) {
					Button { viewModel.dailyLimit = max(1, viewModel.dailyLimit - 1) } label: {
						Image(systemName: "minus")
							.font(.headline)
							.frame(width: 48, height: 48)
							.ciggyGlass(in: Circle(), interactive: true)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Decrease daily limit")

					VStack(spacing: 0) {
						Text("\(viewModel.dailyLimit)")
							.font(.system(size: 58, weight: .black, design: .rounded))
							.contentTransition(.numericText())
							.accessibilityIdentifier("daily-limit-value")
							.foregroundStyle(CiggyTheme.primaryText)
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
							.ciggyGlass(in: Circle(), interactive: true)
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
								.foregroundStyle(CiggyTheme.primaryText)
							Text("Give the journey a destination")
								.font(.caption)
								.foregroundStyle(CiggyTheme.secondaryText)
						}
					}
				}
				.tint(CiggyTheme.ember)

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
					.foregroundStyle(CiggyTheme.primaryText)
					.tint(CiggyTheme.ember)
				}
			}
		}
	}

	private var saveButton: some View {
		Button {
			viewModel.save(settings: settings)
			withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { didSave = true }
			Task {
				try? await Task.sleep(nanoseconds: 2_000_000_000)
				await MainActor.run { withAnimation(reduceMotion ? nil : .default) { didSave = false } }
			}
		} label: {
			Label(didSave ? "Goals saved" : "Save my goals", systemImage: didSave ? "checkmark" : "arrow.right")
				.font(.headline)
				.foregroundStyle(CiggyTheme.deepInk)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
				.ciggyGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
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
