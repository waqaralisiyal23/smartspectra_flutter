// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "smartspectra_flutter",
    platforms: [
        // SmartSpectra SDK requirement.
        .iOS("17.0")
    ],
    products: [
        .library(name: "smartspectra-flutter", targets: ["smartspectra_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/Presage-Security/SmartSpectra-Swift.git", exact: "3.4.0"),
    ],
    targets: [
        .target(
            name: "smartspectra_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "SmartSpectra", package: "SmartSpectra-Swift"),
            ]
        )
    ]
)
