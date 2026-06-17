// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgeOfProvinces",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .executable(name: "SimCLI", targets: ["SimCLI"])
    ],
    dependencies: [
        // Yams is the one justified external dependency: YAML is the canonical
        // card/rules format and Swift has no built-in YAML parser. It is pure
        // Swift with no system dependencies.
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.2.0")
    ],
    targets: [
        .target(
            name: "GameCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/GameCore"
        ),
        .executableTarget(
            name: "SimCLI",
            dependencies: ["GameCore"],
            path: "Sources/SimCLI"
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"],
            path: "Tests/GameCoreTests"
        )
    ]
)
