#if os(iOS)
import AVFoundation
import CiggyShared
import SwiftUI

/// Synthetic fold previews and ordinary phones never unlock the lounge.
struct CiggyDuoDeskGate<Desk: View, Normal: View>: View {
	@Environment(\.ciggyDisplay) private var display
	private let desk: Desk
	private let normal: Normal
	init(@ViewBuilder desk: () -> Desk, @ViewBuilder normal: () -> Normal) {
		self.desk = desk(); self.normal = normal()
	}
	var body: some View {
		if display.isDuoDeskMode { desk } else { normal }
	}
}

struct CiggyDuoAshtrayScene: View {
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.ciggyDisplay) private var display
	@AppStorage("duoLoungeLastScenery") private var lastScenery = ""
	@State private var scenery = CiggyLoungeScenery.mountains
	@State private var hasChosenScenery = false
	@State private var smokePaused = false
	@State private var isVisible = false

	var body: some View {
		let animated = !reduceMotion && !smokePaused && isVisible && scenePhase == .active
		Button { smokePaused.toggle() } label: {
			TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { timeline in
				Canvas { context, size in
					context.scaleBy(x: size.width / 480, y: size.height / 320)
					CiggyLoungeBackdrop.draw(scenery, in: context)
					context.translateBy(x: 0, y: 75)
					drawAshtray(in: context, time: animated ? timeline.date.timeIntervalSinceReferenceDate : 2)
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Desk mode, \(display.hinge?.degrees ?? 0)°, ashtray. \(smokePaused || reduceMotion ? "Smoke paused" : "Drifting smoke")")
		.accessibilityValue(scenery.title)
		.accessibilityHint("Double tap to pause or resume the smoke")
		.accessibilityIdentifier("duo-lounge-scene")
		.onAppear {
			if !hasChosenScenery {
				scenery = CiggyLoungeScenery.allCases.filter { $0.rawValue != lastScenery }.randomElement() ?? .mountains
				lastScenery = scenery.rawValue
				hasChosenScenery = true
			}
			isVisible = true
		}
		.onDisappear { isVisible = false }
	}

	private func drawAshtray(in context: GraphicsContext, time: Double) {
		var shadow = context
		shadow.addFilter(.blur(radius: 9))
		shadow.fill(Path(ellipseIn: CGRect(x: 92, y: 210, width: 300, height: 25)), with: .color(CiggyTheme.ink.opacity(0.22)))
		var bowl = Path()
		bowl.move(to: CGPoint(x: 65, y: 165))
		bowl.addCurve(to: CGPoint(x: 415, y: 165), control1: CGPoint(x: 65, y: 250), control2: CGPoint(x: 415, y: 250))
		bowl.closeSubpath()
		context.fill(bowl, with: .linearGradient(Gradient(colors: [CiggyTheme.mint, CiggyTheme.ink]),
			startPoint: CGPoint(x: 240, y: 150), endPoint: CGPoint(x: 240, y: 260)))
		context.stroke(bowl, with: .color(CiggyTheme.ink), lineWidth: 2)
		let rim = Path(ellipseIn: CGRect(x: 65, y: 115, width: 350, height: 100))
		context.fill(rim, with: .linearGradient(Gradient(colors: [CiggyTheme.softMint, CiggyTheme.mint]),
			startPoint: CGPoint(x: 170, y: 100), endPoint: CGPoint(x: 280, y: 220)))
		context.stroke(rim, with: .color(CiggyTheme.ink), lineWidth: 2)
		let hollow = Path(ellipseIn: CGRect(x: 98, y: 131, width: 284, height: 65))
		context.fill(hollow, with: .linearGradient(Gradient(colors: [CiggyTheme.ink.opacity(0.80), CiggyTheme.mint]),
			startPoint: CGPoint(x: 240, y: 125), endPoint: CGPoint(x: 240, y: 200)))
		context.stroke(hollow, with: .color(CiggyTheme.paper.opacity(0.6)), lineWidth: 2)
		for fleck in 0..<36 {
			let x = 240 + sin(Double(fleck) * 7.2) * Double(35 + fleck % 5 * 12)
			let y = 165 + cos(Double(fleck) * 3.7) * 18
			context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: Double(2 + fleck % 3), height: 2)),
				with: .color(fleck.isMultiple(of: 3) ? CiggyTheme.paper.opacity(0.7) : CiggyTheme.ink.opacity(0.65)))
		}
		cigarette(in: context, origin: CGPoint(x: 116, y: 164), angle: -0.48, length: 145, lit: true)
		cigarette(in: context, origin: CGPoint(x: 282, y: 174), angle: 0.45, length: 68, lit: false)
		var smoke = context
		smoke.addFilter(.blur(radius: 1.5))
		for wisp in 0..<9 {
			let progress = (time * 0.12 + Double(wisp) / 9).truncatingRemainder(dividingBy: 1)
			let x = 245 + sin(progress * 7 + Double(wisp)) * progress * 28
			let y = 100 - progress * 140
			var path = Path()
			path.move(to: CGPoint(x: x, y: y))
			path.addCurve(to: CGPoint(x: x + sin(progress * 9) * 24, y: y - 34),
				control1: CGPoint(x: x - 22, y: y - 12), control2: CGPoint(x: x + 24, y: y - 22))
			smoke.stroke(path, with: .color((scenery == .aurora || scenery == .lake || scenery == .city ? Color.white : CiggyTheme.ink).opacity((1 - progress) * 0.35)),
				style: StrokeStyle(lineWidth: 2 + progress * 5, lineCap: .round))
		}
	}

	private func cigarette(in context: GraphicsContext, origin: CGPoint, angle: Double, length: CGFloat, lit: Bool) {
		var drawing = context
		drawing.translateBy(x: origin.x, y: origin.y)
		drawing.rotate(by: .radians(angle))
		let body = Path(roundedRect: CGRect(x: 0, y: 0, width: length, height: 13), cornerRadius: 3)
		drawing.fill(body, with: .color(CiggyTheme.paper))
		drawing.stroke(body, with: .color(CiggyTheme.ink.opacity(0.8)), lineWidth: 1.2)
		drawing.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 28, height: 13), cornerRadius: 3), with: .color(CiggyTheme.peach))
		for stripe in 0..<4 {
			drawing.fill(Path(CGRect(x: CGFloat(5 + stripe * 6), y: 3, width: 1, height: 7)), with: .color(CiggyTheme.ember.opacity(0.4)))
		}
		drawing.fill(Path(roundedRect: CGRect(x: length - 10, y: 0, width: 10, height: 13), cornerRadius: 2),
			with: .color(lit ? CiggyTheme.ember : CiggyTheme.ink.opacity(0.65)))
		if lit {
			drawing.fill(Path(ellipseIn: CGRect(x: length - 6, y: 2, width: 5, height: 8)), with: .color(CiggyTheme.sunlight))
		}
	}
}

