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
        .library(
            name: "NotchBridgeParserCore",
            targets: ["NotchBridgeParserCore"]
        ),
        .library(
            name: "NotchMailParserCore",
            targets: ["NotchMailParserCore"]
        ),
        .library(
            name: "NotchChatHistoryCore",
            targets: ["NotchChatHistoryCore"]
        ),
        .library(
            name: "NotchGeminiSkillStorage",
            targets: ["NotchGeminiSkillStorage"]
        ),
        .library(
            name: "NotchScreenShareCore",
            targets: ["NotchScreenShareCore"]
        ),
        .executable(
            name: "Notch",
            targets: ["Notch"]
        ),
        .executable(
            name: "NotchShelfTests",
            targets: ["NotchShelfTests"]
        ),
        .executable(
            name: "NotchBridgeParserTests",
            targets: ["NotchBridgeParserTests"]
        ),
        .executable(
            name: "NotchMailParserTests",
            targets: ["NotchMailParserTests"]
        ),
        .executable(
            name: "NotchSkillsTests",
            targets: ["NotchSkillsTests"]
        ),
        .executable(
            name: "NotchChatHistoryTests",
            targets: ["NotchChatHistoryTests"]
        ),
        .executable(
            name: "NotchScreenShareTests",
            targets: ["NotchScreenShareTests"]
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
        .target(
            name: "NotchGeminiSkillStorage"
        ),
        .executableTarget(
            name: "NotchSkillsTests",
            dependencies: ["NotchGeminiSkillStorage"],
            path: "Tests/NotchSkillsTests"
        ),
        .executableTarget(
            name: "Notch",
            dependencies: [
                "NotchTooling",
                "NotchGeminiSkillStorage",
                "NotchFocusCore",
                "NotchShelfCore",
                "NotchBridgeParserCore",
                "NotchMailParserCore",
                "NotchChatHistoryCore",
                "NotchScreenShareCore",
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ],
            resources: [
                .copy("Resources/mediaremote-adapter.pl"),
                .copy("Resources/MediaRemoteAdapter.framework"),
                .copy("Resources/MediaRemoteAdapterTestClient"),
                .copy("Resources/FocusSounds"),
                .copy("Resources/MenuBar"),
                .copy("Resources/Animations"),
                .copy("Resources/Shared"),
            ]
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
        .target(
            name: "NotchBridgeParserCore"
        ),
        .target(
            name: "NotchMailParserCore"
        ),
        .target(
            name: "NotchChatHistoryCore"
        ),
        .target(
            name: "NotchScreenShareCore"
        ),
        .executableTarget(
            name: "NotchBridgeParserTests",
            dependencies: ["NotchBridgeParserCore"],
            path: "Tests/NotchBridgeParserTests"
        ),
        .executableTarget(
            name: "NotchMailParserTests",
            dependencies: ["NotchMailParserCore"],
            path: "Tests/NotchMailParserTests"
        ),
        .executableTarget(
            name: "NotchChatHistoryTests",
            dependencies: ["NotchChatHistoryCore"],
            path: "Tests/NotchChatHistoryTests"
        ),
        .executableTarget(
            name: "NotchScreenShareTests",
            dependencies: ["NotchScreenShareCore"],
            path: "Tests/NotchScreenShareTests"
        ),
    ]
)
