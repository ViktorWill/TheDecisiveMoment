// swift-tools-version: 6.0
import PackageDescription

// Deliberately no `platforms:` — this package builds and tests on Linux.
let package = Package(
    name: "TDMLight",
    products: [
        .library(name: "TDMLight", targets: ["TDMLight"])
    ],
    dependencies: [
        .package(path: "../TDMCore")
    ],
    targets: [
        .target(name: "TDMLight", dependencies: [.product(name: "TDMCore", package: "TDMCore")]),
        .testTarget(name: "TDMLightTests", dependencies: ["TDMLight"])
    ]
)
