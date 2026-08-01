// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AirControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AirControl",
            path: "Sources/AirControl"
        )
    ]
)
