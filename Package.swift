// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowShopper",
    platforms: [
        .macOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .library(name: "WindowShopper", targets: ["WindowShopper"]),
        .executable(name: "WindowShopperDemo", targets: ["WindowShopperDemo"])
    ],
    targets: [
        .target(
            name: "WindowShopper",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "WindowShopperDemo",
            dependencies: ["WindowShopper"]
        ),
        .testTarget(
            name: "WindowShopperTests",
            dependencies: ["WindowShopper"]
        )
    ],
    swiftLanguageModes: [.v5]
)
