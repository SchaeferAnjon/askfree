// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AskFreeCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AskFreeCore",
            targets: ["AskFreeCore"]
        ),
    ],
    targets: [
        .target(
            name: "AskFreeCore",
            path: "Sources/AskFreeCore",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "AskFreeCoreTests",
            dependencies: ["AskFreeCore"],
            path: "Tests/AskFreeCoreTests"
        )
    ]
)
