// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceFlowApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceFlowApp", targets: ["VoiceFlowApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.12.4"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceFlowApp",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/VoiceFlowApp",
            exclude: [
                "Resources/Info.plist",
                "Resources/VoiceFlowApp.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/AppLogoMark.png"),
                .copy("Resources/AppIcon256.png"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "VoiceFlowAppTests",
            dependencies: ["VoiceFlowApp"],
            path: "Tests"
        ),
    ]
)