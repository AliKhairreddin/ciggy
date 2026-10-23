// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "Ciggy",
	platforms: [
		.macOS(.v13),
		.iOS(.v17),
		.watchOS(.v10)
	],
	products: [
		.library(name: "CiggyShared", targets: ["CiggyShared"]),
		.executable(name: "CiggyiOS", targets: ["CiggyiOS"]),
		.executable(name: "CiggyWatch", targets: ["CiggyWatch"]),
		.executable(name: "CiggyMotionBenchmark", targets: ["CiggyMotionBenchmark"])
	],
	targets: [
		.target(
			name: "CiggyShared",
			path: "Shared",
			resources: [.process("Resources")]
		),
		.executableTarget(
			name: "CiggyiOS",
			dependencies: ["CiggyShared"],
			path: "iOS",
			resources: [.copy("PrivacyInfo.xcprivacy")]
		),
		.executableTarget(
			name: "CiggyWatch",
			dependencies: ["CiggyShared"],
			path: "watchOS",
			resources: [.copy("PrivacyInfo.xcprivacy")]
		),
		.executableTarget(
			name: "CiggyMotionBenchmark",
			dependencies: ["CiggyShared"],
			path: "Tools/MotionBenchmark/Swift"
		),
		.testTarget(
			name: "CiggySharedTests",
			dependencies: ["CiggyShared"],
			path: "Tests/CiggySharedTests"
		)
	]
)
