//  SQLiteUpdateHookTests.swift

import SQLiteNIO
import XCTest
import NIOCore
import NIOEmbedded

final class SQLiteUpdateHookTests: XCTestCase {
    // MARK: Async-await tests
    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let collector = OperationCollector()
            try await db.setUpdateHook { e in Task { await collector.append(e) } }
            
            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES(?)", [.text("Alice")])
            
            let count = await collector.count()
            XCTAssertEqual(count, 1)
            
            let ev = try await XCTUnwrapAsync(await collector.all().first)
            XCTAssertEqual(ev.operation, .insert)
            XCTAssertEqual(ev.database,  "main")
            XCTAssertEqual(ev.table,     "users")
            XCTAssertEqual(ev.rowID,     1)
        }
    }
    
    func testUpdateHookUpdate() async throws {
        try await withOpenedConnection { db in
            let col = OperationCollector()
            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])
            
            try await db.setUpdateHook { e in Task { await col.append(e) } }
            _ = try await db.query("UPDATE users SET name = 'Bob' WHERE id = 1", [])
            
            let evs = await col.all()
            XCTAssertEqual(evs.count, 1)
            XCTAssertEqual(evs[0].operation, .update)
            XCTAssertEqual(evs[0].rowID,     1)
        }
    }
    
    func testUpdateHookDelete() async throws {
        try await withOpenedConnection { db in
            let col = OperationCollector()
            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])
            
            try await db.setUpdateHook { e in Task { await col.append(e) } }
            _ = try await db.query("DELETE FROM users WHERE id = 1", [])
            
            await XCTAssertEqualAsync(await col.count(), 1)
            await XCTAssertEqualAsync(await col.all().first?.operation, .delete)
        }
    }
    
    func testUpdateHookMultipleOperations() async throws {
        try await withOpenedConnection { db in
            let col = OperationCollector()
            try await db.setUpdateHook { e in Task { await col.append(e) } }
            
            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Bob')",   [])
            _ = try await db.query("UPDATE users SET name = 'Charlie' WHERE id = 1", [])
            _ = try await db.query("DELETE FROM users WHERE id = 2", [])
            
            let evs = await col.all()
            XCTAssertEqual(evs.map(\.operation), [.insert, .insert, .update, .delete])
            XCTAssertEqual(evs.map(\.rowID),     [1, 2, 1, 2])
        }
    }
    
    func testUpdateHookDisable() async throws {
        try await withOpenedConnection { db in
            let col = OperationCollector()
            
            try await db.setUpdateHook { e in Task { await col.append(e) } }
            _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
            _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])
            
            await XCTAssertEqualAsync(await col.count(), 1)
            
            try await db.setUpdateHook(nil)
            _ = try await db.query("INSERT INTO users(name) VALUES('Bob')", [])
            
            await XCTAssertEqualAsync(await col.count(), 1)   // still 1
        }
    }
    
    func testUpdatesAsyncStream() async throws {
        try await withOpenedConnection { db in
            var evs: [SQLiteConnection.SQLiteUpdateEvent] = []
            
            let t = Task {
                for try await e in db.updates() {
                    evs.append(e)
                    // Stop after exactly two events so the stream closes
                    if evs.count == 2 { break }
                }
            }
            
            _ = try await db.query("CREATE TABLE t(id INTEGER)", [])
            _ = try await db.query("INSERT INTO t VALUES(1)",   [])
            _ = try await db.query("INSERT INTO t VALUES(2)",   [])
            
            _ = try await t.value
            XCTAssertEqual(evs.count, 2)
            
            _ = try await db.query("INSERT INTO t VALUES(3)", [])
            XCTAssertEqual(evs.count, 2)           // hook removed by stream
        }
    }
    
    func testUpdateHookWithoutRowIDTable() async throws {
        try await withOpenedConnection { db in
            let col = OperationCollector()
            try await db.setUpdateHook { e in Task { await col.append(e) } }
            
            _ = try await db.query("CREATE TABLE x(id TEXT PRIMARY KEY) WITHOUT ROWID", [])
            _ = try await db.query("INSERT INTO x VALUES('a')", [])
            
            await XCTAssertEqualAsync(await col.count(), 0)
        }
    }
    
    // MARK: Futures API tests
    func testUpdateHookFuturesVersion() throws {
        let el = EmbeddedEventLoop()
        let db = try SQLiteConnection
            .open(storage: .memory,
                  threadPool: NIOThreadPool.singleton,
                  logger: .init(label: "test"),
                  on: el).wait()
        defer { _ = try? db.close().wait() }
        
        let col = OperationCollector()
        try db.setUpdateHook { e in Task { await col.append(e) } }.wait()
        
        _ = try db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", []).wait()
        _ = try db.query("INSERT INTO users(name) VALUES('Alice')",               []).wait()
        
        // ── bridge async actor call → synchronous wait ───────────────
        let p = el.makePromise(of: Int.self)
        Task { p.succeed(await col.count()) }
        let count = try p.futureResult.wait()
        // ─────────────────────────────────────────────────────────────
        
        XCTAssertEqual(count, 1)
    }
}

// Actor helper
fileprivate actor OperationCollector {
    private var events: [SQLiteConnection.SQLiteUpdateEvent] = []
    func append(_ e: SQLiteConnection.SQLiteUpdateEvent) { events.append(e) }
    func all() -> [SQLiteConnection.SQLiteUpdateEvent] { events }
    func count() -> Int { events.count }
}
