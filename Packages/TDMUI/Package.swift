// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TDMUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "TDMUI", targets: ["TDMUI"])
    ],
    dependencies: [
        .package(path: "../TDMCore"),
        .package(path: "../TDMLight"),
        .package(path: "../TDMSpots"),
        .package(path: "../TDMWeather"),
        .package(path: "../TDMPersistence")
    ],
    targets: [
        .target(
            name: "TDMUI",
            dependencies: [
                .product(name: "TDMCore", package: "TDMCore"),
                .product(name: "TDMLight", package: "TDMLight"),
                .product(name: "TDMSpots", package: "TDMSpots"),
                .product(name: "TDMWeather", package: "TDMWeather"),
                .product(name: "TDMPersistence", package: "TDMPersistence")
            ]
        )
    ]
)
