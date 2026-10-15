// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "SwiftTrueTypeInterpreter",
	platforms: [
		.macOS("26.0")
	],
	dependencies: [
		.package(
			url: "https://github.com/apple/swift-collections",
			from: "1.6.0",
			traits: [.defaults, .trait(name: "UnstableContainersPreview")]
		),
		.package(url: "https://github.com/ordo-one/benchmark", from: "1.27.0", traits: []),
	],
	targets: [
		.target(
			name: "SwiftTrueTypeInterpreter",
			dependencies: [
				.product(name: "BasicContainers", package: "swift-collections"),
				.product(name: "ContainersPreview", package: "swift-collections"),
			],
			exclude: ["Private/Vendored/NOTICE.txt"],
			swiftSettings: [
				.enableExperimentalFeature("Lifetimes"),
				.swiftLanguageMode(.v6),
				.strictMemorySafety(),
			]
		),
		.testTarget(
			name: "SwiftTrueTypeInterpreterTests",
			dependencies: [
				"SwiftTrueTypeInterpreter",
				.product(name: "BasicContainers", package: "swift-collections"),
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
				.strictMemorySafety(),
			]
		),
		.executableTarget(
			name: "GlyphHinting",
			dependencies: [
				.product(name: "Benchmark", package: "benchmark"),
				.product(name: "BasicContainers", package: "swift-collections"),
				"SwiftTrueTypeInterpreter",
			],
			path: "Benchmarks/GlyphHinting",
			exclude: ["README.md"],
			swiftSettings: [
				.swiftLanguageMode(.v6),
				.strictMemorySafety(),
			],
			plugins: [
				.plugin(name: "BenchmarkPlugin", package: "benchmark")
			]
		),
	]
)
