// swift-tools-version: 6.0
import PackageDescription

// `Tools/spotforge` links this package and builds it for macOS (its own
// Package.swift declares .macOS(.v15)), but that floor does not propagate
// into a dependency's own compilation — each package's `platforms:` governs
// itself. With no .macOS entry here, SwiftPM fell back to an old implicit
// default that predates JSONEncoder's `withoutEscapingSlashes` (macOS
// 10.15+), which BundleCoding.encoder() uses — a real build failure the
// first time this ran on a Mac, invisible on Linux CI since `platforms:` is
// ignored there. .v14 is enough for this package — nothing here needs
// anything newer — and it does not have to match spotforge's own floor.
let package = Package(
    name: "TDMSpots",
    platforms: [.iOS(.v18), .macOS(.v14)],
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
