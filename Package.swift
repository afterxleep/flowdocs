// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "flowdocs",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "flowdocs", targets: ["flowdocs"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "flowdocs",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "flowdocsTests",
            dependencies: ["flowdocs"]
        )
    ]
)
