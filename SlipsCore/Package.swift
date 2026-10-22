// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlipsCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SlipsCore", targets: ["SlipsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "SlipsCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "SlipsCoreTests",
            dependencies: ["SlipsCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
