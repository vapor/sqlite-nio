// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "nio-sqlite",
    products: [
        .library(name: "NIOSQLite", targets: ["NIOSQLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["sqlite"]),
                .brew(["sqlite3"])
            ]
        ),
        .target(name: "NIOSQLite", dependencies: ["CSQLite", "NIO"]),
        .testTarget(name: "NIOSQLiteTests", dependencies: ["NIOSQLite"]),
    ]
)
