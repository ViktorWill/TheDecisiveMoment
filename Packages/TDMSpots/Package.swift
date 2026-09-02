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
        // The fixture bundle lives beside the tests rather than inside them:
        // it is the schema's executable definition, referenced from
        // `docs/DATA-BUNDLES.md`, not an implementation detail of one suite.
        .testTarget(
            name: "TDMSpotsTests",
            dependencies: ["TDMSpots"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        )
    ]
)
