#if os(iOS)
import AVFoundation
import CiggyShared
import Combine

@MainActor
final class CiggyDeskAudioPlayer: ObservableObject {
	@Published private(set) var track = CiggyAmbientLoop.Track.blueHour
	@Published private(set) var isPlaying = false
	@Published private(set) var isLoading = false
	@Published private(set) var error: String?
	@Published var volume: Float = 0.35 { didSet { player?.volume = volume } }
	private var player: AVAudioPlayer?
	private var preparation: Task<Void, Never>?
	private var cache: [CiggyAmbientLoop.Track: Data] = [:]
	var currentTime: TimeInterval { player?.currentTime ?? 0 }

	func toggle() {
		if isPlaying || isLoading { pause() } else { play() }
	}

	func select(offset: Int) {
		let tracks = CiggyAmbientLoop.Track.allCases
		let index = tracks.firstIndex(of: track) ?? 0
		let resume = isPlaying || isLoading
		pause()
		track = tracks[(index + offset + tracks.count) % tracks.count]
		player = nil
		error = nil
		if resume { play() }
	}

	func pause() {
		preparation?.cancel()
		preparation = nil
		player?.pause()
		isPlaying = false
		isLoading = false
		try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
	}

	private func play() {
		guard !isLoading else { return }
		error = nil
		isLoading = true
		let selected = track
		preparation = Task { [weak self] in
			guard let self else { return }
			do {
				if self.player == nil {
					let data: Data
					if let saved = self.cache[selected] { data = saved }
					else {
						data = await Task.detached(priority: .userInitiated) {
							CiggyAmbientLoop.waveData(for: selected)
						}.value
					}
					guard !Task.isCancelled else { return }
					self.cache[selected] = data
					self.player = try AVAudioPlayer(data: data)
					self.player?.numberOfLoops = -1
				}
				guard !Task.isCancelled else { return }
				// Respect silent mode and mix with any music already playing.
				try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
				try AVAudioSession.sharedInstance().setActive(true)
				self.player?.volume = self.volume
				self.isPlaying = self.player?.play() == true
				if !self.isPlaying { self.error = "Audio couldn't start. Try again." }
			} catch {
				guard !Task.isCancelled else { return }
				self.error = "Audio couldn't start. Try again."
				self.isPlaying = false
			}
			self.isLoading = false
		}
	}
}
#endif
