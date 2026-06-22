// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "GoldChart",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "GoldChart", targets: ["GoldChart"])
    ],
    dependencies: [
        .package(url: "https://github.com/danielgindi/Charts.git", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "GoldChart",
            dependencies: [
                .product(name: "DGCharts", package: "Charts")
            ],
            path: "Sources/GoldChart",
            resources: []
        )
    ]
)
