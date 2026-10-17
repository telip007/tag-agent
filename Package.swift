// swift-tools-version: 6.4

import PackageDescription

/// Compiler settings for every target. Every warning is an error and the
/// upcoming Swift features are enabled early so the compiler pushes back as
/// hard as it can. See wiki/concepts/backpressure-setup.md.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "Tag",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        // Git submodule; see wiki/concepts/openrouter-sdk.md.
        .package(path: "Packages/OpenRouter"),
    ],
    targets: [
        .executableTarget(
            name: "Tag",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "OpenRouter", package: "OpenRouter"),
            ],
            swiftSettings: strictSettings,
        )
    ]
)
