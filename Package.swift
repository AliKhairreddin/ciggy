// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "Ciggy",
	platforms: [
		.iOS(.v17),
		.watchOS(.v10)
	],
	products: [
		.library(name: "CiggyShared", targets: ["CiggyShared"]),
		.executable(name: "CiggyiOS", targets: ["CiggyiOS"]),
		.executable(name: "CiggyWatch", targets: ["CiggyWatch"])
	],
	targets: [
		.target(
			name: "CiggyShared",
			path: "Shared"
		),
		.executableTarget(
			name: "CiggyiOS",
			dependencies: ["CiggyShared"],
			path: "iOS"
		),
		.executableTarget(
			name: "CiggyWatch",
			dependencies: ["CiggyShared"],
			path: "watchOS"
		)
	]
)
