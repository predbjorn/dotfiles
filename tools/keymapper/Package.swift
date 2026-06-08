// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keymapper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Keymapper"
        ),
        .executableTarget(
            name: "KeymapperApp",
            dependencies: ["Keymapper"]
        ),
        .testTarget(
            name: "KeymapperTests",
            dependencies: ["Keymapper"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
