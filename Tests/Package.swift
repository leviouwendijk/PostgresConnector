// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PostgresConnectorTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "pgctest",
            targets: [
                "PostgresConnectorTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Milieu.git", branch: "master"),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "PostgresConnectorTestFlows",
            dependencies: [
                .product(name: "PostgresConnector", package: "PostgresConnector"),
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
