// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessions",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClaudeSessions"
        ),
        .executableTarget(
            name: "ClaudeSessionsApp",
            dependencies: ["ClaudeSessions"]
        ),
        .testTarget(
            name: "ClaudeSessionsTests",
            dependencies: ["ClaudeSessions"]
        ),
    ]
)
