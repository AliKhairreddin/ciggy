import SwiftUI

/// Ciggy's paper, ink, and ember palette. Watch keeps a dark, glanceable canvas.
public enum CiggyTheme {
	public static let ink = Color(red: 0.16, green: 0.13, blue: 0.19)
	public static let deepInk = ink
	public static let paper = Color(red: 1, green: 0.97, blue: 0.90)
	public static let ember = Color(red: 0.91, green: 0.30, blue: 0.13)
	public static let peach = Color(red: 1, green: 0.72, blue: 0.52)
	public static let sunlight = Color(red: 1, green: 0.79, blue: 0.32)
	public static let lavender = Color(red: 0.73, green: 0.66, blue: 0.92)
	#if os(watchOS)
	public static let mint = Color(red: 0.64, green: 0.86, blue: 0.66)
	#else
	public static let mint = Color(red: 0.20, green: 0.48, blue: 0.39)
	#endif
	public static let softMint = Color(red: 0.76, green: 0.88, blue: 0.72)
	#if os(watchOS)
	public static let surface = Color(red: 0.14, green: 0.12, blue: 0.17)
	public static let elevatedSurface = Color(red: 0.22, green: 0.19, blue: 0.25)
	public static let primaryText = paper
	public static let secondaryText = paper.opacity(0.7)
	public static let border = paper.opacity(0.14)
	#else
	public static let surface = Color(red: 1, green: 0.985, blue: 0.95)
	public static let elevatedSurface = Color(red: 0.94, green: 0.90, blue: 0.85)
	public static let primaryText = ink
	public static let secondaryText = ink.opacity(0.65)
	public static let border = ink.opacity(0.12)
	#endif

	public static var brandGradient: LinearGradient {
		LinearGradient(colors: [peach, sunlight], startPoint: .topLeading, endPoint: .bottomTrailing)
	}
	public static var emberGradient: LinearGradient {
		LinearGradient(colors: [peach, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
	}
	public static var appBackground: LinearGradient {
		#if os(watchOS)
		LinearGradient(colors: [ink, Color(red: 0.06, green: 0.05, blue: 0.08)], startPoint: .top, endPoint: .bottom)
		#else
		LinearGradient(colors: [paper, Color(red: 0.97, green: 0.93, blue: 0.87)], startPoint: .top, endPoint: .bottom)
		#endif
	}
}

public struct CiggyBrandMark: View {
	private let size: CGFloat
	public init(size: CGFloat = 44) { self.size = size }
	public var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: size * 0.30).fill(CiggyTheme.peach)
			RoundedRectangle(cornerRadius: size * 0.30).stroke(CiggyTheme.ink, lineWidth: 1.5)
			CiggyMascot(animated: false).padding(size * 0.04)
		}
		.frame(width: size, height: size)
		.rotationEffect(.degrees(-6))
		.accessibilityHidden(true)
	}
}

public struct CiggyProfileMark: View {
	private let size: CGFloat
	public init(size: CGFloat = 44) { self.size = size }
	public var body: some View {
		Image(systemName: "person.crop.circle")
			.font(.system(size: size * 0.53, weight: .medium))
			.foregroundStyle(CiggyTheme.primaryText)
			.frame(width: size, height: size)
			.ciggyGlass(in: Circle())
			.accessibilityHidden(true)
	}
}

public struct CiggyPanel<Content: View>: View {
	private let content: Content
	public init(@ViewBuilder content: () -> Content) { self.content = content() }
	public var body: some View {
		content.padding(18)
			.background(CiggyTheme.surface, in: RoundedRectangle(cornerRadius: 26))
			.overlay(RoundedRectangle(cornerRadius: 26).stroke(CiggyTheme.border, lineWidth: 1))
	}
}

public struct CiggyStatusPill: View {
	private let title: String
	private let systemImage: String
	private let color: Color
	public init(_ title: String, systemImage: String, color: Color = CiggyTheme.mint) {
		self.title = title; self.systemImage = systemImage; self.color = color
	}
	public var body: some View {
		Label(title, systemImage: systemImage)
			.font(.caption.weight(.semibold))
			.foregroundStyle(color)
			.padding(.horizontal, 12).padding(.vertical, 9)
			.ciggyGlass(in: Capsule())
	}
}

/// Real Liquid Glass on current systems; material on older supported systems.
public extension View {
	func ciggyGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
		modifier(CiggyGlassModifier(shape: shape, interactive: interactive))
	}
}

private struct CiggyGlassModifier<S: Shape>: ViewModifier {
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	let shape: S
	let interactive: Bool
	@ViewBuilder func body(content: Content) -> some View {
		if reduceTransparency {
			content.background(CiggyTheme.surface, in: shape)
				.overlay(shape.stroke(CiggyTheme.border, lineWidth: 1))
		} else {
			if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
				content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
			} else {
				content.background(.regularMaterial, in: shape)
					.overlay(shape.stroke(CiggyTheme.border, lineWidth: 1))
			}
		}
	}
}
