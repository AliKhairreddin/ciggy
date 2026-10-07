import SwiftUI

/// Original vector character: paper body, freckled filter, rubber-hose limbs, and quiet wisps.
public struct CiggyMascot: View {
	@Environment(\.colorScheme) private var colorScheme
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	private let animated: Bool
	@State private var isVisible = false
	public init(animated: Bool = true) { self.animated = animated }

	public var body: some View {
		TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated || reduceMotion || !isVisible || scenePhase != .active)) { timeline in
			let time = animated && !reduceMotion && isVisible && scenePhase == .active ? timeline.date.timeIntervalSinceReferenceDate : 0
			Canvas { context, size in
				let scale = min(size.width, size.height) / 200
				context.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 200 * scale) / 2)
				context.scaleBy(x: scale, y: scale)
				let bob = sin(time * 1.8) * 2.5
				let wave = sin(time * 1.4) * 4
				func line(_ points: [CGPoint], color: Color? = nil, width: CGFloat = 3) {
					var path = Path(); path.addLines(points)
					context.stroke(path, with: .color(color ?? palette.primaryText), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
				}
				func curve(_ start: CGPoint, _ end: CGPoint, _ c1: CGPoint, _ c2: CGPoint, color: Color? = nil, width: CGFloat = 3) {
					var path = Path(); path.move(to: start); path.addCurve(to: end, control1: c1, control2: c2)
					context.stroke(path, with: .color(color ?? palette.primaryText), style: StrokeStyle(lineWidth: width, lineCap: .round))
				}
				context.fill(Path(ellipseIn: CGRect(x: 47, y: 178, width: 111, height: 9)), with: .color(CiggyTheme.ink.opacity(0.10)))
				// A soft smoke ribbon moves independently of the character.
				curve(CGPoint(x: 128, y: 57), CGPoint(x: 139 + wave, y: 8), CGPoint(x: 163 + wave, y: 40), CGPoint(x: 105, y: 24), color: CiggyTheme.paper.opacity(0.9), width: 9)
				curve(CGPoint(x: 151, y: 55), CGPoint(x: 165 - wave, y: 24), CGPoint(x: 133, y: 44), CGPoint(x: 187, y: 38), color: CiggyTheme.lavender, width: 5)
				context.translateBy(x: 0, y: bob)
				// Legs and rounded shoes.
				curve(CGPoint(x: 86, y: 134), CGPoint(x: 76, y: 174), CGPoint(x: 75, y: 151), CGPoint(x: 94, y: 162))
				curve(CGPoint(x: 112, y: 126), CGPoint(x: 135, y: 170), CGPoint(x: 112, y: 151), CGPoint(x: 123, y: 160))
				context.fill(Path(ellipseIn: CGRect(x: 60, y: 169, width: 25, height: 10)), with: .color(palette.primaryText))
				context.fill(Path(ellipseIn: CGRect(x: 128, y: 167, width: 25, height: 10)), with: .color(palette.primaryText))
				curve(CGPoint(x: 68, y: 104), CGPoint(x: 36, y: 85), CGPoint(x: 48, y: 113), CGPoint(x: 33, y: 106))
				line([CGPoint(x: 36, y: 85), CGPoint(x: 29, y: 81), CGPoint(x: 32, y: 90)])
				curve(CGPoint(x: 126, y: 91), CGPoint(x: 171, y: 79 + wave), CGPoint(x: 155, y: 118), CGPoint(x: 165, y: 101))
				line([CGPoint(x: 171, y: 79 + wave), CGPoint(x: 170, y: 72 + wave), CGPoint(x: 176, y: 78 + wave)])
				// Draw the cigarette diagonally as one outlined paper silhouette.
				var body = Path()
				body.move(to: CGPoint(x: 62, y: 127)); body.addLine(to: CGPoint(x: 116, y: 53))
				body.addQuadCurve(to: CGPoint(x: 145, y: 75), control: CGPoint(x: 144, y: 48))
				body.addLine(to: CGPoint(x: 91, y: 149)); body.addQuadCurve(to: CGPoint(x: 62, y: 127), control: CGPoint(x: 62, y: 156))
				body.closeSubpath()
				context.fill(body, with: .color(CiggyTheme.paper))
				// A paper seam and scalloped ash cap make the silhouette read as a cigarette.
				var paperDetail = context
				paperDetail.clip(to: body)
				var seam = Path()
				seam.move(to: CGPoint(x: 91, y: 129)); seam.addLine(to: CGPoint(x: 135, y: 70))
				paperDetail.stroke(seam, with: .color(CiggyTheme.peach.opacity(0.35)), lineWidth: 4)
				var ash = Path()
				ash.addLines([CGPoint(x: 112, y: 56), CGPoint(x: 116, y: 48), CGPoint(x: 145, y: 58), CGPoint(x: 148, y: 76), CGPoint(x: 138, y: 82), CGPoint(x: 137, y: 76), CGPoint(x: 129, y: 75), CGPoint(x: 126, y: 67), CGPoint(x: 119, y: 66)])
				ash.closeSubpath()
				paperDetail.fill(ash, with: .color(CiggyTheme.ink.opacity(0.8)))
				for point in [CGPoint(x: 120, y: 58), CGPoint(x: 130, y: 64), CGPoint(x: 139, y: 72)] {
					paperDetail.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 3, height: 2)), with: .color(CiggyTheme.peach))
				}
				context.stroke(body, with: .color(CiggyTheme.ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
				var filter = Path()
				filter.move(to: CGPoint(x: 62, y: 127)); filter.addLine(to: CGPoint(x: 75, y: 109)); filter.addLine(to: CGPoint(x: 104, y: 131))
				filter.addLine(to: CGPoint(x: 91, y: 149)); filter.addQuadCurve(to: CGPoint(x: 62, y: 127), control: CGPoint(x: 62, y: 156)); filter.closeSubpath()
				context.fill(filter, with: .color(CiggyTheme.peach))
				context.stroke(filter, with: .color(CiggyTheme.ink), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
				for point in [CGPoint(x: 77, y: 122), CGPoint(x: 86, y: 130), CGPoint(x: 76, y: 134), CGPoint(x: 89, y: 141)] {
					context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 2, height: 2)), with: .color(CiggyTheme.ember))
				}
				let blink = time.truncatingRemainder(dividingBy: 5) > 4.8
				for x in [101.0, 117.0] {
					context.fill(Path(ellipseIn: CGRect(x: x, y: x == 101 ? 89 : 80, width: 4, height: blink ? 2 : 8)), with: .color(CiggyTheme.ink))
				}
				// Facial ink stays dark on the cream body, including in Dark appearance.
				curve(CGPoint(x: 104, y: 103), CGPoint(x: 122, y: 92), CGPoint(x: 117, y: 108), CGPoint(x: 126, y: 102), color: CiggyTheme.ink, width: 2.5)
				context.fill(Path(ellipseIn: CGRect(x: 95, y: 100, width: 7, height: 4)), with: .color(CiggyTheme.peach))
				// Four-point doodle stars.
				for (x, y, r) in [(42.0, 48.0, 9.0), (161.0, 139.0, 7.0), (80.0, 32.0, 5.0)] {
					line([CGPoint(x: x - r, y: y), CGPoint(x: x + r, y: y)], width: 2)
					line([CGPoint(x: x, y: y - r), CGPoint(x: x, y: y + r)], width: 2)
				}
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
