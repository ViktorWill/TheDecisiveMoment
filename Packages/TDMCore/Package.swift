// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TDMCore",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "TDMCore", targets: ["TDMCore"])
    ],
    targets: [
        .target(name: "TDMCore"),
        .testTarget(name: "TDMCoreTests", dependencies: ["TDMCore"])
    ]
)
