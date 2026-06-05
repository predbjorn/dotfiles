// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LaunchDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LaunchDashboard"),
        .testTarget(name: "LaunchDashboardTests", dependencies: ["LaunchDashboard"]),
    ]
)
