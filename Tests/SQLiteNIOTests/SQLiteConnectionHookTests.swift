// SQLiteConnectionHookTests.swift

import SQLiteNIO
import XCTest
import NIOCore
import NIOEmbedded

// MARK: – Collector actors

fileprivate actor UpdateCollector {
    private var events: [SQLiteUpdateEvent] = []
    func append(_ e: SQLiteUpdateEvent) { events.append(e) }
    func all() -> [SQLiteUpdateEvent]     { events }
    func count() -> Int                   { events.count }
}

fileprivate actor CommitCollector {
    private var calls = 0
    func append() { calls += 1 }
    func count() -> Int { calls }
}

fileprivate actor RollbackCollector {
    private var calls = 0
    func append() { calls += 1 }
    func count() -> Int { calls }
}

fileprivate actor TransactionCollector {
    private var events: [SQLiteTransactionEvent] = []
    func append(_ e: SQLiteTransactionEvent) { events.append(e) }
    func all() -> [SQLiteTransactionEvent]       { events }
    func count() -> Int                          { events.count }
}

// MARK: – Async/await tests

final class SQLiteConnectionHookTests: XCTestCase {

    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let col = UpdateCollector()
            try await db.setUpdateHook { e in Task { await col.append(e) } }

            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])

            await XCTAssertEqualAsync(await col.count(), 1)
            let ev = try await XCTUnwrapAsync(await col.all().first)
            XCTAssertEqual(ev.operation, .insert)
            XCTAssertEqual(ev.table,     "users")
            XCTAssertEqual(ev.rowID,     1)
        }
    }

    func testCommitHookAllow() async throws {
        try await withOpenedConnection { db in
            let col = CommitCollector()
            try await db.setCommitHook {
                Task { await col.append() }
                return false // allow commit
            }

            _ = try await db.query("BEGIN TRANSACTION", [])
            // MUST perform at least one modifying statement
            _ = try await db.query("CREATE TABLE t1(x INTEGER)", [])
            _ = try await db.query("COMMIT", [])

            await XCTAssertEqualAsync(await col.count(), 1)
        }
    }

    func testCommitHookAbort() async throws {
        try await withOpenedConnection { db in
            let col = CommitCollector()
            try await db.setCommitHook {
                Task { await col.append() }
                return true // abort commit
            }

            _ = try await db.query("BEGIN TRANSACTION", [])
            // MUST perform at least one modifying statement
            _ = try await db.query("CREATE TABLE t2(y TEXT)", [])
            await XCTAssertThrowsErrorAsync(try await db.query("COMMIT", []))
            await XCTAssertEqualAsync(await col.count(), 1)
        }
    }

    func testRollbackHook() async throws {
        try await withOpenedConnection { db in
            let col = RollbackCollector()
            try await db.setTransactionHook { e in
                if e.type == .rollback {
                    Task { await col.append() }
                }
            }

            _ = try await db.query("BEGIN TRANSACTION", [])
            _ = try await db.query("ROLLBACK", [])

            await XCTAssertEqualAsync(await col.count(), 1)
        }
    }

    func testUpdateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let col = UpdateCollector()
            try await db.setUpdateHook { e in Task { await col.append(e) } }

            _ = try await db.query("CREATE TABLE test(id INTEGER PRIMARY KEY, val TEXT)", [])
            _ = try await db.query("INSERT INTO test(val) VALUES('A')", [])
            _ = try await db.query("UPDATE test SET val='B' WHERE id=1", [])
            _ = try await db.query("DELETE FROM test WHERE id=1", [])

            let ops = await col.all().map(\.operation)
            await XCTAssertEqualAsync(ops, [.insert, .update, .delete])
        }
    }

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let ucol = UpdateCollector()
            let ccol = CommitCollector()
            try await db.setUpdateHook { e in Task { await ucol.append(e) } }
            try await db.setCommitHook {
                Task { await ccol.append() }
                return false
            }

            _ = try await db.query("BEGIN TRANSACTION", [])
            _ = try await db.query("CREATE TABLE foo(x INT)", [])
            _ = try await db.query("INSERT INTO foo(x) VALUES(1)", [])
            _ = try await db.query("COMMIT", [])

            await XCTAssertEqualAsync(await ucol.count(), 1)
            await XCTAssertEqualAsync(await ccol.count(), 1)
        }
    }

    func testMultiStatementTransactionCommitHook() async throws {
        try await withOpenedConnection { db in
            let ccol = CommitCollector()
            try await db.setCommitHook {
                Task { await ccol.append() }
                return false
            }

            _ = try await db.query("BEGIN TRANSACTION", [])
            _ = try await db.query("CREATE TABLE m1(a INT)", [])
            _ = try await db.query("INSERT INTO m1 VALUES(5)", [])
            _ = try await db.query("UPDATE m1 SET a=6 WHERE a=5", [])
            _ = try await db.query("COMMIT", [])

            await XCTAssertEqualAsync(await ccol.count(), 1)
        }
    }

    // MARK: – Futures-based tests

    func testUpdateHookFuture() throws {
        let el = EmbeddedEventLoop()
        let db = try SQLiteConnection
            .open(storage: .memory,
                  threadPool: NIOThreadPool.singleton,
                  logger: .init(label: "test"),
                  on: el).wait()
        defer { _ = try? db.close().wait() }

        let col = UpdateCollector()
        try db.setUpdateHook { e in Task { await col.append(e) } }.wait()
        _ = try db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", []).wait()
        _ = try db.query("INSERT INTO users(name) VALUES('X')",               []).wait()

        let p = el.makePromise(of: Int.self)
        Task {
            let cnt = await col.count()
            p.succeed(cnt)
        }
        let c = try p.futureResult.wait()
        XCTAssertEqual(c, 1)
    }

    func testCommitHookFutureAllow() throws {
        let el = EmbeddedEventLoop()
        let db = try SQLiteConnection
            .open(storage: .memory,
                  threadPool: NIOThreadPool.singleton,
                  logger: .init(label: "test"),
                  on: el).wait()
        defer { _ = try? db.close().wait() }

        let col = CommitCollector()
        try db.setCommitHook {
            Task { await col.append() }
            return false
        }.wait()

        _ = try db.query("BEGIN TRANSACTION", []).wait()
        // include a modifying statement
        _ = try db.query("CREATE TABLE f1(a INT)", []).wait()
        _ = try db.query("COMMIT", []).wait()

        let p = el.makePromise(of: Int.self)
        Task {
            p.succeed(await col.count())
        }
        let count = try p.futureResult.wait()
        XCTAssertEqual(count, 1)
    }

    func testCommitHookFutureAbort() throws {
        let el = EmbeddedEventLoop()
        let db = try SQLiteConnection
            .open(storage: .memory,
                  threadPool: NIOThreadPool.singleton,
                  logger: .init(label: "test"),
                  on: el).wait()
        defer { _ = try? db.close().wait() }

        let col = CommitCollector()
        try db.setCommitHook {
            Task { await col.append() }
            return true
        }.wait()

        _ = try db.query("BEGIN TRANSACTION", []).wait()
        _ = try db.query("CREATE TABLE f2(b TEXT)", []).wait()
        XCTAssertThrowsError(try db.query("COMMIT", []).wait())
        let p = el.makePromise(of: Int.self)
        Task {
            p.succeed(await col.count())
        }
        let c = try p.futureResult.wait()
        XCTAssertEqual(c, 1)
    }

    func testRollbackHookFuture() throws {
        let el = EmbeddedEventLoop()
        let db = try SQLiteConnection
            .open(storage: .memory,
                  threadPool: NIOThreadPool.singleton,
                  logger: .init(label: "test"),
                  on: el).wait()
        defer { _ = try? db.close().wait() }

        let col = RollbackCollector()
        try db.setTransactionHook { e in
            if e.type == .rollback {
                Task { await col.append() }
            }
        }.wait()

        _ = try db.query("BEGIN TRANSACTION", []).wait()
        _ = try db.query("ROLLBACK", []).wait()

        let p = el.makePromise(of: Int.self)
        Task {
            p.succeed(await col.count())
        }
        let count = try p.futureResult.wait()
        XCTAssertEqual(count, 1)
    }

    // MARK: - setup

    override class func setUp() {
        XCTAssert(isLoggingConfigured)
    }
}
