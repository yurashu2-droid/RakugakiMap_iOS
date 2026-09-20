// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MapGrapherCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MapGrapherCore", targets: ["MapGrapherCore"]),
    ],
    targets: [
        .target(name: "MapGrapherCore"),
        .testTarget(name: "MapGrapherCoreTests", dependencies: ["MapGrapherCore"]),
    ],
    swiftLanguageModes: [.v6]
)
