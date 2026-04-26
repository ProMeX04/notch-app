// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NotchTooling",
            targets: ["NotchTooling"]
        ),
        .library(
            name: "NotchFocusCore",
            targets: ["NotchFocusCore"]
        ),
        .executable(
            name: "Notch",
            targets: ["Notch"]
        ),
        .executable(
            name: "NotchToolParityTests",
            targets: ["NotchToolParityTests"]
        ),
        .executable(
            name: "NotchShelfTests",
            targets: ["NotchShelfTests"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.02"),
    ],
    targets: [
        .target(
            name: "NotchTooling"
        ),
        .target(
            name: "NotchFocusCore"
        ),
        .target(
            name: "NotchShelfCore",
            swiftSettings: [
                // Allow `@testable import NotchShelfCore` from Notch and NotchShelfTests
                // in both debug and release builds.
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        .executableTarget(
            name: "Notch",
            dependencies: [
                "NotchTooling",
                "NotchFocusCore",
                "NotchShelfCore",
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ],
            resources: [
                .copy("Resources/mediaremote-adapter.pl"),
                .copy("Resources/MediaRemoteAdapter.framework"),
                .copy("Resources/MediaRemoteAdapterTestClient"),
                .copy("Resources/BuiltInSkills"),
                .copy("Resources/FocusSounds"),
                .copy("Resources/MenuBar"),
                .copy("Resources/Animations"),
                .copy("docs"),
            ]
        ),
        .executableTarget(
            name: "NotchToolParityTests",
            dependencies: ["NotchTooling"]
        ),
        .executableTarget(
            name: "NotchShelfTests",
            dependencies: ["NotchShelfCore"]
        ),
        .executableTarget(
            name: "NotchFocusTests",
            dependencies: ["NotchFocusCore"],
            path: "Tests/NotchFocusTests"
        ),
    ]
)
