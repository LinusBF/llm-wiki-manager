// swift-tools-version: 5.9

import PackageDescription

var products: [Product] = [
    .library(name: "LLMWikiCore", targets: ["LLMWikiCore"]),
    .executable(name: "llm-wiki-daemon", targets: ["LLMWikiDaemon"])
]

var coreExcludes: [String] = []
var targets: [Target] = []

#if os(Linux)
coreExcludes = ["AppSettings.swift", "RawFolderWatcher.swift"]
#else
products.append(.executable(name: "LLMWikiManager", targets: ["LLMWikiManager"]))
#endif

targets.append(
    .target(
        name: "LLMWikiCore",
        exclude: coreExcludes,
        resources: [
            .process("Resources")
        ]
    )
)

#if !os(Linux)
targets.append(
    .executableTarget(
        name: "LLMWikiManager",
        dependencies: ["LLMWikiCore"]
    )
)
#endif

targets.append(contentsOf: [
    .executableTarget(
        name: "LLMWikiDaemon",
        dependencies: ["LLMWikiCore"]
    ),
    .testTarget(
        name: "LLMWikiManagerTests",
        dependencies: ["LLMWikiCore"]
    ),
    .testTarget(
        name: "LLMWikiDaemonTests",
        dependencies: ["LLMWikiDaemon"]
    )
])

let package = Package(
    name: "LLMWikiManager",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
