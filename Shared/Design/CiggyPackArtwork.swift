import SwiftUI

/// Fictional labels from Ciggy's Department of Bad Excuses.
/// These are decorative satire, never products, rewards, or logging categories.
public enum CiggyPackBrand: String, CaseIterable, Identifiable {
	case ashford, ego, later
	public var id: Self { self }
	public var name: String {
		switch self {
		case .ashford: return "Ashford"
		case .ego: return "Égo"
		case .later: return "Later"
		}
	}
	public var slogan: String {
		switch self {
		case .ashford: return "Old money. New ash."
		case .ego: return "A very expensive air."
		case .later: return "Tomorrow’s finest."
		}
	}
	fileprivate var ink: Color {
		switch self {
		case .ashford: return Color(red: 0.43, green: 0.16, blue: 0.20)
		case .ego: return Color(red: 0.12, green: 0.30, blue: 0.29)
		case .later: return Color(red: 0.72, green: 0.28, blue: 0.13)
		}
	}
}

/// Resolution-independent packaging; all lettering and emblems are drawn locally.
public struct CiggyPackArtwork: View {
	private let brand: CiggyPackBrand
	public init(_ brand: CiggyPackBrand) { self.brand = brand }

	public var body: some View {
		Canvas { context, size in
			let scale = min(size.width / 120, size.height / 176)
			context.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 176 * scale) / 2)
			context.scaleBy(x: scale, y: scale)
			let paper = CiggyTheme.paper
			let ink = brand.ink
			let gold = Color(red: 0.82, green: 0.64, blue: 0.36)
			func polygon(_ points: [CGPoint], _ color: Color) {
				var path = Path(); path.addLines(points); path.closeSubpath()
				context.fill(path, with: .color(color))
			}
			func rule(_ start: CGPoint, _ end: CGPoint, _ color: Color, width: CGFloat = 1) {
				var path = Path(); path.move(to: start); path.addLine(to: end)
				context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
			}
			func text(_ value: String, x: CGFloat = 54, y: CGFloat, size: CGFloat, color: Color,
					  weight: Font.Weight = .regular, design: Font.Design = .serif) {
				context.draw(Text(value).font(.system(size: size, weight: weight, design: design)).foregroundColor(color), at: CGPoint(x: x, y: y))
			}
			// Slight three-quarter view: folded lid, narrow spine, offset printed face.
			context.fill(Path(roundedRect: CGRect(x: 10, y: 12, width: 106, height: 162), cornerRadius: 3), with: .color(CiggyTheme.ink.opacity(0.12)))
			polygon([CGPoint(x: 4, y: 14), CGPoint(x: 18, y: 5), CGPoint(x: 116, y: 5), CGPoint(x: 104, y: 14)], Color(red: 0.91, green: 0.85, blue: 0.72))
			rule(CGPoint(x: 20, y: 8), CGPoint(x: 108, y: 8), ink.opacity(0.25), width: 0.6)
			polygon([CGPoint(x: 104, y: 14), CGPoint(x: 116, y: 5), CGPoint(x: 116, y: 158), CGPoint(x: 104, y: 167)], ink.opacity(0.85))
			let face = Path(roundedRect: CGRect(x: 4, y: 14, width: 100, height: 153), cornerRadius: 2)
			context.fill(face, with: .color(brand == .ego ? ink : paper))
			context.stroke(face, with: .color(ink), lineWidth: 1.4)
			rule(CGPoint(x: 5, y: 37), CGPoint(x: 103, y: 37), brand == .ego ? gold : ink.opacity(0.4))
			text("20 FILTERED EXCUSES", y: 26, size: 6, color: brand == .ego ? gold : ink, weight: .bold, design: .monospaced)

