// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "NotchTooling",
            targets: ["NotchTooling"]
        ),
        .library(
            name: "NotchFocusFeature",
            targets: ["NotchFocusFeature"]
        ),
        .library(
            name: "NotchMailParserCore",
            targets: ["NotchMailParserCore"]
        ),
        .library(
            name: "NotchChatHistoryFeature",
            targets: ["NotchChatHistoryFeature"]
        ),
        .library(
            name: "NotchScreenShareCore",
            targets: ["NotchScreenShareCore"]
        ),
        .library(
            name: "NotchGeminiLiveCore",
            targets: ["NotchGeminiLiveCore"]
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
            name: "NotchMailParserTests",
            targets: ["NotchMailParserTests"]
        ),
        .executable(
            name: "NotchChatHistoryTests",
            targets: ["NotchChatHistoryTests"]
        ),
        .executable(
            name: "NotchScreenShareTests",
            targets: ["NotchScreenShareTests"]
        ),
        .executable(
            name: "NotchGeminiLiveTests",
            targets: ["NotchGeminiLiveTests"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.02"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.1"),
        .package(path: ".vendor/iosMath"),
    ],
    targets: [
        .target(
            name: "NotchTooling"
        ),
        .target(
            name: "NotchFocusFeature"
        ),
        .target(
            name: "NotchShelfFeature",
            swiftSettings: [
                // Allow `@testable import NotchShelfFeature` from Notch and NotchShelfTests
                // in both debug and release builds.
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        .target(
            name: "NotchGeminiLiveCore"
        ),
        .executableTarget(
            name: "Notch",
            dependencies: [
                "NotchTooling",
                "NotchGeminiLiveCore",
                "NotchFocusFeature",
                "NotchShelfFeature",
                "NotchChatHistoryFeature",
                "NotchScreenShareCore",
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "iosMath", package: "iosMath"),
            ],
            resources: [
                .copy("Resources/mediaremote-adapter.pl"),
                .copy("Resources/MediaRemoteAdapter.framework"),
                .copy("Resources/MediaRemoteAdapterTestClient"),
                .copy("Resources/FocusSounds"),
                .copy("Resources/MenuBar"),
                .copy("Resources/Animations"),
                .copy("Resources/Shared"),
                .copy("Resources/WebMarkdown"),
                .copy("Resources/TOEIC"),
            ]
        ),
        .executableTarget(
            name: "NotchShelfTests",
            dependencies: ["NotchShelfFeature"]
        ),
        .executableTarget(
            name: "NotchFocusTests",
            dependencies: ["NotchFocusFeature"],
            path: "Tests/NotchFocusTests"
        ),
        .target(
            name: "NotchMailParserCore"
        ),
        .target(
            name: "NotchChatHistoryFeature"
        ),
        .target(
            name: "NotchScreenShareCore"
        ),
        .executableTarget(
            name: "NotchMailParserTests",
            dependencies: ["NotchMailParserCore"],
            path: "Tests/NotchMailParserTests"
        ),
        .executableTarget(
            name: "NotchChatHistoryTests",
            dependencies: ["NotchChatHistoryFeature"],
            path: "Tests/NotchChatHistoryTests"
        ),
        .executableTarget(
            name: "NotchScreenShareTests",
            dependencies: ["NotchScreenShareCore"],
            path: "Tests/NotchScreenShareTests"
        ),
        .executableTarget(
            name: "NotchGeminiLiveTests",
            dependencies: ["NotchGeminiLiveCore"],
            path: "Tests/NotchGeminiLiveTests"
        ),
        .testTarget(
            name: "NotchMediaTests",
            dependencies: ["Notch"],
            path: "Tests/NotchMediaTests"
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