struct CiggyDuoMusicPlayer: View {
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@StateObject private var audio = CiggyDeskAudioPlayer()
	private let palette = CiggyPalette(colorScheme: .dark)

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				LinearGradient(colors: [Color(red: 0.14, green: 0.12, blue: 0.19), CiggyTheme.ink, Color(red: 0.07, green: 0.10, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
				Circle().fill(CiggyTheme.peach.opacity(0.10)).frame(width: 330, height: 330).blur(radius: 70).offset(x: -180, y: -100)
				ScrollView {
					VStack(spacing: 22) {
						HStack {
							Label("CIGGY FM", systemImage: "hifispeaker.fill").font(.caption.weight(.heavy)).tracking(2)
							Spacer()
							Text(audio.isPlaying ? "ON AIR" : "ORIGINAL AMBIENT LOOPS").font(.system(size: 9, weight: .heavy)).tracking(1.5)
						}.foregroundStyle(CiggyTheme.softMint)
						Spacer(minLength: 0)
						if proxy.size.width > 500 {
							HStack(spacing: 30) {
								record.frame(width: min(190, proxy.size.height * 0.47), height: min(190, proxy.size.height * 0.47))
								VStack(spacing: 18) { metadata; transport; playback }.frame(maxWidth: .infinity)
							}
						} else {
							record.frame(width: 110, height: 110)
							metadata
							transport
							playback
						}
						Spacer(minLength: 0)
						HStack(spacing: 14) {
							Image(systemName: "speaker.fill")
							Slider(value: $audio.volume, in: 0...1).tint(CiggyTheme.softMint).accessibilityLabel("Ambient music volume")
							Image(systemName: "speaker.wave.2.fill")
						}.font(.caption).foregroundStyle(palette.secondaryText)
						if let error = audio.error { Text(error).font(.caption).foregroundStyle(CiggyTheme.peach) }
					}
					.padding(32)
					.frame(minHeight: proxy.size.height)
				}
				.scrollIndicators(.hidden)
			}
			.foregroundStyle(CiggyTheme.paper)
		}
		.environment(\.colorScheme, .dark)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("duo-music-player")
		.onDisappear { audio.pause() }
		.onChange(of: scenePhase) { _, phase in if phase != .active { audio.pause() } }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in audio.pause() }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in audio.pause() }
		.onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in audio.pause() }
		.onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
			if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
			   AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable { audio.pause() }
		}
	}

	private var metadata: some View {
		VStack(spacing: 6) {
			Text(audio.track.title).font(.system(.title, design: .rounded, weight: .black)).accessibilityIdentifier("duo-music-track")
			Text(audio.track.subtitle).font(.caption).foregroundStyle(palette.secondaryText)
		}.frame(maxWidth: .infinity)
	}

	private var record: some View {
		TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !audio.isPlaying || reduceMotion)) { timeline in
			ZStack {
				Circle().fill(Color.black.opacity(0.65))
				ForEach(0..<8) { groove in
					Circle().stroke(CiggyTheme.paper.opacity(groove.isMultiple(of: 2) ? 0.10 : 0.04), lineWidth: 1).padding(CGFloat(8 + groove * 7))
				}
				Circle().fill(CiggyTheme.brandGradient).padding(58)
				Circle().fill(CiggyTheme.ink).frame(width: 9, height: 9)
			}
			.rotationEffect(.degrees(audio.isPlaying && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) * 18 : 0))
		}
		.shadow(color: CiggyTheme.peach.opacity(0.10), radius: 25)
		.accessibilityHidden(true)
	}

	private var transport: some View {
		HStack(spacing: 22) {
			Button { audio.select(offset: -1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Previous ambient track")
			Button { audio.toggle() } label: {
				Group {
					if audio.isLoading { ProgressView().tint(CiggyTheme.ink) }
					else { Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.title2) }
				}
				.frame(width: 62, height: 62).background(CiggyTheme.peach, in: Circle()).foregroundStyle(CiggyTheme.ink)
			}
			.accessibilityLabel(audio.isPlaying || audio.isLoading ? "Pause ambient music" : "Play ambient music")
			.accessibilityIdentifier("duo-music-play")
			Button { audio.select(offset: 1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Next ambient track")
		}.buttonStyle(.plain).frame(maxWidth: .infinity)
	}

	private var playback: some View {
		TimelineView(.periodic(from: .now, by: 1)) { timeline in
			VStack(spacing: 7) {
				ProgressView(value: audio.currentTime, total: CiggyAmbientLoop.duration).tint(CiggyTheme.softMint)
					.accessibilityLabel("Ambient loop playback").accessibilityValue("\(Int(audio.currentTime)) of 24 seconds")
					.accessibilityIdentifier("duo-music-progress")
				HStack {
					Text(String(format: "0:%02d", Int(audio.currentTime))).monospacedDigit()
					Spacer()
					Image(systemName: "repeat")
					Text("0:24").monospacedDigit()
				}.font(.caption2).foregroundStyle(palette.secondaryText).accessibilityHidden(true)
			}
			// AVAudioPlayer's clock is not observable; invalidate this small view
			// on the periodic timeline even when no player setting has changed.
			.id(timeline.date)
		}
	}
}
#endif
