// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CacheCleaner",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CacheCleaner",
            path: "Sources/CacheCleaner",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CacheCleanerTests",
            dependencies: ["CacheCleaner"],
            path: "Tests/CacheCleanerTests"
        )
    ]
)