// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spotforge",
    dependencies: [
        .package(path: "../../Packages/TDMCore")
    ],
    targets: [
        .executableTarget(
            name: "spotforge",
            dependencies: [.product(name: "TDMCore", package: "TDMCore")]
        )
    ]
)
