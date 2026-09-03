// swift-tools-version: 6.0
import PackageDescription

// `SpotForgeKit` holds the pipeline and `spotforge` is a thin CLI over it: an
// executable target cannot be imported by a test target, and the pipeline is
// exactly the part that has to be tested offline against recorded fixtures.
let package = Package(
    name: "spotforge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spotforge", targets: ["spotforge"])
    ],
    dependencies: [
        .package(path: "../../Packages/TDMCore"),
        .package(path: "../../Packages/TDMSpots")
    ],
    targets: [
        .target(
            name: "SpotForgeKit",
            dependencies: [
                .product(name: "TDMCore", package: "TDMCore"),
                .product(name: "TDMSpots", package: "TDMSpots")
            ]
        ),
        .executableTarget(name: "spotforge", dependencies: ["SpotForgeKit"]),
        .testTarget(
            name: "SpotForgeKitTests",
            dependencies: ["SpotForgeKit"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        )
    ]
)
