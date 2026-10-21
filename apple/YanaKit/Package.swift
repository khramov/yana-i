// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "YanaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YanaDomain", targets: ["YanaDomain"]),
        .library(name: "YanaSync", targets: ["YanaSync"]),
        .library(name: "YanaMarketData", targets: ["YanaMarketData"]),
    ],
    targets: [
        .target(name: "YanaDomain"),
        .target(name: "YanaSync", dependencies: ["YanaDomain"]),
        .target(name: "YanaMarketData", dependencies: ["YanaDomain"]),
        .testTarget(name: "YanaDomainTests", dependencies: ["YanaDomain"], resources: [.copy("Fixtures")]),
        .testTarget(name: "YanaSyncTests", dependencies: ["YanaSync"], resources: [.copy("Golden")]),
        .testTarget(name: "YanaMarketDataTests", dependencies: ["YanaMarketData"], resources: [.copy("Fixtures")]),
    ]
)
