// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DiskCleaner"),
        .testTarget(name: "DiskCleanerTests", dependencies: ["DiskCleaner"], resources: [.copy("Fixtures")]),
    ]
)
