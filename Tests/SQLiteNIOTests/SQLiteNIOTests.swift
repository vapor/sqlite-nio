import XCTest
import SQLiteNIO
import Logging

final class SQLiteNIOTests: XCTestCase {
    func testBasicConnection() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        let rows = try conn.query("SELECT sqlite_version()").wait()
        print(rows)
    }

    func testZeroLengthBlob() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        let rows = try conn.query("SELECT zeroblob(0) as zblob").wait()
        print(rows)
    }

    func testTimestampStorage() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        let date = Date()
        let rows = try conn.query("SELECT ? as date", [date.sqliteData!]).wait()
        XCTAssertEqual(rows[0].column("date"), .float(date.timeIntervalSince1970))
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!)?.description, date.description)
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!), date)
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!)?.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
    }

    func testTimestampStorageRoundToMicroseconds() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        // Test value that when read back out of sqlite results in 7 decimal places that we need to round to microseconds
        let date = Date(timeIntervalSinceReferenceDate: 689658914.293192)
        let rows = try conn.query("SELECT ? as date", [date.sqliteData!]).wait()
        XCTAssertEqual(rows[0].column("date"), .float(date.timeIntervalSince1970))
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!)?.description, date.description)
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!), date)
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!)?.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
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

    func testTimestampStorageInDateColumnIntegralValue() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        let date = Date(timeIntervalSince1970: 42)
        // This is how a column of type .date is crated when using Vapor’s
        // scheme table creation.
        _ = try conn.query(#"CREATE TABLE "test" ("date" DATE NOT NULL);"#).wait()
        _ = try conn.query(#"INSERT INTO test (date) VALUES (?);"#, [date.sqliteData!]).wait()
        let rows = try conn.query("SELECT * FROM test;").wait()
        XCTAssertTrue(rows[0].column("date") == .float(date.timeIntervalSince1970) || rows[0].column("date") == .integer(Int(date.timeIntervalSince1970)))
        XCTAssertEqual(Date(sqliteData: rows[0].column("date")!)?.description, date.description)
    }

    func testDuplicateColumnName() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        let rows = try conn.query("SELECT 1 as foo, 2 as foo").wait()
        var i = 0
        for column in rows[0].columns {
            XCTAssertEqual(column.name, "foo")
            i += column.data.integer!
        }
        XCTAssertEqual(i, 3)
        XCTAssertEqual(rows[0].column("foo")?.integer, 1)
        XCTAssertEqual(rows[0].columns.filter { $0.name == "foo" }[0].data.integer, 1)
        XCTAssertEqual(rows[0].columns.filter { $0.name == "foo" }[1].data.integer, 2)
    }

	func testCustomAggregate() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		_ = try conn.query(#"CREATE TABLE "scores" ("score" INTEGER NOT NULL);"#).wait()
		_ = try conn.query(#"INSERT INTO scores (score) VALUES (?), (?), (?);"#, [.integer(3), .integer(4), .integer(5)]).wait()

		struct MyAggregate: SQLiteCustomAggregate {
			var sum: Int = 0
			mutating func step(_ values: [SQLiteData]) throws {
				sum = sum + (values.first?.integer ?? 0)
			}

			func finalize() throws -> SQLiteDataConvertible? {
				sum
			}
		}

		let function = SQLiteCustomFunction("my_sum", argumentCount: 1, pure: true, aggregate: MyAggregate.self)
		_ = try conn.install(customFunction: function).wait()

		let rows = try conn.query("SELECT my_sum(score) as total_score FROM scores").wait()
		XCTAssertEqual(rows.first?.column("total_score")?.integer, 12)
	}

	func testDatabaseFunction() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		let function = SQLiteCustomFunction("my_custom_function", argumentCount: 1, pure: true) { args in
			let result = Int(args[0].integer! * 3)
			return SQLiteData.integer(result)
		}

		_ = try conn.install(customFunction: function).wait()
		let rows = try conn.query("SELECT my_custom_function(2) as my_value").wait()
		XCTAssertEqual(rows.first?.column("my_value")?.integer, 6)
	}

    var threadPool: NIOThreadPool!
    var eventLoopGroup: EventLoopGroup!
    var eventLoop: EventLoop { return self.eventLoopGroup.any() }

    override func setUpWithError() throws {
        self.threadPool = .init(numberOfThreads: 1)
        self.threadPool.start()
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        XCTAssert(isLoggingConfigured)
    }
    
    override func tearDownWithError() throws {
        try self.threadPool.syncShutdownGracefully()
        try self.eventLoopGroup.syncShutdownGracefully()
    }
}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? .info
        return handler
    }
    return true
}()

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}
