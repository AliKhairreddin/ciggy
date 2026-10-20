import SwiftUI

/// The same Siggy artwork used by both app icons and every in-app mascot placement.
public struct CiggyMascot: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	private let animated: Bool
	@State private var isVisible = false
	public init(animated: Bool = true) { self.animated = animated }

	public var body: some View {
		let shouldAnimate = animated && !reduceMotion && isVisible && scenePhase == .active
		TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !shouldAnimate)) { timeline in
			let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0
			GeometryReader { geometry in
				Image(decorative: "Siggy", bundle: .module)
					.resizable()
					.interpolation(.high)
					.scaledToFit()
					// A quiet rim keeps the dark limbs readable on dark cards.
					.shadow(color: colorScheme == .dark ? CiggyTheme.paper.opacity(0.45) : .clear, radius: 1)
					.rotationEffect(.degrees(sin(time * 1.2) * 2), anchor: .bottom)
					.offset(y: sin(time * 1.8) * geometry.size.height * 0.012)
			}
		}
		.aspectRatio(1, contentMode: .fit)
		.onAppear { isVisible = true }
		.onDisappear { isVisible = false }
		.accessibilityHidden(true)
	}
}

public struct CiggyBackdrop: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	public init() {}
	public var body: some View {
		#if os(watchOS)
		ZStack(alignment: .top) {
			palette.appBackground
			LinearGradient(
				colors: colorScheme == .dark
					? [Color(red: 0.36, green: 0.20, blue: 0.20), CiggyTheme.ink, CiggyTheme.ink.opacity(0)]
					: [Color(red: 0.58, green: 0.27, blue: 0.16), CiggyTheme.peach, CiggyTheme.paper.opacity(0)],
				startPoint: .top,
				endPoint: .bottom
			)
			.frame(height: 140)
		}
		.ignoresSafeArea()
		.allowsHitTesting(false).accessibilityHidden(true)
		#else
		ZStack(alignment: .topTrailing) {
			palette.appBackground
			Canvas { context, size in
				var grid = Path()
				for x in stride(from: CGFloat(0), through: size.width, by: 28) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
				for y in stride(from: CGFloat(0), through: size.height, by: 28) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
				context.stroke(grid, with: .color(palette.primaryText.opacity(0.035)), lineWidth: 0.5)
			}
			CiggyPackWallpaper()
			Circle().fill(CiggyTheme.peach.opacity(0.20)).frame(width: 260, height: 260).blur(radius: 65).offset(x: 120, y: -80)
		}
		.ignoresSafeArea()
		.allowsHitTesting(false).accessibilityHidden(true)
		#endif
	}
}

public struct CiggyScreenHeader: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	private let eyebrow: String
	private let title: String
	private let subtitle: String
	public init(_ eyebrow: String, title: String, subtitle: String) {
		self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle
	}
	public var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Image(systemName: "sparkle")
				Text(eyebrow.uppercased()).tracking(2)
			}.font(.caption2.weight(.heavy)).foregroundStyle(CiggyTheme.ember)
			Text(title).font(.system(.largeTitle, design: .rounded, weight: .black)).tracking(-1.5).foregroundStyle(palette.primaryText)
			Text(subtitle).font(.subheadline).foregroundStyle(palette.secondaryText)
		}.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
	}
}

/// Honest daily-limit meter. Slots represent proportions when the limit exceeds twenty.
public struct CiggyPackMeter: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	private let count: Int
	private let limit: Int
	public init(count: Int, limit: Int) { self.count = count; self.limit = limit }
	public var body: some View {
		HStack(spacing: 5) {
			ForEach(0..<min(20, max(1, limit)), id: \.self) { index in
				let filled = Double(index) / Double(min(20, max(1, limit))) < Double(count) / Double(max(1, limit))
				VStack(spacing: 0) {
					RoundedRectangle(cornerRadius: 3).fill(filled ? palette.primaryText : CiggyTheme.paper).frame(height: 25)
					RoundedRectangle(cornerRadius: 2).fill(filled ? palette.primaryText.opacity(0.6) : CiggyTheme.ember.opacity(0.65)).frame(height: 9)
				}.frame(maxWidth: .infinity).opacity(filled ? 0.45 : 1)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(count) cigarettes logged, daily limit \(limit)")
	}
}

/// A little illustrated note for secondary screens, with the same character and ink treatment.
public struct CiggyStoryCard: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	private let title: String
	private let subtitle: String
	private let color: Color
	public init(_ title: String, subtitle: String, color: Color = CiggyTheme.lavender) {
		self.title = title; self.subtitle = subtitle; self.color = color
	}
	public var body: some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 7) {
				Text(title).font(.system(.title3, design: .rounded, weight: .black)).tracking(-0.5)
				Text(subtitle).font(.caption)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			CiggyMascot(animated: false).frame(width: 84, height: 84)
		}
		.foregroundStyle(palette.primaryText).padding(18)
		.background(color.opacity(colorScheme == .dark ? 0.22 : 0.55), in: RoundedRectangle(cornerRadius: 26))
		.overlay(RoundedRectangle(cornerRadius: 26).stroke(palette.border, lineWidth: 1))
	}
}
