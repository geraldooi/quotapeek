// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "QuotaPeek",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuotaPeek", targets: ["QuotaPeek"]),
        .executable(
            name: "QuotaPeekClaudeBridge",
            targets: ["QuotaPeekClaudeBridge"]
        )
    ],
    targets: [
        .target(
            name: "QuotaPeekCore"
        ),
        .executableTarget(
            name: "QuotaPeek",
            dependencies: ["QuotaPeekCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "QuotaPeekClaudeBridge",
            dependencies: ["QuotaPeekCore"]
        ),
        .testTarget(
            name: "QuotaPeekCoreTests",
            dependencies: ["QuotaPeekCore"]
        )
    ]
)
