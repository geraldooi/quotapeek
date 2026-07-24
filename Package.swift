// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "QuotaPeek",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuotaPeek", targets: ["QuotaPeek"])
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
        .testTarget(
            name: "QuotaPeekCoreTests",
            dependencies: ["QuotaPeekCore"]
        )
    ]
)
