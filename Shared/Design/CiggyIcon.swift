import SwiftUI

/// Original Ciggy symbols shared by the companion apps, widgets and system controls.
/// Each asset includes nine weights and three scales, with template rendering so
/// the system can apply Watch-face, Lock Screen and accessibility appearances.
public enum CiggyIcon: String, CaseIterable, Sendable {
    case cigarette = "CiggyIconCigarette"
    case limit = "CiggyIconLimit"
    case elapsed = "CiggyIconElapsed"
    case reports = "CiggyIconReports"
    case log = "CiggyIconLog"
    case settings = "CiggyIconSettings"
    case profile = "CiggyIconProfile"
    case watch = "CiggyIconWatch"
    case savings = "CiggyIconSavings"
    case streak = "CiggyIconStreak"

    /// Retains symbol metadata for native labels, tabs and Control Center.
    public var image: Image {
        Image(rawValue, bundle: .module).renderingMode(.template)
    }
}

/// A decorative icon. Its enclosing label or button supplies the accessible name.
public struct CiggyIconView: View {
    private let icon: CiggyIcon
    private let size: CGFloat

    public init(_ icon: CiggyIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        icon.image.resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
