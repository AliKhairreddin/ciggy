#if canImport(SwiftUI)
import SwiftUI

public struct DetectionMomentsView: View {
    public let review: DetectionReview
    @State private var expanded = true
    public init(review: DetectionReview) { self.review = review }

    public var body: some View {
        #if os(watchOS)
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text("When Ciggy counted (\(review.originalCount))")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.font(.caption2)
            }.buttonStyle(.plain)
            if expanded { details }
        }.accessibilityIdentifier("detection-moments")
        #else
        DisclosureGroup(isExpanded: $expanded) { details } label: {
            Text("When Ciggy counted (\(review.originalCount))").font(.caption.weight(.semibold))
        }.accessibilityIdentifier("detection-moments")
        #endif
    }

    private var details: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(review.decision == .adjusted ? "Original motion estimates" : "Motion start → counted time")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(review.detectionMoments.enumerated()), id: \.element.id) { index, moment in
                    Text("\(index + 1). \(moment.summary())")
                        .font(.caption).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("These are motion evidence windows, not confirmed smoking times.")
                    .font(.caption2).foregroundStyle(.secondary)
                if review.decision == .adjusted {
                    Text("Adjusting the count does not assign times to added or removed cigarettes.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
    }
}
#endif
