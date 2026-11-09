// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Remembrance",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Remembrance", path: "Sources/Remembrance")
    ]
)
