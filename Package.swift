// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "SwiftTrueTypeInterpreter",
	platforms: [
		.macOS("27.0")
	],
	dependencies: [
		.package(url: "https://github.com/ordo-one/benchmark", from: "1.27.0", traits: []),
	],
	targets: [
		.target(
			name: "SwiftTrueTypeInterpreter",
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
				"SwiftTrueTypeInterpreter",
			],
			path: "Benchmarks/GlyphHinting",
			exclude: ["README.md"],
			swiftSettings: [
				.enableExperimentalFeature("Lifetimes"),
				.swiftLanguageMode(.v6),
				.strictMemorySafety(),
			],
			plugins: [
				.plugin(name: "BenchmarkPlugin", package: "benchmark")
			]
		),
	]
)