			switch brand {
			case .ashford:
				context.fill(Path(CGRect(x: 5, y: 43, width: 98, height: 90)), with: .color(ink))
				context.stroke(Path(CGRect(x: 10, y: 48, width: 88, height: 80)), with: .color(gold), lineWidth: 0.7)
				// An aristocratic monogram whose entire estate is an ashtray.
				context.stroke(Path(ellipseIn: CGRect(x: 43, y: 54, width: 22, height: 24)), with: .color(gold), lineWidth: 1)
				text("A", y: 66, size: 18, color: gold, weight: .bold)
				text("ASHFORD", y: 91, size: 17, color: paper, weight: .bold)
				text("RESERVE OF REGRET", y: 108, size: 5.8, color: gold, weight: .bold, design: .monospaced)
				text("EST. YESTERDAY", y: 121, size: 5, color: paper, design: .monospaced)
				text("OLD MONEY.", y: 144, size: 7, color: ink, weight: .bold)
				text("NEW ASH.", y: 155, size: 7, color: ink, weight: .bold)
			case .ego:
				// Art-deco geometry and an absurdly self-important luxury seal.
				context.stroke(Path(CGRect(x: 11, y: 44, width: 86, height: 114)), with: .color(gold), lineWidth: 1)
				polygon([CGPoint(x: 54, y: 49), CGPoint(x: 65, y: 61), CGPoint(x: 54, y: 73), CGPoint(x: 43, y: 61)], gold)
				text("É", y: 61, size: 16, color: ink, weight: .bold)
				text("Égo", y: 94, size: 37, color: paper)
				text("AIR OF IMPORTANCE", y: 120, size: 5.8, color: gold, weight: .bold, design: .monospaced)
				rule(CGPoint(x: 27, y: 132), CGPoint(x: 81, y: 132), gold)
				text("A VERY EXPENSIVE AIR", y: 145, size: 5.5, color: paper, design: .monospaced)
			case .later:
				// A sunset doubles as a clock permanently stuck on "not now".
				context.fill(Path(ellipseIn: CGRect(x: 28, y: 47, width: 52, height: 52)), with: .color(CiggyTheme.sunlight))
				rule(CGPoint(x: 54, y: 57), CGPoint(x: 54, y: 74), ink, width: 2)
				rule(CGPoint(x: 54, y: 74), CGPoint(x: 66, y: 80), ink, width: 2)
				for y in stride(from: CGFloat(84), through: 102, by: 6) {
					rule(CGPoint(x: 6, y: y), CGPoint(x: 102, y: y), ink, width: 2)
				}
				context.fill(Path(CGRect(x: 5, y: 108, width: 98, height: 29)), with: .color(ink))
				text("Later", y: 121, size: 28, color: paper, weight: .black, design: .rounded)
				text("TOMORROW’S FINEST", y: 147, size: 6.5, color: ink, weight: .bold, design: .monospaced)
				text("SINCE EVENTUALLY", y: 158, size: 5.3, color: ink, design: .monospaced)
			}
			// Quiet print grain, fixed positions: no animation or randomized rendering.
			for index in 0..<65 {
				let x = CGFloat((index * 37) % 94) + 7
				let y = CGFloat((index * 53) % 143) + 18
				context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)), with: .color(paper.opacity(0.16)))
			}
		}
		.aspectRatio(120.0 / 176.0, contentMode: .fit)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}

/// Fixed paper collage, revealed between the foreground cards as they scroll.
/// Angles are intentionally stable so re-rendering never shuffles the wallpaper.
public struct CiggyPackWallpaper: View {
	@Environment(\.colorScheme) private var colorScheme
	public init() {}
	public var body: some View {
		GeometryReader { geometry in
			let width = geometry.size.width
			let height = geometry.size.height
			#if os(watchOS)
			let packWidth = min(72, width * 0.36)
			#else
			let packWidth = min(170, width * 0.36)
			#endif
			ZStack {
				CiggyPackArtwork(.ashford)
					.frame(width: packWidth)
					.rotationEffect(.degrees(-19))
					.position(x: width * 0.88, y: height * 0.16)
				CiggyPackArtwork(.ego)
					.frame(width: packWidth * 0.94)
					.rotationEffect(.degrees(16))
					.position(x: width * 0.10, y: height * 0.52)
				CiggyPackArtwork(.later)
					.frame(width: packWidth * 0.90)
					.rotationEffect(.degrees(-12))
					.position(x: width * 0.88, y: height * 0.88)
			}
			.opacity(colorScheme == .dark ? 0.26 : 0.48)
		}
		.clipped()
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}
