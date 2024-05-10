import XCTest
import SQLiteNIO
import Logging
import NIOCore
import NIOPosix
import NIOFoundationCompat

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

final class SQLiteNIOTests: XCTestCase {
    func testBasicConnection() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT sqlite_version()")

            XCTAssertEqual(rows.count, 1)
            await XCTAssertNoThrowAsync(try await conn.query("PRAGMA compile_options"))
        }
    }
    
    func testConnectionClosedThreadPool() async throws {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        try await threadPool.shutdownGracefully()
        
        // This should error, but not create a leaking promise fatal error
        await XCTAssertThrowsErrorAsync(try await SQLiteConnection.open(storage: .memory, threadPool: threadPool, on: MultiThreadedEventLoopGroup.singleton.any()))
    }

    func testZeroLengthBlob() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT zeroblob(0) as zblob")
        
            XCTAssertEqual(rows.count, 1)
        }
    }

    func testDateFormat() async throws {
        try await withOpenedConnection { conn in
            XCTAssertEqual(Date(sqliteData: .text("2023-03-10"))?.timeIntervalSince1970, 1678406400)
            
            let rows = try await conn.query("SELECT CURRENT_DATE")
            XCTAssertNotNil(rows.first?.column("CURRENT_DATE").flatMap(Date.init(sqliteData:)))
        }
    }
    
    func testDateTimeFormat() async throws {
        try await withOpenedConnection { conn in
            XCTAssertEqual(Date(sqliteData: .text("2023-03-10 23:54:27"))?.timeIntervalSince1970, 1678492467)
            
            let rows = try await conn.query("SELECT CURRENT_TIMESTAMP")
            XCTAssertNotNil(rows.first?.column("CURRENT_TIMESTAMP").flatMap(Date.init(sqliteData:)))
        }
    }
    
    func testTimestampStorage() async throws {
        try await withOpenedConnection { conn in
            let date = Date()
            let rows = try await conn.query("SELECT ? as date", [date.sqliteData!])
            XCTAssertEqual(rows.first?.column("date"), .float(date.timeIntervalSince1970))
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.description, date.description)
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:)), date)
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
        }
    }

    func testTimestampStorageRoundToMicroseconds() async throws {
        try await withOpenedConnection { conn in
           // Test value that when read back out of sqlite results in 7 decimal places that we need to round to microseconds
            let date = Date(timeIntervalSinceReferenceDate: 689658914.293192)
            let rows = try await conn.query("SELECT ? as date", [date.sqliteData!])
            XCTAssertEqual(rows.first?.column("date"), .float(date.timeIntervalSince1970))
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.description, date.description)
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:)), date)
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
        }
    }

    func testDateRoundToMicroseconds() throws {
        let secondsSinceUnixEpoch = 1667950774.6214828
        let secondsSinceSwiftReference = 689643574.621483
        let timestamp = SQLiteData.float(secondsSinceUnixEpoch)
        let date = try XCTUnwrap(Date(sqliteData: timestamp))
        XCTAssertEqual(date.timeIntervalSince1970, secondsSinceUnixEpoch)
        XCTAssertEqual(date.timeIntervalSinceReferenceDate, secondsSinceSwiftReference)
        XCTAssertEqual(date.sqliteData, .float(secondsSinceUnixEpoch))
    }

    func testTimestampStorageInDateColumnIntegralValue() async throws {
        try await withOpenedConnection { conn in
            let date = Date(timeIntervalSince1970: 42)
            // This is how a column of type .date is crated when using Vapor’s
            // scheme table creation.
            _ = try await conn.query(#"CREATE TABLE "test" ("date" DATE NOT NULL)"#)
            _ = try await conn.query(#"INSERT INTO test (date) VALUES (?)"#, [date.sqliteData!])
            let rows = try await conn.query("SELECT * FROM test")
            
            XCTAssertTrue(rows.first?.column("date") == .float(date.timeIntervalSince1970) || rows.first?.column("date") == .integer(Int(date.timeIntervalSince1970)))
            XCTAssertEqual(rows.first?.column("date").flatMap(Date.init(sqliteData:))?.description, date.description)
        }
    }

    func testDuplicateColumnName() async throws {
        try await withOpenedConnection { conn in
            let rows = try await conn.query("SELECT 1 as foo, 2 as foo")
            let row0 = try XCTUnwrap(rows.first)
            var i = 0
            for column in row0.columns {
                XCTAssertEqual(column.name, "foo")
                i += column.data.integer ?? 0
            }
            XCTAssertEqual(i, 3)
            XCTAssertEqual(row0.column("foo")?.integer, 1)
            XCTAssertEqual(row0.columns.filter { $0.name == "foo" }.dropFirst(0).first?.data.integer, 1)
            XCTAssertEqual(row0.columns.filter { $0.name == "foo" }.dropFirst(1).first?.data.integer, 2)
        }
    }

	func testCustomAggregate() async throws {
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
            XCTAssertEqual(rows.first?.column("total_score")?.integer, 12)
        }
	}

	func testDatabaseFunction() async throws {
        try await withOpenedConnection { conn in
            let function = SQLiteCustomFunction("my_custom_function", argumentCount: 1, pure: true) { args in
                Int(args[0].integer! * 3)
            }

            _ = try await conn.install(customFunction: function)
            let rows = try await conn.query("SELECT my_custom_function(2) as my_value")
            XCTAssertEqual(rows.first?.column("my_value")?.integer, 6)
        }
	}

    func testSingletonEventLoopOpen() async throws {
        var conn: SQLiteConnection? = nil
        await XCTAssertNoThrowAsync(conn = try await SQLiteConnection.open(storage: .memory).get())
        try await conn?.close().get()
    }
    
    func testSerializedConnectionAccess() async throws {
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

    override class func setUp() {
        XCTAssert(isLoggingConfigured)
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
