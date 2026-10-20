// swift-tools-version: 6.2

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

/// SwiftLint on every build, so violations show up inline in Xcode. Pinned to
/// the same version CI installs. See wiki/concepts/backpressure-setup.md.
let lintPlugins: [Target.PluginUsage] = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
]

let package = Package(
    name: "Tag",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        // Git submodule; see wiki/concepts/openrouter-sdk.md.
        .package(path: "Packages/OpenRouter"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", exact: "0.65.1"),
        // SwiftUI-shaped terminal UI; see wiki/concepts/terminal-ui.md.
        .package(url: "https://github.com/telip007/stipple.git", from: "0.5.2"),
    ],
    targets: [
        // Thin command-line entry point: argument parsing and terminal I/O.
        .executableTarget(
            name: "Tag",
            dependencies: [
                "TagKit",
                "ModelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Stipple", package: "stipple"),
            ],
            swiftSettings: strictSettings,
            plugins: lintPlugins,
        ),
        // The agent itself (loop, model access, tools), kept in a library so
        // tests can import it.
        // Providers, wire formats, sign-in and the model catalogue, with no UI.
        .target(
            name: "ModelKit",
            dependencies: [
                .product(name: "OpenRouter", package: "OpenRouter")
            ],
            swiftSettings: strictSettings,
            plugins: lintPlugins,
        ),
        .target(
            name: "TagKit",
            dependencies: [
                "ModelKit",
                .product(name: "OpenRouter", package: "OpenRouter"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Stipple", package: "stipple"),
            ],
            swiftSettings: strictSettings,
            plugins: lintPlugins,
        ),
        .testTarget(
            name: "ModelKitTests",
            dependencies: [
                "ModelKit",
                .product(name: "OpenRouter", package: "OpenRouter"),
            ],
            swiftSettings: strictSettings,
            plugins: lintPlugins,
        ),
        .testTarget(
            name: "TagKitTests",
            dependencies: [
                "TagKit",
                "ModelKit",
                .product(name: "OpenRouter", package: "OpenRouter"),
                .product(name: "Stipple", package: "stipple"),
            ],
            swiftSettings: strictSettings,
            plugins: lintPlugins,
        ),
    ]
)
