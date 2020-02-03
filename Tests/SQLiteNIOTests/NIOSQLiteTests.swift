import XCTest
import SQLiteNIO

final class SQLiteNIOTests: XCTestCase {
    func testExample() throws {
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
    }

    func testDateStorage() throws {
        let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
        defer { try! conn.close().wait() }

        _ = try conn.query("CREATE TABLE foo (bar DATE)").wait()
        _ = try conn.query("INSERT INTO foo (bar) VALUES (strftime('%s','2020-01-02'))").wait()
        let rows = try conn.query("SELECT bar FROM foo").wait()
        XCTAssertEqual(Date(sqliteData: rows[0].column("bar")!)?.description, "2020-01-02 00:00:00 +0000")
    }

    var threadPool: NIOThreadPool!
    var eventLoopGroup: EventLoopGroup!
    var eventLoop: EventLoop {
        return self.eventLoopGroup.next()
    }

    override func setUp() {
        self.threadPool = .init(numberOfThreads: 8)
        self.threadPool.start()
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 8)
    }

    override func tearDown() {
        try! self.threadPool.syncShutdownGracefully()
        try! self.eventLoopGroup.syncShutdownGracefully()
    }
}
