// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StereoCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "StereoCore", targets: ["StereoCore"]),
        .executable(name: "foa-replay", targets: ["FOAReplayCLI"])
    ],
    targets: [
        .target(name: "StereoCore"),
        .executableTarget(name: "FOAReplayCLI", dependencies: ["StereoCore"]),
        .testTarget(name: "StereoCoreTests", dependencies: ["StereoCore"])
    ]
)
