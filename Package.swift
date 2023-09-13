// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "sqlite-nio",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "SQLiteNIO", targets: ["SQLiteNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .plugin(
            name: "VendorSQLite",
            capability: .command(
                intent: .custom(verb: "vendor-sqlite", description: "Vendor SQLite"),
                permissions: [/*.writeToPackageDirectory(reason: "Update the vendored SQLite files")*/]
            ),
            exclude: ["001-warnings-and-data-race.patch"]
        ),
        .target(name: "CSQLite", cSettings: [
            // Derived from sqlite3 version 3.43.0
            .define("SQLITE_DQS", to: "0"),
            .define("SQLITE_ENABLE_API_ARMOR"),
            .define("SQLITE_ENABLE_COLUMN_METADATA"),
            .define("SQLITE_ENABLE_DBSTAT_VTAB"),
            .define("SQLITE_ENABLE_FTS3"),
            .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
            .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
            .define("SQLITE_ENABLE_FTS4"),
            .define("SQLITE_ENABLE_FTS5"),
            .define("SQLITE_ENABLE_MEMORY_MANAGEMENT"),
            .define("SQLITE_ENABLE_PREUPDATE_HOOK"),
            .define("SQLITE_ENABLE_RTREE"),
            .define("SQLITE_ENABLE_SESSION"),
            .define("SQLITE_ENABLE_STMTVTAB"),
            .define("SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION"),
            .define("SQLITE_ENABLE_UNLOCK_NOTIFY"),
            .define("SQLITE_MAX_VARIABLE_NUMBER", to: "250000"),
            .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
            .define("SQLITE_OMIT_DEPRECATED"),
            .define("SQLITE_OMIT_LOAD_EXTENSION"),
            .define("SQLITE_OMIT_SHARED_CACHE"),
            .define("SQLITE_SECURE_DELETE"),
            .define("SQLITE_THREADSAFE", to: "2"),
            .define("SQLITE_USE_URI"),
        ]),
        .target(name: "SQLiteNIO", dependencies: [
            .target(name: "CSQLite"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "NIO", package: "swift-nio"),
        ]),
        .testTarget(name: "SQLiteNIOTests", dependencies: ["SQLiteNIO"]),
    ]
)
