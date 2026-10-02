import SwiftUI

/// Stored separately on each device; incoming detection settings never overwrite appearance.
public enum CiggyAppearance: String, CaseIterable, Identifiable {
	case cream
	case dark
	case system

	public static let storageKey = "Ciggy.appearance.v1"
	public static let defaultValue: Self = .cream
	public var id: Self { self }
	public var title: String {
		switch self {
		case .cream: return "Cream"
		case .dark: return "Dark"
		case .system: return "Follow System"
		}
	}
	public var preferredColorScheme: ColorScheme? {
		switch self {
		case .cream: return .light
		case .dark: return .dark
		case .system: return nil
		}
	}
	public func resolvedColorScheme(systemScheme: ColorScheme) -> ColorScheme {
		preferredColorScheme ?? systemScheme
	}
}

public extension View {
	func ciggyAppearance() -> some View { modifier(CiggyAppearanceModifier()) }
}

private struct CiggyAppearanceModifier: ViewModifier {
	@Environment(\.colorScheme) private var systemScheme
	@AppStorage(CiggyAppearance.storageKey) private var appearance = CiggyAppearance.defaultValue
	func body(content: Content) -> some View {
		content
			.environment(\.colorScheme, appearance.resolvedColorScheme(systemScheme: systemScheme))
			.preferredColorScheme(appearance.preferredColorScheme)
	}
}

public struct CiggyAppearanceSettings: View {
	@Environment(\.colorScheme) private var colorScheme
	@AppStorage(CiggyAppearance.storageKey) private var appearance = CiggyAppearance.defaultValue
	private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }
	public init() {}
	public var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			#if os(watchOS)
			Picker("Appearance", selection: $appearance) {
				ForEach(CiggyAppearance.allCases) { option in Text(option.title).tag(option) }
			}
			.pickerStyle(.navigationLink)
			.accessibilityIdentifier("appearance-picker")
			Text("Applies instantly on this Watch.")
				.font(.system(size: 9)).foregroundStyle(palette.secondaryText)
			#else
			Label("Appearance", systemImage: "circle.lefthalf.filled").font(.headline)
			Picker("Appearance", selection: $appearance) {
				ForEach(CiggyAppearance.allCases) { option in Text(option.title).tag(option) }
			}
			.pickerStyle(.segmented)
			.accessibilityIdentifier("appearance-picker")
			Text("Applies instantly on this device. Follow System matches its light or dark appearance.")
				.font(.caption).foregroundStyle(palette.secondaryText)
			#endif
		}
		.foregroundStyle(palette.primaryText)
	}
}
