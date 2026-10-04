#if os(iOS)
import ActivityKit
import CiggyShared
import Combine
import Foundation

/// Starts only after a user action; log/goal changes update an existing activity.
@MainActor
final class LiveActivityManager: ObservableObject {
	@Published private(set) var isActive = false
	@Published private(set) var isBusy = false
	@Published private(set) var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
	@Published private(set) var errorMessage: String?

	private var cancellables = Set<AnyCancellable>()
	private var repository: EventRepository?
	private var settings: UserSettingsStore?
	private var operation: Task<Void, Never>?
	private var stateObservers: [String: Task<Void, Never>] = [:]
	private var authorizationObserver: Task<Void, Never>?

	func bind(repository: EventRepository, settings: UserSettingsStore) {
		guard self.repository == nil else { return }
		self.repository = repository
		self.settings = settings
		repository.$events.combineLatest(settings.$settings)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] events, settings in
				self?.enqueueUpdate(LiveActivitySnapshot(events: events, dailyLimit: settings.dailyLimit))
			}
			.store(in: &cancellables)
		Timer.publish(every: 60, on: .main, in: .common).autoconnect()
			.sink { [weak self] _ in self?.refresh() }
			.store(in: &cancellables)
		authorizationObserver = Task { [weak self] in
			for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
				guard let self else { return }
				self.activitiesEnabled = enabled
				self.refresh()
			}
		}
		refresh()
	}

	func refresh() {
		activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
		refreshActivityState()
		guard let repository, let settings else { return }
		enqueueUpdate(LiveActivitySnapshot(events: repository.events, dailyLimit: settings.settings.dailyLimit))
	}

	func start() async {
		guard !isBusy, let repository, let settings else { return }
		isBusy = true
		defer { isBusy = false }
		await operation?.value
		refreshActivityState()
		guard !isActive else { return }
		errorMessage = nil
		activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
		guard activitiesEnabled else {
			errorMessage = "Allow Live Activities in iPhone Settings → Ciggy to start a session."
			return
		}
		let now = Date()
		let snapshot = LiveActivitySnapshot(events: repository.events, dailyLimit: settings.settings.dailyLimit, now: now)
		let attributes = CiggyActivityAttributes(startedAt: now, expiresAt: LiveActivitySnapshot.expiration(startingAt: now))
		do {
			_ = try Activity.request(
				attributes: attributes,
				content: ActivityContent(state: snapshot, staleDate: attributes.expiresAt),
				pushType: nil
			)
			refreshActivityState()
		} catch {
			errorMessage = "Couldn't start the Live Activity. \(error.localizedDescription)"
		}
	}

	func stop() async {
		guard !isBusy else { return }
		isBusy = true
		defer { isBusy = false }
		await operation?.value
		for activity in Activity<CiggyActivityAttributes>.activities {
			await activity.end(nil, dismissalPolicy: .immediate)
		}
		errorMessage = nil
		refreshActivityState()
	}

	private func enqueueUpdate(_ snapshot: LiveActivitySnapshot) {
		// Serialize updates so a delayed Watch delivery cannot overwrite a later undo or correction.
		let previous = operation
		operation = Task { [weak self] in
			await previous?.value
			for activity in Activity<CiggyActivityAttributes>.activities {
				if activity.attributes.expiresAt <= Date() || activity.activityState == .ended {
					await activity.end(nil, dismissalPolicy: .immediate)
				} else if activity.content.state != snapshot {
					await activity.update(ActivityContent(state: snapshot, staleDate: activity.attributes.expiresAt))
				}
			}
			self?.refreshActivityState()
		}
	}

	private func refreshActivityState() {
		let activities = Activity<CiggyActivityAttributes>.activities
		isActive = activities.contains {
			($0.activityState == .active || $0.activityState == .stale) && $0.attributes.expiresAt > Date()
		}
		for activity in activities where stateObservers[activity.id] == nil {
			stateObservers[activity.id] = Task { [weak self] in
				for await _ in activity.activityStateUpdates {
					self?.refreshActivityState()
				}
			}
		}
		let existingIDs = Set(activities.map(\.id))
		for id in Array(stateObservers.keys) where !existingIDs.contains(id) {
			stateObservers.removeValue(forKey: id)?.cancel()
		}
	}
}
#endif
