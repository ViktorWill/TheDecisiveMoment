// swift-tools-version: 6.0
import PackageDescription

// Tools/spotforge links this package directly and builds it for macOS (its
// own Package.swift declares .macOS(.v14)); that floor does not propagate
// into a dependency's own compilation, so this needs its own entry too — see
// the identical, already-hit bug in Packages/TDMSpots/Package.swift. Nothing
// here uses an availability-gated API yet, but the risk is the same and this
// package is confirmed in that same macOS build graph.
let package = Package(
    name: "TDMCore",
    platforms: [.iOS(.v13), .macOS(.v14)],
    products: [
        .library(name: "TDMCore", targets: ["TDMCore"])
    ],
    targets: [
        .target(name: "TDMCore"),
        .testTarget(name: "TDMCoreTests", dependencies: ["TDMCore"])
    ]
)
