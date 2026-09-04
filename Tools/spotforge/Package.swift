// swift-tools-version: 6.0
import PackageDescription

// `SpotForgeKit` holds the pipeline and `spotforge` is a thin CLI over it: an
// executable target cannot be imported by a test target, and the pipeline is
// exactly the part that has to be tested offline against recorded fixtures.
let package = Package(
    name: "spotforge",
    // macOS 15, not 14: `HTTPClient` and two test helpers use
    // `Synchronization.Mutex`, which is macOS 15+. Declaring .v14 while using
    // it compiled only because CI builds this package on Linux, where
    // `platforms:` is ignored — it failed on the first real macOS build.
    platforms: [.macOS(.v15)],
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
