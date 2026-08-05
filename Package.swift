// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PostgresConnector",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PostgresConnector",
            targets: ["PostgresConnector"]
        ),
        .executable(
            name: "pgctest",
            targets: [
                "PostgresConnectorTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.11.4"),
        .package(url: "https://github.com/leviouwendijk/Milieu.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/PSQL.git", branch: "master"),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        )
    ],
    targets: [
        .target(
            name: "PostgresConnector",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "Milieu", package: "Milieu"),
                .product(name: "PSQL", package: "PSQL"),
            ],
        ),
        .executableTarget(
            name: "PostgresConnectorTestFlows",
            dependencies: [
                "PostgresConnector",
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
                .product(
                    name: "Milieu",
                    package: "Milieu"
                )
            ]
        ),
    ]
)
