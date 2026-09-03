// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TDMPersistence",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "TDMPersistence", targets: ["TDMPersistence"])
    ],
    dependencies: [
        .package(path: "../TDMCore"),
        .package(path: "../TDMSpots")
    ],
    targets: [
        .target(
            name: "TDMPersistence",
            dependencies: [
                .product(name: "TDMCore", package: "TDMCore"),
                .product(name: "TDMSpots", package: "TDMSpots")
            ]
        ),
        .testTarget(name: "TDMPersistenceTests", dependencies: ["TDMPersistence"])
    ]
)
