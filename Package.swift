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

#if os(macOS)
// Derived from sqlite3 version 3.37.0 2021-12-09 01:34:53 9ff244ce0739f8ee52a3e9671adb4ee54c83c640b02e3f9d185fd2f9a179aapl
// compiled with clang-13.1.6
// on platform macOS 12.6 (21G115)
let cSQLiteSettings: [CSetting] = [
    .define("SQLITE_ATOMIC_INTRINSICS", to: "1"),
    .define("SQLITE_DEFAULT_CACHE_SIZE", to: "2000"),
    .define("SQLITE_DEFAULT_FILE_FORMAT", to: "4"),
    .define("SQLITE_DEFAULT_JOURNAL_SIZE_LIMIT", to: "32768"),
    .define("SQLITE_DEFAULT_LOOKASIDE", to: "1200,102"),
    .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
    .define("SQLITE_DEFAULT_MMAP_SIZE", to: "0"),
    .define("SQLITE_DEFAULT_PAGE_SIZE", to: "4096"),
    .define("SQLITE_DEFAULT_PCACHE_INITSZ", to: "20"),
    .define("SQLITE_DEFAULT_SECTOR_SIZE", to: "4096"),
    .define("SQLITE_DEFAULT_SYNCHRONOUS", to: "2"),
    .define("SQLITE_DEFAULT_WAL_AUTOCHECKPOINT", to: "1000"),
    .define("SQLITE_DEFAULT_WAL_SYNCHRONOUS", to: "1"),
    .define("SQLITE_DEFAULT_WORKER_THREADS", to: "0"),
    .define("SQLITE_ENABLE_LOCKING_STYLE", to: "1"),
    .define("SQLITE_MALLOC_SOFT_LIMIT", to: "1024"),
    .define("SQLITE_MAX_ATTACHED", to: "10"),
    .define("SQLITE_MAX_COLUMN", to: "2000"),
    .define("SQLITE_MAX_COMPOUND_SELECT", to: "500"),
    .define("SQLITE_MAX_DEFAULT_PAGE_SIZE", to: "8192"),
    .define("SQLITE_MAX_EXPR_DEPTH", to: "1000"),
    .define("SQLITE_MAX_FUNCTION_ARG", to: "127"),
    .define("SQLITE_MAX_LENGTH", to: "2147483645"),
    .define("SQLITE_MAX_LIKE_PATTERN_LENGTH", to: "50000"),
    .define("SQLITE_MAX_MMAP_SIZE", to: "1073741824"),
    .define("SQLITE_MAX_PAGE_COUNT", to: "1073741823"),
    .define("SQLITE_MAX_PAGE_SIZE", to: "65536"),
    .define("SQLITE_MAX_SQL_LENGTH", to: "1000000000"),
    .define("SQLITE_MAX_TRIGGER_DEPTH", to: "1000"),
    .define("SQLITE_MAX_VARIABLE_NUMBER", to: "500000"),
    .define("SQLITE_MAX_VDBE_OP", to: "250000000"),
    .define("SQLITE_MAX_WORKER_THREADS", to: "8"),
    .define("SQLITE_STMTJRNL_SPILL", to: "131072"),
    .define("SQLITE_TEMP_STORE", to: "1"),
    .define("SQLITE_THREADSAFE", to: "2"),
    .define("SQLITE_BUG_COMPATIBLE_20160819"),
    .define("SQLITE_DEFAULT_AUTOVACUUM"),
    .define("SQLITE_DEFAULT_CKPTFULLFSYNC"),
    .define("SQLITE_DEFAULT_RECURSIVE_TRIGGERS"),
    .define("SQLITE_ENABLE_API_ARMOR"),
    .define("SQLITE_ENABLE_BYTECODE_VTAB"),
    .define("SQLITE_ENABLE_COLUMN_METADATA"),
    .define("SQLITE_ENABLE_DBPAGE_VTAB"),
    .define("SQLITE_ENABLE_DBSTAT_VTAB"),
    .define("SQLITE_ENABLE_EXPLAIN_COMMENTS"),
    .define("SQLITE_ENABLE_FTS3"),
    .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
    .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
    .define("SQLITE_ENABLE_FTS4"),
    .define("SQLITE_ENABLE_FTS5"),
    .define("SQLITE_ENABLE_JSON1"),
    .define("SQLITE_ENABLE_NORMALIZE"),
    .define("SQLITE_ENABLE_PREUPDATE_HOOK"),
    .define("SQLITE_ENABLE_RTREE"),
    .define("SQLITE_ENABLE_SESSION"),
    .define("SQLITE_ENABLE_SNAPSHOT"),
    .define("SQLITE_ENABLE_STMT_SCANSTATUS"),
    .define("SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION"),
    .define("SQLITE_ENABLE_UPDATE_DELETE_LIMIT"),
    .define("SQLITE_HAVE_ISNAN"),
    .define("SQLITE_MUTEX_UNFAIR"),
    .define("SQLITE_OMIT_AUTORESET"),
    .define("SQLITE_OMIT_LOAD_EXTENSION"),
    .define("SQLITE_SYSTEM_MALLOC"),
    .define("SQLITE_USE_URI"),
]
#else
// Derived from sqlite3 version 3.31.1 2020-01-27 19:55:54 3bfa9cc97da10598521b342961df8f5f68c7388fa117345eeb516eaa837balt1
// compiled with gcc-9.4.0
// on platform Ubuntu 20.04.5 LTS (Focal Fossa)
let cSQLiteSettings: [CSetting] = [
    .define("SQLITE_MAX_SCHEMA_RETRY", to: "25"),
    .define("SQLITE_MAX_VARIABLE_NUMBER", to: "250000"),
    .define("SQLITE_THREADSAFE", to: "2"),
    .define("SQLITE_ENABLE_COLUMN_METADATA"),
    .define("SQLITE_ENABLE_DBSTAT_VTAB"),
    .define("SQLITE_ENABLE_FTS3"),
    .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
    .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
    .define("SQLITE_ENABLE_FTS4"),
    .define("SQLITE_ENABLE_FTS5"),
    .define("SQLITE_ENABLE_JSON1"),
    .define("SQLITE_ENABLE_LOAD_EXTENSION"),
    .define("SQLITE_ENABLE_PREUPDATE_HOOK"),
    .define("SQLITE_ENABLE_RTREE"),
    .define("SQLITE_ENABLE_SESSION"),
    .define("SQLITE_ENABLE_STMTVTAB"),
    .define("SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION"),
    .define("SQLITE_ENABLE_UNLOCK_NOTIFY"),
    .define("SQLITE_ENABLE_UPDATE_DELETE_LIMIT"),
    .define("SQLITE_HAVE_ISNAN"),
    .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
    .define("SQLITE_OMIT_LOOKASIDE"),
    .define("SQLITE_SECURE_DELETE"),
    .define("SQLITE_SOUNDEX"),
    .define("SQLITE_USE_URI"),
]
#endif

package.targets.append(
    .target(
        name: "CSQLite",
        dependencies: [],
        cSettings: cSQLiteSettings
    )
)
