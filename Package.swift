// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaptureToPrompt",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CaptureToPrompt",
            path: "Sources/CaptureToPrompt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CaptureToPromptTests",
            dependencies: ["CaptureToPrompt"],
            path: "Tests/CaptureToPromptTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
