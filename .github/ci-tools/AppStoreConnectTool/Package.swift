// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AppStoreConnectTool",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "app-store-connect-tool", targets: ["AppStoreConnectTool"]),
        .library(name: "ASCReleaseCore", targets: ["ASCReleaseCore"]),
    ],
    targets: [
        .target(name: "ASCReleaseCore"),
        .executableTarget(
            name: "AppStoreConnectTool",
            dependencies: ["ASCReleaseCore"]
        ),
        .testTarget(
            name: "ASCReleaseCoreTests",
            dependencies: ["ASCReleaseCore"]
        ),
    ]
)
