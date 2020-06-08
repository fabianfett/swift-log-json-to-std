// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-log-json-to-std",
    products: [
        .library(
            name: "LoggingJSONToSTD",
            targets: ["LoggingJSONToSTD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.2.0"))
    ],
    targets: [
        .target(name: "LoggingJSONToSTD", dependencies: [
            .product(name: "Logging", package: "swift-log"),
        ]),
        .testTarget(name: "LoggingJSONToSTDTests", dependencies: [
            .byName(name: "LoggingJSONToSTD"),
        ]),
    ]
)
