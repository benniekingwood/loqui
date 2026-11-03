// swift-tools-version: 6.0
import PackageDescription

/// A standalone benchmark for comparing speech models on your own dictation.
/// It is not part of the app: it pins the same FluidAudio release as
/// `Loqui/Package.swift` so results reflect the runtime Loqui ships.
let package = Package(
    name: "LoquiModelBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
    ],
    targets: [
        .executableTarget(
            name: "loqui-model-bench",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
