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
        // 回答正文的排版（段落、公式、代码块），App 和离屏渲染测试共用
        .library(
            name: "AnswerRender",
            targets: ["AnswerRender"]
        ),
    ],
    dependencies: [
        // 公式排版。MIT，钉在 main 的这个 commit 上（1.7.3 那个 tag 不认 \dfrac）；升级先看 diff，再跑 FormulaCorpusTests
        .package(url: "https://github.com/mgriebling/SwiftMath.git", revision: "0b0222e102ba415b352cd29f334075622bd4e6aa"),
    ],
    targets: [
        .target(
            name: "AskFreeCore",
            path: "Sources/AskFreeCore",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "AnswerRender",
            dependencies: ["AskFreeCore", .product(name: "SwiftMath", package: "SwiftMath")],
            path: "Sources/AnswerRender"
        ),
        .testTarget(
            name: "AskFreeCoreTests",
            dependencies: ["AskFreeCore"],
            path: "Tests/AskFreeCoreTests"
        ),
        .testTarget(
            name: "AnswerRenderTests",
            dependencies: ["AnswerRender", "AskFreeCore"],
            path: "Tests/AnswerRenderTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
