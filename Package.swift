// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindowsCore",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "WindowsCore", path: "Windows/Core"),
        .testTarget(name: "WindowsCoreTests", dependencies: ["WindowsCore"]),
    ]
)
