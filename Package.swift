// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MailFoundation",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MailFoundation",
            targets: ["MailFoundation"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
        .package(url: "https://github.com/migueldeicaza/MimeFoundation", branch: "main")
    ],
    targets: [
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [
                .brew(["openssl@3"]),
                .apt(["libssl-dev"])
            ]
        ),
        .target(
            name: "MailFoundation",
            dependencies: [
                "MimeFoundation",
                .target(name: "COpenSSL", condition: .when(platforms: [.macOS, .linux]))
            ]
        ),
        .testTarget(
            name: "MailFoundationTests",
            dependencies: ["MailFoundation"],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
