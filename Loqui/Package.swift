// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistURL = packageDirectory.appendingPathComponent("Info.plist")
let infoPlistData: Data
do {
    infoPlistData = try Data(contentsOf: infoPlistURL)
} catch {
    fatalError("Could not read canonical bundle metadata at \(infoPlistURL.path): \(error)")
}

let infoPlist: [String: Any]
do {
    guard let metadata = try PropertyListSerialization.propertyList(from: infoPlistData, format: nil) as? [String: Any] else {
        fatalError("Canonical bundle metadata at \(infoPlistURL.path) is not a property-list dictionary")
    }
    infoPlist = metadata
} catch {
    fatalError("Could not parse canonical bundle metadata at \(infoPlistURL.path): \(error)")
}

@MainActor func requiredMetadataString(_ key: String) -> String {
    guard let value = infoPlist[key] as? String, !value.isEmpty else {
        fatalError("Canonical bundle metadata at \(infoPlistURL.path) must define a nonempty string \(key)")
    }
    return value
}

let bundleName = requiredMetadataString("CFBundleName")
let executableName = requiredMetadataString("CFBundleExecutable")
let minimumSystemVersion = requiredMetadataString("LSMinimumSystemVersion")

/// Every module compiles in Swift 6 language mode with complete concurrency
/// checking. Module boundaries are enforced by `ArchitectureTests`.
let strictSettings: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: bundleName,
    platforms: [.macOS(minimumSystemVersion)],
    products: [
        .executable(name: executableName, targets: [executableName]),
    ],
    dependencies: [
        // The only third-party dependency: the on-device Parakeet runtime.
        // Only the LoquiParakeet target may depend on it.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
    ],
    targets: [
        // Engine, state machine, and the contracts every other module implements.
        // Foundation, Combine, and os only: no AppKit, audio, or backend imports.
        .target(name: "LoquiCore", swiftSettings: strictSettings),
        // Microphone capture, input devices, recording files, and sound cues.
        .target(name: "LoquiAudio", dependencies: ["LoquiCore"], swiftSettings: strictSettings),
        // The speech backend. The only module that sees FluidAudio.
        .target(
            name: "LoquiParakeet",
            dependencies: ["LoquiCore", .product(name: "FluidAudio", package: "FluidAudio")],
            resources: [.process("Resources")],
            swiftSettings: strictSettings
        ),
        // Accessibility insertion, live drafts, paste fallback, focus detection.
        .target(name: "LoquiDelivery", dependencies: ["LoquiCore"], swiftSettings: strictSettings),
        // The global dictation-key monitor and shortcut recording.
        .target(name: "LoquiShortcuts", dependencies: ["LoquiCore"], swiftSettings: strictSettings),
        // Menu bar, Settings, recording indicator, and transcript card.
        .target(
            name: "LoquiInterface",
            dependencies: ["LoquiCore", "LoquiAudio", "LoquiShortcuts"],
            swiftSettings: strictSettings
        ),
        // The app: composition root and lifecycle only.
        .executableTarget(
            name: executableName,
            dependencies: ["LoquiCore", "LoquiAudio", "LoquiParakeet", "LoquiDelivery", "LoquiShortcuts", "LoquiInterface"],
            path: "Sources/Loqui",
            swiftSettings: strictSettings
        ),
        // Engine fakes shared by the core and app test targets.
        .target(name: "LoquiTestSupport", dependencies: ["LoquiCore"], path: "Tests/LoquiTestSupport"),
        .testTarget(name: "LoquiCoreTests", dependencies: ["LoquiCore", "LoquiTestSupport"]),
        .testTarget(name: "LoquiAudioTests", dependencies: ["LoquiCore", "LoquiAudio"]),
        .testTarget(name: "LoquiParakeetTests", dependencies: ["LoquiCore", "LoquiAudio", "LoquiParakeet"]),
        .testTarget(name: "LoquiDeliveryTests", dependencies: ["LoquiCore", "LoquiDelivery"]),
        .testTarget(name: "LoquiShortcutsTests", dependencies: ["LoquiCore", "LoquiShortcuts"]),
        .testTarget(name: "LoquiInterfaceTests", dependencies: ["LoquiCore", "LoquiInterface"]),
        .testTarget(
            name: "LoquiAppTests",
            dependencies: [.target(name: executableName), "LoquiAudio", "LoquiCore", "LoquiShortcuts", "LoquiTestSupport"]
        ),
        .testTarget(name: "LoquiArchitectureTests"),
    ]
)
