#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import NIOCore
import NIOPosix
#if canImport(FoundationEssentials)
import NIOFoundationEssentialsCompat
#else
import NIOFoundationCompat
#endif
import SQLiteNIO
import Testing

/// Run the provided closure with an opened ``SQLiteConnection`` using an in-memory database and the singleton thread
/// pool and event loop, guaranteeing that the connection is correctly cleaned up afterwards regardless of errors.
func withOpenedConnection<T>(
    _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
) async throws -> T {
    let connection = try await SQLiteConnection.open(storage: .memory)

    do {
        let result = try await closure(connection)
        try await connection.close()

        return result
    } catch {
        try? await connection.close()
        throw error
    }

}

@Suite("Base SQLiteNIO tests")
struct SQLiteNIOTests {
    @Test
    func basicConnection() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT sqlite_version()")

            #expect(rows.count == 1)
            await #expect(throws: Never.self) { try await conn.query("PRAGMA compile_options") }
        }
    }

    @Test
    func connectionClosedThreadPool() async throws {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        try await threadPool.shutdownGracefully()

        // This should error, but not create a leaking promise fatal error
        await #expect(throws: (any Error).self) { try await SQLiteConnection.open(storage: .memory, threadPool: threadPool, on: MultiThreadedEventLoopGroup.singleton.any()) }
    }

    @Test
    func zeroLengthBlob() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT zeroblob(0) as zblob")

            #expect(rows.count == 1)
        }
    }

    @Test
    func dateFormat() async throws {
        try await withOpenedConnection { conn in
            #expect(Date(sqliteData: .text("2023-03-10"))?.timeIntervalSince1970 == 1678406400)

            let rows = try await conn.query("SELECT CURRENT_DATE")
            #expect(rows.first?.column("CURRENT_DATE").flatMap(Date.init(sqliteData:)) != nil)
        }
    }

    @Test
    func dateTimeFormat() async throws {
        try await withOpenedConnection { conn in
            #expect(Date(sqliteData: .text("2023-03-10 23:54:27"))?.timeIntervalSince1970 == 1678492467)

            let rows = try await conn.query("SELECT CURRENT_TIMESTAMP")
            #expect(rows.first?.column("CURRENT_TIMESTAMP").flatMap(Date.init(sqliteData:)) != nil)
        }
    }

    @Test
    func timestampStorage() async throws {
        try await withOpenedConnection { conn in
            // When the value is read back out of sqlite, it will have only microsecond precision, make sure we use a Date with
            // the same limit or else the test will fail.
            let date = Date(timeIntervalSinceReferenceDate: 689658914.293192)
            let rows = try await conn.query("SELECT ? as date", [date.sqliteData!])
            #expect(rows.first?.column("date") == .float(date.timeIntervalSince1970))
            #expect(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.description == date.description)
            #expect(rows.first?.column("date").flatMap(Date.init(sqliteData:)) == date)
            #expect(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.timeIntervalSinceReferenceDate == date.timeIntervalSinceReferenceDate)
        }
    }

    @Test
    func dateRoundToMicroseconds() throws {
        let secondsSinceUnixEpoch = 1667950774.6214828
        let secondsSinceSwiftReference = 689643574.621483
        let timestamp = SQLiteData.float(secondsSinceUnixEpoch)
        let date = try #require(Date(sqliteData: timestamp))
        #expect(date.timeIntervalSince1970 == secondsSinceUnixEpoch)
        #expect(date.timeIntervalSinceReferenceDate == secondsSinceSwiftReference)
        #expect(date.sqliteData == .float(secondsSinceUnixEpoch))
    }

    @Test
    func timestampStorageInDateColumnIntegralValue() async throws {
        try await withOpenedConnection { conn in
            let date = Date(timeIntervalSince1970: 42)
            // This is how a column of type .date is crated when using Vapor’s
            // scheme table creation.
            _ = try await conn.query(#"CREATE TABLE "test" ("date" DATE NOT NULL)"#)
            _ = try await conn.query(#"INSERT INTO test (date) VALUES (?)"#, [date.sqliteData!])
            let rows = try await conn.query("SELECT * FROM test")

            #expect(rows.first?.column("date") == .float(date.timeIntervalSince1970) || rows.first?.column("date") == .integer(Int(date.timeIntervalSince1970)))
            #expect(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.description == date.description)
        }
    }

    @Test
    func duplicateColumnName() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT 1 as foo, 2 as foo")
            let row0 = try #require(rows.first)
            var i = 0
            for column in row0.columns {
                #expect(column.name == "foo")
                i += column.data.integer ?? 0
            }
            #expect(i == 3)
            #expect(row0.column("foo")?.integer == 1)
            #expect(row0.columns.filter { $0.name == "foo" }.dropFirst(0).first?.data.integer == 1)
            #expect(row0.columns.filter { $0.name == "foo" }.dropFirst(1).first?.data.integer == 2)
        }
    }

    @Test
    func customAggregate() async throws {
        try await withOpenedConnection { conn in
            _ = try await conn.query(#"CREATE TABLE "scores" ("score" INTEGER NOT NULL)"#)
            _ = try await conn.query(#"INSERT INTO scores (score) VALUES (?), (?), (?)"#, [.integer(3), .integer(4), .integer(5)])

            struct MyAggregate: SQLiteCustomAggregate {
                var sum: Int = 0
                mutating func step(_ values: [SQLiteData]) throws {
                    self.sum += (values.first?.integer ?? 0)
                }

                func finalize() throws -> (any SQLiteDataConvertible)? {
                    self.sum
                }
            }

            let function = SQLiteCustomFunction("my_sum", argumentCount: 1, pure: true, aggregate: MyAggregate.self)
            try await conn.install(customFunction: function)

            let rows = try await conn.query("SELECT my_sum(score) as total_score FROM scores")
            #expect(rows.first?.column("total_score")?.integer == 12)
        }
    }

    @Test
    func databaseFunction() async throws {
        try await withOpenedConnection { conn in
            let function = SQLiteCustomFunction("my_custom_function", argumentCount: 1, pure: true) { args in
                Int(args[0].integer! * 3)
            }

            _ = try await conn.install(customFunction: function)
            let rows = try await conn.query("SELECT my_custom_function(2) as my_value")
            #expect(rows.first?.column("my_value")?.integer == 6)
        }
    }

    @Test
    func singletonEventLoopOpen() async throws {
        var conn: SQLiteConnection? = nil
        await #expect(throws: Never.self) { conn = try await SQLiteConnection.open(storage: .memory).get() }
        try await conn?.close().get()
    }

    @Test
    func serializedConnectionAccess() async throws {
        /// Although this test has no assertions, it does serve a useful purpose: when run with Thread Sanitizer
        /// enabed, it validates that we are using SQLite in "serialized" mode (e.g. it is safe to use a single
        /// connection simultaneously from multiple threads) rather than single- or multi-threaded mode.
        try await withOpenedConnection { conn in
            let t1 = Task {
                for _ in 0 ..< 100 {
                    _ = try await conn.query("SELECT random()", [], { _ in })
                }
            }
            let t2 = Task {
                for _ in 0 ..< 100 {
                    _ = try await conn.query("SELECT random()", [], { _ in })
                }
            }

            try await t1.value
            try await t2.value
        }
    }

    init() {
        #expect(isLoggingConfigured)
    }
}

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = env("LOG_LEVEL").flatMap { .init(rawValue: $0) } ?? .info
        return handler
    }
    return true
}()
