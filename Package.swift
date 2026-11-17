// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacSnapperCore",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MacSnapperCore", path: "MacSnapper/Core"),
        .testTarget(name: "MacSnapperCoreTests", dependencies: ["MacSnapperCore"]),
    ]
)
