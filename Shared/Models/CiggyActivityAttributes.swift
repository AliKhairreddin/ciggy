#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

public struct CiggyActivityAttributes: ActivityAttributes {
	public typealias ContentState = LiveActivitySnapshot
	public let startedAt: Date
	public let expiresAt: Date

	public init(startedAt: Date, expiresAt: Date) {
		self.startedAt = startedAt
		self.expiresAt = expiresAt
	}
}
#endif
