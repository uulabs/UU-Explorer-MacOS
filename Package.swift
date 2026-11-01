// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Explorer", targets: ["Explorer"])
    ],
    targets: [
        .target(
            name: "ExplorerCore",
            path: "Sources/ExplorerCore"
        ),
        .executableTarget(
            name: "Explorer",
            dependencies: ["ExplorerCore"],
            path: "Sources/Explorer"
        ),
        .testTarget(
            name: "ExplorerCoreTests",
            dependencies: ["ExplorerCore"],
            path: "Tests/ExplorerCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
