// swift-tools-version: 6.0
import PackageDescription

// Deliberately no `platforms:` — this package builds and tests on Linux.
let package = Package(
    name: "TDMCore",
    products: [
        .library(name: "TDMCore", targets: ["TDMCore"])
    ],
    targets: [
        .target(name: "TDMCore"),
        .testTarget(name: "TDMCoreTests", dependencies: ["TDMCore"])
    ]
)
