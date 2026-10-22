// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JSONFormatter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "JSONFormatter",
            path: "Sources/JSONFormatter"
        )
    ]
)
