// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoBleedingEyes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NoBleedingEyes",
            path: "Sources/NoBleedingEyes"
        ),
        .testTarget(
            name: "NoBleedingEyesTests",
            dependencies: ["NoBleedingEyes"],
            path: "Tests/NoBleedingEyesTests"
        ),
    ]
)
