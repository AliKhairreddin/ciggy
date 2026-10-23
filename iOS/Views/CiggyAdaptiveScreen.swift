#if os(iOS)
import CiggyShared
import SwiftUI

/// Hinge readings provide context; angle-dependent reserved regions drive layout.
struct CiggyDisplayContext {
	struct Hinge: Equatable {
		enum Status { case closed, partiallyOpen, fullyOpen }
		var status: Status
		var degrees: Int
	}
	var mode: CiggyLayoutPlan.Mode = .single
	var hinge: Hinge?
	var overviewHeight: CGFloat = 0
	var isDuoDeskMode: Bool { mode == .tabletop && hinge?.status == .partiallyOpen }
}

private struct CiggyDisplayContextKey: EnvironmentKey {
	static let defaultValue = CiggyDisplayContext()
}

extension EnvironmentValues {
	var ciggyDisplay: CiggyDisplayContext {
		get { self[CiggyDisplayContextKey.self] }
		set { self[CiggyDisplayContextKey.self] = newValue }
	}
}

struct CiggyDuoStatus: View {
	@Environment(\.ciggyDisplay) private var display
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		if let hinge = display.hinge {
			HStack(spacing: 8) {
				Label(title(for: hinge), systemImage: display.mode == .tabletop ? "laptopcomputer" : "book.closed")
				Spacer(minLength: 8)
				Text("\(hinge.degrees)°").monospacedDigit()
			}
			.font(.caption.weight(.semibold))
			.foregroundStyle(CiggyPalette(colorScheme: colorScheme).secondaryText)
			.accessibilityElement(children: .combine)
			.accessibilityIdentifier("duo-posture")
		}
	}

	private func title(for hinge: CiggyDisplayContext.Hinge) -> String {
		if hinge.status == .closed { return "Cover display" }
		switch display.mode {
		case .tabletop: return "Desk mode"
		case .book: return "Book mode"
		default: return hinge.status == .fullyOpen ? "Fully open" : "Partly open"
		}
	}
}

private struct CiggyHingeObserver: ViewModifier {
	@Binding var hinge: CiggyDisplayContext.Hinge?

	@ViewBuilder
	func body(content: Content) -> some View {
		#if canImport(SwiftUI, _version: 8.0.85)
		if #available(iOS 27.1, *) {
			content.onHingeChange { _, context in
				guard let value = context.hinge else { hinge = nil; return }
				let status: CiggyDisplayContext.Hinge.Status
				switch value.status {
				case .closed: status = .closed
				case .fullyOpen: status = .fullyOpen
				default: status = .partiallyOpen
				}
				hinge = .init(status: status, degrees: Int(value.angle.degrees.rounded()))
			}
		} else {
			content
		}
		#else
		content
		#endif
	}
}

