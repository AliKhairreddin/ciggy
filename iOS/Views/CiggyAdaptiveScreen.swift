#if os(iOS)
import CiggyShared
import SwiftUI

/// Each panel scrolls within its usable display region. Screen state belongs to
/// the caller so folding, rotating, and resizing never discard an edit.
struct CiggyAdaptiveScreen<Compact: View, Overview: View, Controls: View>: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@Environment(\.layoutDirection) private var layoutDirection
	private let compact: () -> Compact
	private let overview: (CiggyLayoutPlan.Mode) -> Overview
	private let controls: (CiggyLayoutPlan.Mode) -> Controls

	init(
		@ViewBuilder compact: @escaping () -> Compact,
		@ViewBuilder overview: @escaping (CiggyLayoutPlan.Mode) -> Overview,
		@ViewBuilder controls: @escaping (CiggyLayoutPlan.Mode) -> Controls
	) {
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
			ZStack {
				CiggyBackdrop()
				if let controlFrame = plan.controls {
					pane(in: plan.overview, occlusions: regions.occlusions, identifier: "overview-pane") {
						overview(plan.mode)
					}
					pane(in: controlFrame, occlusions: regions.occlusions, identifier: "controls-pane") {
						controls(plan.mode)
					}
				} else {
					pane(in: plan.overview, occlusions: regions.occlusions, identifier: "compact-pane") {
						compact().frame(maxWidth: 560)
							.frame(maxWidth: .infinity)
					}
				}
			}
			.accessibilityIdentifier("layout-\(plan.mode.rawValue)")
		}
	}

	private func pane<Content: View>(
		in frame: CGRect, occlusions: [CGRect], identifier: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		let topInset = occlusions.filter { $0.intersects(frame) }
			.map { max(0, $0.maxY - frame.minY) + 8 }.max() ?? 14
		return ScrollView {
			VStack(alignment: .leading, spacing: 18, content: content)
				.padding(.horizontal, 18)
				.padding(.top, max(14, topInset))
				.padding(.bottom, 28)
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
