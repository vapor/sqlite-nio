// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "sqlite-nio",
    products: [
        .library(name: "SQLiteNIO", targets: ["SQLiteNIO"]),
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
        .target(name: "SQLiteNIO", dependencies: ["CSQLite", "NIO"]),
        .testTarget(name: "SQLiteNIOTests", dependencies: ["SQLiteNIO"]),
    ]
)