/// Each panel scrolls within its usable display region. Screen state belongs to
/// the caller so folding, rotating, and resizing never discard an edit.
struct CiggyAdaptiveScreen<Compact: View, Overview: View, Controls: View>: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@Environment(\.layoutDirection) private var layoutDirection
	@State private var hinge: CiggyDisplayContext.Hinge?
	@State private var isImmersive = false
	private let immersiveDuoDesk: Bool
	private let compact: () -> Compact
	private let overview: (CiggyLayoutPlan.Mode) -> Overview
	private let controls: (CiggyLayoutPlan.Mode) -> Controls

	init(
		immersiveDuoDesk: Bool = false,
		@ViewBuilder compact: @escaping () -> Compact,
		@ViewBuilder overview: @escaping (CiggyLayoutPlan.Mode) -> Overview,
		@ViewBuilder controls: @escaping (CiggyLayoutPlan.Mode) -> Controls
	) {
		self.immersiveDuoDesk = immersiveDuoDesk
		self.compact = compact
		self.overview = overview
		self.controls = controls
	}

	var body: some View {
		GeometryReader { proxy in
			let regions = reservedFrames(in: proxy)
			let plan = CiggyLayoutPlan(
				size: proxy.size,
				regularWidth: horizontalSizeClass == .regular,
				accessibilitySize: dynamicTypeSize.isAccessibilitySize,
				division: regions.division,
				rightToLeft: layoutDirection == .rightToLeft
			)
			let immersive = immersiveDuoDesk && plan.mode == .tabletop && hinge?.status == .partiallyOpen
			ZStack {
				if immersive { CiggyTheme.ink.ignoresSafeArea() } else { CiggyBackdrop() }
				if let controlFrame = plan.controls {
					if immersive {
						immersivePane(in: plan.overview, identifier: "immersive-overview-pane") { overview(plan.mode) }
						immersivePane(in: controlFrame, identifier: "immersive-controls-pane") { controls(plan.mode) }
					} else {
						pane(in: plan.overview, occlusions: regions.occlusions, identifier: "overview-pane") { overview(plan.mode) }
						pane(in: controlFrame, occlusions: regions.occlusions, identifier: "controls-pane") { controls(plan.mode) }
					}
				} else {
					pane(in: plan.overview, occlusions: regions.occlusions, identifier: "compact-pane") {
						compact().frame(maxWidth: 560)
							.frame(maxWidth: .infinity)
					}
				}
			}
			.environment(\.ciggyDisplay, CiggyDisplayContext(mode: plan.mode, hinge: hinge, overviewHeight: plan.overview.height))
			.onChange(of: immersive, initial: true) { _, value in isImmersive = value }
		}
		.ignoresSafeArea(edges: isImmersive ? .all : [])
		.statusBarHidden(isImmersive)
		.persistentSystemOverlays(isImmersive ? .hidden : .automatic)
		.toolbar(isImmersive ? .hidden : .automatic, for: .tabBar)
		.modifier(CiggyHingeObserver(hinge: $hinge))
	}

	private func immersivePane<Content: View>(in frame: CGRect, identifier: String,
		@ViewBuilder content: () -> Content) -> some View {
		content()
			.frame(width: frame.width, height: frame.height)
			.clipped()
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier(identifier)
			.position(x: frame.midX, y: frame.midY)
	}

	private func pane<Content: View>(
		in frame: CGRect, occlusions: [CGRect], identifier: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		let insets = CiggyLayoutPlan.contentInsets(in: frame, occlusions: occlusions)
		return ScrollView {
			VStack(alignment: .leading, spacing: 18, content: content)
				.padding(.leading, layoutDirection == .rightToLeft ? insets.right : insets.left)
				.padding(.trailing, layoutDirection == .rightToLeft ? insets.left : insets.right)
				.padding(.top, insets.top)
				.padding(.bottom, insets.bottom)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.scrollDismissesKeyboard(.interactively)
		.accessibilityIdentifier(identifier)
		.frame(width: frame.width, height: frame.height)
		.position(x: frame.midX, y: frame.midY)
	}

	private func reservedFrames(in proxy: GeometryProxy) -> (division: CGRect?, occlusions: [CGRect]) {
		#if DEBUG
		// Exercise the real pane layout in UI tests on older Simulator runtimes.
		// This overrides geometry only; it never claims to sense a physical hinge.
		if ProcessInfo.processInfo.arguments.contains("--ciggy-preview-fold") {
			if proxy.size.height >= proxy.size.width {
				return (CGRect(x: 0, y: proxy.size.height / 2 - 12, width: proxy.size.width, height: 24), [])
			}
			return (CGRect(x: proxy.size.width / 2 - 12, y: 0, width: 24, height: proxy.size.height), [])
		}
		#endif

		// Xcode 27.0 ships SwiftUI 8.0.84 without the Duo symbols. A runtime
		// availability check alone cannot compile them with that older SDK.
		#if canImport(SwiftUI, _version: 8.0.85)
		if #available(iOS 27.1, *) {
			let divisions = proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
			let occlusions = proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
			return (divisions.first(where: \.isActive)?.frame, occlusions.filter(\.isActive).map(\.frame))
		}
		#endif
		return (nil, [])
	}
}
#endif
