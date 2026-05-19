// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LLMWikiManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LLMWikiCore", targets: ["LLMWikiCore"]),
        .executable(name: "LLMWikiManager", targets: ["LLMWikiManager"])
    ],
    targets: [
        .target(
            name: "LLMWikiCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "LLMWikiManager",
            dependencies: ["LLMWikiCore"]
        ),
        .testTarget(
            name: "LLMWikiManagerTests",
            dependencies: ["LLMWikiCore"]
        )
    ]
)
