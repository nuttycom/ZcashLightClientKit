// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ZcashLightClientKit",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_12)
    ],
    products: [
        .library(
            name: "ZcashLightClientKit",
            targets: ["ZcashLightClientKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.13.0"),
        .package(url: "https://github.com/zcash-hackworks/zcash-light-client-ffi.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "ZcashLightClientKit",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "libzcashlc", package: "libzcashlc"),
            ],
            exclude: [
                "Service/ProtoBuf/proto/compact_formats.proto",
                "Service/ProtoBuf/proto/service.proto",
                "Stencil"
            ]
        ),
        .target(
            name: "TestUtils",
            dependencies: ["ZcashLightClientKit"],
            path: "Tests/TestUtils",
            exclude: [
                "proto/darkside.proto"
            ],
            resources: [
                .copy("test_data.db"),
                .copy("cache.db"),
                .copy("ZcashSdk_Data.db"),
            ]
        ),
        .testTarget(
            name: "OfflineTests",
            dependencies: ["ZcashLightClientKit", "TestUtils"]
        ),
        .testTarget(
            name: "NetworkTests",
            dependencies: ["ZcashLightClientKit", "TestUtils"]
        ),
        .testTarget(
            name: "DarksideTests",
            dependencies: ["ZcashLightClientKit", "TestUtils"]
        )
    ]
)
