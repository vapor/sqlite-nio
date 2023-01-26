// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "sqlite-nio",
    platforms: [
       .macOS(.v10_15),
       .iOS(.v13)
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
        .target(name: "SQLiteNIO", dependencies: [
            .target(name: "CSQLite"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "NIO", package: "swift-nio"),
        ]),
        .testTarget(name: "SQLiteNIOTests", dependencies: ["SQLiteNIO"]),
    ]
)

// Derived from sqlite3 version 3.37.2 2022-01-06 13:25:41 872ba256cbf61d9290b571c0e6d82a20c224ca3ad82971edc46b29818d5dalt1
// compiled with gcc-11.3.0
// on platform Ubuntu 22.04.1 LTS (Jammy Jellyfish)
var cSQLiteSettings: [CSetting] = [
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
    .define("SQLITE_ENABLE_UPDATE_DELETE_LIMIT"),
    .define("SQLITE_HAVE_ISNAN"),
    .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
    .define("SQLITE_OMIT_LOAD_EXTENSION"),
    .define("SQLITE_OMIT_LOOKASIDE"),
    .define("SQLITE_SECURE_DELETE"),
    .define("SQLITE_SYSTEM_MALLOC"),
    .define("SQLITE_THREADSAFE", to: "2"),
    .define("SQLITE_USE_URI"),
]

#if os(macOS)
// Derived from sqlite3 version 3.37.0 2021-12-09 01:34:53 9ff244ce0739f8ee52a3e9671adb4ee54c83c640b02e3f9d185fd2f9a179aapl
// compiled with clang-13.1.6
// on platform macOS 12.6 (21G115)
cSQLiteSettings.append(contentsOf: [
    .define("SQLITE_DEFAULT_CACHE_SIZE", to: "2000"),
    .define("SQLITE_DEFAULT_JOURNAL_SIZE_LIMIT", to: "32768"),
    .define("SQLITE_DEFAULT_LOOKASIDE", to: "1200,102"),
    .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
    .define("SQLITE_DEFAULT_MMAP_SIZE", to: "0"),
    .define("SQLITE_DEFAULT_PAGE_SIZE", to: "4096"),
    .define("SQLITE_DEFAULT_PCACHE_INITSZ", to: "20"),
    .define("SQLITE_DEFAULT_SYNCHRONOUS", to: "2"),
    .define("SQLITE_DEFAULT_WAL_AUTOCHECKPOINT", to: "1000"),
    .define("SQLITE_DEFAULT_WAL_SYNCHRONOUS", to: "1"),
    .define("SQLITE_DEFAULT_WORKER_THREADS", to: "0"),
    .define("SQLITE_ENABLE_LOCKING_STYLE", to: "1"),
    .define("SQLITE_MAX_MMAP_SIZE", to: "1073741824"),
])
#endif

// In Xcode  on macOS (and possibly on other platforms), sqlite.3 emits several harmless warnings that
// we suppress to avoid cluttering the build.
cSQLiteSettings.append(
    .unsafeFlags([
        "-Wno-shorten-64-to-32",
        "-Wno-ambiguous-macro",
    ])
)

package.targets.append(
    .target(
        name: "CSQLite",
        dependencies: [],
        cSettings: cSQLiteSettings
    )
)
