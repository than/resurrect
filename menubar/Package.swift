// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ResBar",
            path: "Sources/ResBar"
        )
    ]
)
