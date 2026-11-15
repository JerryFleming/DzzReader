// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DzzCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "DzzCore", targets: ["DzzCore"]),
    ],
    targets: [
        .target(name: "DzzCore"),
        .testTarget(
            name: "DzzCoreTests",
            dependencies: ["DzzCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
