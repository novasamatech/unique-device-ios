// swift-tools-version: 5.11
import PackageDescription

// MARK: - Config main

let package = Package(
    name: "UniqueDevice",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "UniqueDevice", targets: ["UniqueDevice"])
    ],
    dependencies: [
        .package(url: "https://github.com/novasamatech/Operation-iOS", from: "2.2.0"),
        .package(url: "https://github.com/novasamatech/Keystore-iOS", from: "1.0.1"),
        .package(url: "https://github.com/novasamatech/logger-ios", from: "0.0.1")
    ],
    targets: [
        .target(
            name: "UniqueDevice",
            dependencies: [
                "Operation-iOS",
                "Keystore-iOS",
                .product(name: "SDKLogger", package: "logger-ios")
            ],
            path: "Sources"
        )
    ]
)
