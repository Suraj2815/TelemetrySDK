// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TelemetrySDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "TelemetrySDK",
            targets: ["TelemetrySDK"]
        ),
    ],
    targets: [
        .target(
            name: "TelemetrySDK",
            path: "Sources/TelemetrySDK",
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-disable-availability-checking",
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-strict-concurrency=minimal"
                ])
            ]
                
                
        )
    ]
)
