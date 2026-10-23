#if os(iOS)
import SwiftUI

enum CiggyLoungeScenery: String, CaseIterable {
	case mountains, sky, ocean, beach, forest, desert, aurora, lake, lavender, city
	var title: String {
		switch self {
		case .mountains: return "Alpine morning"
		case .sky: return "Above the clouds"
		case .ocean: return "Open ocean"
		case .beach: return "Golden beach"
		case .forest: return "Misty pines"
		case .desert: return "Desert sunset"
		case .aurora: return "Northern lights"
		case .lake: return "Moonlit lake"
		case .lavender: return "Lavender fields"
		case .city: return "Rainy city"
		}
	}
}

/// Ten original vector landscapes stay sharp at either Duo display scale.
/// Coordinates are a 480 × 320 scene; the ashtray rests on its foreground ledge.
enum CiggyLoungeBackdrop {
	static func draw(_ scene: CiggyLoungeScenery, in context: GraphicsContext) {
		let colors: [Color]
		switch scene {
		case .mountains: colors = [hex(0x80B7CC), hex(0xE8DCC6), hex(0xB1BAB0)]
		case .sky: colors = [hex(0x6E9FCA), hex(0xF2B6B8), hex(0xFFE4C1)]
		case .ocean: colors = [hex(0x83CBD5), hex(0xDAEBDA), hex(0x498F9C)]
		case .beach: colors = [hex(0xF3B795), hex(0xFFE5B0), hex(0xD6C79A)]
		case .forest: colors = [hex(0xAEC1B7), hex(0xE3E5D5), hex(0x728C7E)]
		case .desert: colors = [hex(0x8F779C), hex(0xF4B095), hex(0xD49774)]
		case .aurora: colors = [hex(0x132C40), hex(0x244953), hex(0x49695D)]
		case .lake: colors = [hex(0x242E54), hex(0x747D9A), hex(0x3D6071)]
		case .lavender: colors = [hex(0xC8BADD), hex(0xF5D5C8), hex(0x887E9B)]
		case .city: colors = [hex(0x45445F), hex(0xA194A7), hex(0x555569)]
		}
		context.fill(Path(CGRect(x: 0, y: 0, width: 480, height: 320)),
			with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: 320)))

		switch scene {
		case .mountains:
			sun(context, x: 374, y: 57, radius: 28, color: hex(0xFFF2C9))
			mountain(context, points: [(0, 168), (80, 72), (154, 147), (245, 51), (344, 149), (402, 98), (480, 157)], color: hex(0x718E9B))
			mountain(context, points: [(48, 111), (80, 72), (113, 112), (83, 101)], color: hex(0xE9EFEB), base: 112)
			mountain(context, points: [(204, 101), (245, 51), (291, 101), (250, 83)], color: hex(0xF1F0E5), base: 101)
			hill(context, y: 191, amplitude: 27, phase: 1, color: hex(0x486F75))
			hill(context, y: 223, amplitude: 17, phase: 4, color: hex(0x345A5A))
		case .sky:
			sun(context, x: 360, y: 75, radius: 35, color: hex(0xFFF1CD))
			for cloud in 0..<11 {
				let x = Double((cloud * 83) % 530) - 30
				let y = Double(40 + (cloud * 37) % 160)
				var soft = context; soft.addFilter(.blur(radius: 7))
				soft.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 110, height: 22)), with: .color(.white.opacity(0.40)))
			}
			hill(context, y: 227, amplitude: 14, phase: 2, color: hex(0xD4BBC9).opacity(0.6))
		case .ocean:
			sun(context, x: 370, y: 52, radius: 24, color: hex(0xFFF0C7))
			water(context, horizon: 118, color: hex(0x378E9D), light: hex(0xC0E5DC))
			mountain(context, points: [(0, 183), (30, 152), (67, 166), (94, 201)], color: hex(0x3E7278))
		case .beach:
			sun(context, x: 351, y: 73, radius: 32, color: hex(0xFFF2B5))
			water(context, horizon: 125, color: hex(0x6FAFB2), light: hex(0xF8E5C4))
			hill(context, y: 218, amplitude: 20, phase: 2, color: hex(0xE8CB9F))
			palm(context, x: 50, y: 240, scale: 0.9)
			palm(context, x: 441, y: 232, scale: 0.65)
		case .forest:
			for layer in 0..<3 {
				for tree in 0..<12 {
					let x = Double(tree * 48 - 22 + layer * 16)
					let height = Double(45 + (tree * 19 + layer * 23) % 60)
					pine(context, x: x, y: Double(150 + layer * 38), height: height,
						 color: hex(layer == 0 ? 0x8BA49B : layer == 1 ? 0x607F72 : 0x365F50))
				}
				var fog = context; fog.addFilter(.blur(radius: 12))
				fog.fill(Path(ellipseIn: CGRect(x: -40, y: 143 + layer * 30, width: 560, height: 26)), with: .color(.white.opacity(0.18)))
			}
		case .desert:
			sun(context, x: 350, y: 81, radius: 37, color: hex(0xFFDDA5))
			hill(context, y: 169, amplitude: 25, phase: 0, color: hex(0xBF8A83))
			hill(context, y: 199, amplitude: 30, phase: 2, color: hex(0xDCA483))
			hill(context, y: 235, amplitude: 22, phase: 4, color: hex(0xA36D69))
		case .aurora:
			stars(context)
			for ribbon in 0..<4 {
				var glow = context; glow.addFilter(.blur(radius: 10))
				var path = Path()
				for x in stride(from: 0.0, through: 480, by: 5) {
					let point = CGPoint(x: x, y: 57 + Double(ribbon) * 15 + sin(x / 82 + Double(ribbon)) * 30)
					if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
				}
				glow.stroke(path, with: .color(hex(ribbon.isMultiple(of: 2) ? 0x90DAB7 : 0xB4A1D4).opacity(0.55)), lineWidth: 17)
			}
			mountain(context, points: [(0, 197), (89, 135), (158, 180), (269, 127), (387, 189), (449, 145), (480, 175)], color: hex(0x1B3942))
		case .lake:
			stars(context)
			sun(context, x: 363, y: 57, radius: 21, color: hex(0xFFF2CE))
			mountain(context, points: [(0, 153), (80, 104), (135, 142), (232, 91), (324, 142), (410, 100), (480, 145)], color: hex(0x34435F))
			water(context, horizon: 161, color: hex(0x3D6071), light: hex(0xB8B3C7))
			for index in 0..<8 {
				context.fill(Path(ellipseIn: CGRect(x: 350 - index * 3, y: 166 + index * 7, width: 25 + index * 6, height: 2)), with: .color(hex(0xF4DDAF).opacity(0.32)))
			}
		case .lavender:
			sun(context, x: 369, y: 61, radius: 28, color: hex(0xFFEDCB))
			hill(context, y: 153, amplitude: 20, phase: 3, color: hex(0x91A08D))
			hill(context, y: 183, amplitude: 16, phase: 1, color: hex(0x78778D))
			for row in 0..<10 {
				var path = Path()
				path.move(to: CGPoint(x: 230 + row * 5, y: 169))
				path.addLine(to: CGPoint(x: row * 62 - 75, y: 255))
				context.stroke(path, with: .color(hex(row.isMultiple(of: 2) ? 0xB49BC5 : 0x74648F)),
					style: StrokeStyle(lineWidth: 12, lineCap: .round))
			}
		case .city:
			for building in 0..<19 {
				let x = Double(building * 28 - 12)
				let top = Double(70 + (building * 31) % 90)
				context.fill(Path(CGRect(x: x, y: top, width: 25, height: 260 - top)), with: .color(hex(building.isMultiple(of: 2) ? 0x43445B : 0x57586D)))
				for window in 0..<4 where !(window + building).isMultiple(of: 3) {
					context.fill(Path(CGRect(x: x + 7, y: top + 12 + Double(window * 19), width: 5, height: 8)), with: .color(hex(0xE8C4A1).opacity(0.7)))
				}
			}
			for drop in 0..<70 {
				let x = Double((drop * 79) % 500)
				let y = Double((drop * 43) % 245)
				var line = Path(); line.move(to: CGPoint(x: x, y: y)); line.addLine(to: CGPoint(x: x - 5, y: y + 15))
				context.stroke(line, with: .color(.white.opacity(0.16)), lineWidth: 0.8)
			}
		}
		// A quiet ledge grounds the ceramic in every landscape.
		context.fill(Path(CGRect(x: 0, y: 239, width: 480, height: 81)),
			with: .linearGradient(Gradient(colors: [hex(0xD1B997), hex(0xA78D75)]),
				startPoint: CGPoint(x: 0, y: 239), endPoint: CGPoint(x: 0, y: 320)))
		for grain in 0..<5 {
			var path = Path(); path.move(to: CGPoint(x: 0, y: 248 + grain * 16)); path.addLine(to: CGPoint(x: 480, y: 245 + grain * 16))
			context.stroke(path, with: .color(hex(0x6A564A).opacity(0.10)), lineWidth: 1)
		}
	}

	private static func hex(_ value: Int) -> Color {
		Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
	}
	private static func sun(_ context: GraphicsContext, x: Double, y: Double, radius: Double, color: Color) {
		var halo = context; halo.addFilter(.blur(radius: 13))
		halo.fill(Path(ellipseIn: CGRect(x: x - radius * 1.4, y: y - radius * 1.4, width: radius * 2.8, height: radius * 2.8)), with: .color(color.opacity(0.25)))
		context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
	}
	private static func mountain(_ context: GraphicsContext, points: [(Double, Double)], color: Color, base: Double = 250) {
		var path = Path(); path.move(to: CGPoint(x: points[0].0, y: base))
		for point in points { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
		path.addLine(to: CGPoint(x: points.last!.0, y: base)); path.closeSubpath()
		context.fill(path, with: .color(color))
	}
	private static func hill(_ context: GraphicsContext, y: Double, amplitude: Double, phase: Double, color: Color) {
		var path = Path(); path.move(to: CGPoint(x: 0, y: 320))
		for x in stride(from: 0.0, through: 480, by: 5) { path.addLine(to: CGPoint(x: x, y: y + sin(x / 110 + phase) * amplitude)) }
		path.addLine(to: CGPoint(x: 480, y: 320)); path.closeSubpath(); context.fill(path, with: .color(color))
	}
	private static func water(_ context: GraphicsContext, horizon: Double, color: Color, light: Color) {
		context.fill(Path(CGRect(x: 0, y: horizon, width: 480, height: 320 - horizon)), with: .color(color))
		for wave in 0..<13 {
			var path = Path()
			for x in stride(from: 0.0, through: 480, by: 8) {
				let point = CGPoint(x: x, y: horizon + Double(wave * 9) + sin(x / 32 + Double(wave)) * 2.5)
				if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
			}
			context.stroke(path, with: .color(light.opacity(0.25)), lineWidth: wave.isMultiple(of: 3) ? 2 : 0.7)
		}
	}
	private static func pine(_ context: GraphicsContext, x: Double, y: Double, height: Double, color: Color) {
		mountain(context, points: [(x - height * 0.25, y), (x, y - height), (x + height * 0.25, y)], color: color, base: y)
	}
	private static func palm(_ context: GraphicsContext, x: Double, y: Double, scale: Double) {
		let crown = CGPoint(x: x + 22 * scale, y: y - 126 * scale)
		var trunk = Path(); trunk.move(to: CGPoint(x: x, y: y)); trunk.addQuadCurve(to: crown, control: CGPoint(x: x + 5, y: y - 100 * scale))
		context.stroke(trunk, with: .color(hex(0x4C7165)), style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round))
		for leaf in 0..<7 {
			let angle = Double(leaf) * .pi / 4
			var path = Path(); path.move(to: crown)
			path.addQuadCurve(to: CGPoint(x: crown.x + cos(angle) * 55 * scale, y: crown.y + sin(angle) * 35 * scale),
				control: CGPoint(x: crown.x + cos(angle) * 34 * scale, y: crown.y - 24 * scale))
			context.stroke(path, with: .color(hex(0x4C7165)), style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
		}
	}
	private static func stars(_ context: GraphicsContext) {
		for star in 0..<60 {
			context.fill(Path(ellipseIn: CGRect(x: Double((star * 97) % 480), y: Double((star * 47) % 143), width: star.isMultiple(of: 4) ? 2 : 1, height: 1.5)), with: .color(.white.opacity(0.55)))
		}
	}
}
#endif
