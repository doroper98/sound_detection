// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StereoCore",
    products: [.library(name: "StereoCore", targets: ["StereoCore"])],
    targets: [
        .target(name: "StereoCore"),
        .testTarget(name: "StereoCoreTests", dependencies: ["StereoCore"])
    ]
)
