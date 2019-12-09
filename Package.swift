// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "sqlite-nio",
    platforms: [
       .macOS(.v10_14)
    ],
    products: [
        .library(name: "SQLiteNIO", targets: ["SQLiteNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"])
            ]
        ),
        .target(name: "SQLiteNIO", dependencies: ["CSQLite", "Logging", "NIO"]),
        .testTarget(name: "SQLiteNIOTests", dependencies: ["SQLiteNIO"]),
    ]
)
