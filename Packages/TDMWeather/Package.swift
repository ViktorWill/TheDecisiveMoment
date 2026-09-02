// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TDMWeather",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "TDMWeather", targets: ["TDMWeather"])
    ],
    dependencies: [
        .package(path: "../TDMCore"),
        .package(path: "../TDMLight")
    ],
    targets: [
        .target(
            name: "TDMWeather",
            dependencies: [
                .product(name: "TDMCore", package: "TDMCore"),
                .product(name: "TDMLight", package: "TDMLight")
            ]
        )
    ]
)
