// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchMusic",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchMusic", targets: ["NotchMusic"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NotchMusic",
            path: "Sources/NotchMusic"
        ),
        .testTarget(
            name: "NotchMusicTests",
            dependencies: ["NotchMusic"],
            path: "Tests/NotchMusicTests"
        )
    ]
)
