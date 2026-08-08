// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ApexGauge",
    platforms: [.iOS(.v17), .watchOS(.v11)],
    products: [
        .library(name: "ApexGaugeCore", targets: ["ApexGaugeCore"]),
    ],
    targets: [
        // Shared core: provider fetchers (vendored from CodexBar's CodexBarCore,
        // Foundation-only) + the cross-process snapshot model exchanged between
        // the iPhone app, the watch app, and the complication extension.
        .target(name: "ApexGaugeCore"),
        .testTarget(name: "ApexGaugeCoreTests", dependencies: ["ApexGaugeCore"]),
    ]
)
