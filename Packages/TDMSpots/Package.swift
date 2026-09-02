// swift-tools-version: 6.0
import PackageDescription

// Deliberately no `platforms:` — this package builds and tests on Linux.
let package = Package(
    name: "TDMSpots",
    products: [
        .library(name: "TDMSpots", targets: ["TDMSpots"])
    ],
    dependencies: [
        .package(path: "../TDMCore")
    ],
    targets: [
        .target(name: "TDMSpots", dependencies: [.product(name: "TDMCore", package: "TDMCore")]),
        .testTarget(name: "TDMSpotsTests", dependencies: ["TDMSpots"])
    ]
)
