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
        // This target is only used to add our vendor prefix and is added and removed automatically.
        // See: scripts/vendor-sqlite3.swift
        /* VENDOR_START
        .library(name: "CSQLite", type: .static, targets: ["CSQLite"]),
        VENDOR_END */
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "CSQLite", cSettings: [
            // Derived from sqlite3 version 3.43.0
            .define("SQLITE_ENABLE_COLUMN_METADATA"),
            .define("SQLITE_ENABLE_DBSTAT_VTAB"),
            .define("SQLITE_ENABLE_FTS3"),
            .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
            .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
            .define("SQLITE_ENABLE_FTS4"),
            .define("SQLITE_ENABLE_FTS5"),
            .define("SQLITE_ENABLE_JSON1"),
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
