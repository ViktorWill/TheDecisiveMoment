// swift-tools-version: 6.0
import PackageDescription

// No `platforms:` of its own, but it still builds and tests on Linux since
// `platforms:` is ignored there — the iOS minimum here matches TDMCore's,
// which it depends on.
let package = Package(
    name: "TDMLight",
    platforms: [.iOS(.v13)],
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
