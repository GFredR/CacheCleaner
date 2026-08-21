// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CacheCleaner",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CacheCleaner",
            path: "Sources/CacheCleaner"
        )
    ]
)
