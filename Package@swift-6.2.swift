// swift-tools-version:6.2
import PackageDescription

// Trait to enable SQLCipher-specific code paths.
let SQLCipherTrait = "SQLCipher"

let package = Package(
    name: "sqlite-nio",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "SQLiteNIO", targets: ["SQLiteNIO"])
    ],
    traits: [
        .trait(
            name: SQLCipherTrait,
            description: "Enable SQLCipher encryption support for encrypted databases"
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        // Binary OpenSSL for Apple OSes (static, XCFramework)
        .package(url: "https://github.com/krzyzanowskim/OpenSSL-Package.git", from: "3.3.3000")
    ],
    targets: [
        .plugin(
            name: "VendorSQLite",
            capability: .command(
                intent: .custom(verb: "vendor-sqlite", description: "Vendor SQLite"),
                permissions: [
                    .allowNetworkConnections(scope: .all(ports: [443]), reason: "Retrieve the latest build of SQLite"),
                    .writeToPackageDirectory(reason: "Update the vendored SQLite files"),
                ]
            ),
            exclude: ["001-warnings-and-data-race.patch"]
        ),
        .target(
            name: "CSQLite",
            cSettings: sqliteCSettings
        ),
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [
                .apt(["libssl-dev"]),      // Debian & Ubuntu
                .yum(["openssl-devel"]),   // AmazonLinux/RHEL
            ]
        ),
        .target(
            name: "CSQLCipher",
            dependencies: [
                // Linux: link against the system library
                .target(name: "COpenSSL", condition: .when(platforms: [.linux])),
                
                // Apple OSes: link against the vendored binary product
                .product(name: "OpenSSL",
                         package: "OpenSSL-Package",
                         condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS]))
            ],
            cSettings: sqliteCSettings
        ),
        .target(
            name: "SQLiteNIO",
            dependencies: [
                .target(name: "CSQLite", condition: .when(traits: [])),
                .target(name: "CSQLCipher", condition: .when(traits: [SQLCipherTrait])),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SQLiteNIOTests",
            dependencies: [
                .target(name: "SQLiteNIO"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ConciseMagicFile"),
    .enableUpcomingFeature("ForwardTrailingClosures"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .define(SQLCipherTrait, .when(traits: [SQLCipherTrait]))
] }

var sqliteCSettings: [CSetting] { [
    // Derived from sqlite3 version 3.43.0
    .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
    .define("SQLITE_DISABLE_PAGECACHE_OVERFLOW_STATS"),
    .define("SQLITE_DQS", to: "0"),
    .define("SQLITE_ENABLE_API_ARMOR", .when(configuration: .debug)),
    .define("SQLITE_ENABLE_COLUMN_METADATA"),
    .define("SQLITE_ENABLE_DBSTAT_VTAB"),
    .define("SQLITE_ENABLE_FTS3"),
    .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
    .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
    .define("SQLITE_ENABLE_FTS4"),
    .define("SQLITE_ENABLE_FTS5"),
    .define("SQLITE_ENABLE_NULL_TRIM"),
    .define("SQLITE_ENABLE_RTREE"),
    .define("SQLITE_ENABLE_SESSION"),
    .define("SQLITE_ENABLE_STMTVTAB"),
    .define("SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION"),
    .define("SQLITE_ENABLE_UNLOCK_NOTIFY"),
    .define("SQLITE_MAX_VARIABLE_NUMBER", to: "250000"),
    .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
    .define("SQLITE_OMIT_AUTHORIZATION"),
    .define("SQLITE_OMIT_COMPLETE"),
    .define("SQLITE_OMIT_DEPRECATED"),
    .define("SQLITE_OMIT_DESERIALIZE"),
    .define("SQLITE_OMIT_GET_TABLE"),
    .define("SQLITE_OMIT_LOAD_EXTENSION"),
    .define("SQLITE_OMIT_PROGRESS_CALLBACK"),
    .define("SQLITE_OMIT_SHARED_CACHE"),
    .define("SQLITE_OMIT_TCL_VARIABLE"),
    .define("SQLITE_OMIT_TRACE"),
    .define("SQLITE_SECURE_DELETE"),
    .define("SQLITE_THREADSAFE", to: "1"),
    .define("SQLITE_UNTESTABLE"),
    .define("SQLITE_USE_URI"),
    
    // SQLCipher
    .define("SQLITE_HAS_CODEC", .when(traits: [SQLCipherTrait])),
    .define("SQLITE_TEMP_STORE", to: "2", .when(traits: [SQLCipherTrait])),
    .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init", .when(traits: [SQLCipherTrait])),
    .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown", .when(traits: [SQLCipherTrait])),
    .define("SQLCIPHER_CRYPTO_OPENSSL", .when(traits: [SQLCipherTrait])),
] }
