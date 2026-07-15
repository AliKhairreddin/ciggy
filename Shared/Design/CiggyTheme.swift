import SwiftUI

/// Shared visual language for the iPhone and Apple Watch experiences.
public enum CiggyTheme {
	public static let ink = Color(red: 0.055, green: 0.075, blue: 0.09)
	public static let deepInk = Color(red: 0.025, green: 0.035, blue: 0.045)
	public static let surface = Color(red: 0.095, green: 0.125, blue: 0.14)
	public static let elevatedSurface = Color(red: 0.13, green: 0.165, blue: 0.18)
	public static let mint = Color(red: 0.37, green: 0.91, blue: 0.69)
	public static let softMint = Color(red: 0.75, green: 1.0, blue: 0.88)
	public static let ember = Color(red: 1.0, green: 0.48, blue: 0.31)
	public static let sunlight = Color(red: 1.0, green: 0.78, blue: 0.35)
	public static let lavender = Color(red: 0.62, green: 0.58, blue: 1.0)
	public static let secondaryText = Color.white.opacity(0.64)
	public static let border = Color.white.opacity(0.09)

	public static var brandGradient: LinearGradient {
		LinearGradient(
			colors: [mint, Color(red: 0.18, green: 0.68, blue: 0.58)],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}

	public static var emberGradient: LinearGradient {
		LinearGradient(
			colors: [sunlight, ember],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}

	public static var appBackground: LinearGradient {
		LinearGradient(
			colors: [ink, deepInk],
			startPoint: .top,
			endPoint: .bottom
		)
	}
}

public struct CiggyBrandMark: View {
	private let size: CGFloat

	public init(size: CGFloat = 44) {
		self.size = size
	}

	public var body: some View {
		ZStack {
			Circle()
				.fill(CiggyTheme.brandGradient)
			Text("c")
				.font(.system(size: size * 0.62, weight: .black, design: .rounded))
				.foregroundStyle(CiggyTheme.deepInk)
				.offset(y: -size * 0.04)
			Circle()
				.fill(CiggyTheme.ember)
				.frame(width: size * 0.16, height: size * 0.16)
				.offset(x: size * 0.34, y: -size * 0.33)
		}
		.frame(width: size, height: size)
		.accessibilityHidden(true)
	}
}

/// Neutral account avatar used in the top-left position on both companion apps.
public struct CiggyProfileMark: View {
	private let size: CGFloat

	public init(size: CGFloat = 44) {
		self.size = size
	}

	public var body: some View {
		Image(systemName: "person.crop.circle.fill")
			.font(.system(size: size, weight: .semibold))
			.symbolRenderingMode(.palette)
			.foregroundStyle(CiggyTheme.softMint, CiggyTheme.elevatedSurface)
			.frame(width: size, height: size)
			.overlay(Circle().stroke(CiggyTheme.mint.opacity(0.3), lineWidth: 1))
			.accessibilityHidden(true)
	}
}

public struct CiggyPanel<Content: View>: View {
	private let content: Content

	public init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	public var body: some View {
		content
			.padding()
			.background(
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.fill(CiggyTheme.surface)
					.overlay(
						RoundedRectangle(cornerRadius: 22, style: .continuous)
							.stroke(CiggyTheme.border, lineWidth: 1)
					)
			)
	}
}

public struct CiggyStatusPill: View {
	private let title: String
	private let systemImage: String
	private let color: Color

	public init(_ title: String, systemImage: String, color: Color = CiggyTheme.mint) {
		self.title = title
		self.systemImage = systemImage
		self.color = color
	}

	public var body: some View {
		Label(title, systemImage: systemImage)
			.font(.caption.weight(.semibold))
			.foregroundStyle(color)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(color.opacity(0.12), in: Capsule())
	}
}
