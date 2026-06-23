// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "res",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ResCore", targets: ["ResCore"]),
        .executable(name: "res", targets: ["res"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ResCore",
            path: "Sources/ResCore"
        ),
        .executableTarget(
            name: "res",
            dependencies: [
                "ResCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/res"
        ),
        .testTarget(
            name: "ResCoreTests",
            dependencies: ["ResCore"],
            path: "Tests/ResCoreTests",
            // Command Line Tools (no full Xcode) ship swift-testing's runtime
            // but SwiftPM doesn't auto-wire the macro plugin or the framework
            // search/rpath. Bake them in so a bare `swift test` works.
            swiftSettings: [
                .unsafeFlags([
                    "-plugin-path",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
