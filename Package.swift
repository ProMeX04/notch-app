// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Notch",
            targets: ["Notch"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.02"),
    ],
    targets: [
        .executableTarget(
            name: "Notch",
            dependencies: [
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ],
            resources: [
                .copy("Resources/mediaremote-adapter.pl"),
                .copy("Resources/MediaRemoteAdapter.framework"),
                .copy("Resources/MediaRemoteAdapterTestClient"),
                .copy("Resources/BuiltInSkills"),
                .copy("Resources/MenuBar"),
            ]
        ),
    ]
)
