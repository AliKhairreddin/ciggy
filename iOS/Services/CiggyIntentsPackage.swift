#if os(iOS)
import AppIntents
import CiggyShared

struct CiggyAppIntentsPackage: AppIntentsPackage {
	static var includedPackages: [any AppIntentsPackage.Type] { [CiggySharedIntentsPackage.self] }
}
#endif
