import SQLiteNIO
import XCTest
import NIOCore
import NIOEmbedded

// MARK: – Async/await tests

final class SQLiteConnectionHookTests: XCTestCase {
    private static func createTableUsers(_ db: SQLiteConnection) async throws {
        _ = try await db.query("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)", [])
    }

    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let col = UpdateCollector()

            try await db.withUpdateObserver({ e in Task { await col.append(e) } }) {
                try await Self.createTableUsers(db)
                _ = try await db.query("INSERT INTO users(name) VALUES('Alice')", [])

                await XCTAssertEqualAsync(await col.count(), 1)
                let ev = try await XCTUnwrapAsync(await col.all().first)
                XCTAssertEqual(ev.operation, .insert)
                XCTAssertEqual(ev.table, "users")
                XCTAssertEqual(ev.rowID, 1)
            }
        }
    }

    func testCommitHookAllow() async throws {
        try await withOpenedConnection { db in
            let col = CommitCollector()

            try await db.withCommitObserver({ _ in
                Task { await col.append() }
                return false // allow commit
            }) {
                _ = try await db.query("BEGIN TRANSACTION", [])
                _ = try await db.query("CREATE TABLE t1(x INTEGER)", [])
                _ = try await db.query("COMMIT", [])

                await XCTAssertEqualAsync(await col.count(), 1)
            }
        }
    }

    func testCommitHookAbort() async throws {
        try await withOpenedConnection { db in
            let col = CommitCollector()

            try await db.withCommitObserver({ _ in
                Task { await col.append() }
                return true // abort commit
            }) {
                _ = try await db.query("BEGIN TRANSACTION", [])
                _ = try await db.query("CREATE TABLE t2(y TEXT)", [])
                await XCTAssertThrowsErrorAsync(try await db.query("COMMIT", []))
                await XCTAssertEqualAsync(await col.count(), 1)
            }
        }
    }

    func testRollbackHook() async throws {
        try await withOpenedConnection { db in
            let col = RollbackCollector()

            try await db.withRollbackObserver({ _ in Task { await col.append() } }) {
                _ = try await db.query("BEGIN TRANSACTION", [])
                _ = try await db.query("ROLLBACK", [])

                await XCTAssertEqualAsync(await col.count(), 1)
            }
        }
    }

    func testUpdateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let col = UpdateCollector()

            try await db.withUpdateObserver({ e in Task { await col.append(e) } }) {
                _ = try await db.query("CREATE TABLE test(id INTEGER PRIMARY KEY, val TEXT)", [])
                _ = try await db.query("INSERT INTO test(val) VALUES('A')", [])
                _ = try await db.query("UPDATE test SET val='B' WHERE id=1", [])
                _ = try await db.query("DELETE FROM test WHERE id=1", [])

                let ops = await col.all().map(\.operation)
                await XCTAssertEqualAsync(ops, [.insert, .update, .delete])
            }
        }
    }

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let ucol = UpdateCollector()
            let ccol = CommitCollector()
            let token1 = try await db.addUpdateObserver { e in Task { await ucol.append(e) } }
            let token2 = try await db.addCommitObserver { _ in Task { await ccol.append() }; return false }

            _ = try await db.query("BEGIN TRANSACTION", [])
            _ = try await db.query("CREATE TABLE foo(x INT)", [])
            _ = try await db.query("INSERT INTO foo(x) VALUES(1)", [])
            _ = try await db.query("COMMIT", [])

            await XCTAssertEqualAsync(await ucol.count(), 1)
            await XCTAssertEqualAsync(await ccol.count(), 1)
            _ = token1 // Keep alive
            _ = token2 // Keep alive
        }
    }

    func testMultipleUpdateObservers() async throws {
        try await withOpenedConnection { db in
            let col1 = UpdateCollector()
            let col2 = UpdateCollector()
            let token1 = try await db.addUpdateObserver { e in Task { await col1.append(e) } }
            let token2 = try await db.addUpdateObserver { e in Task { await col2.append(e) } }

            try await Self.createTableUsers(db)
            _ = try await db.query("INSERT INTO users(name) VALUES('Bob')", [])

            await XCTAssertEqualAsync(await col1.count(), 1)
            await XCTAssertEqualAsync(await col2.count(), 1)
            _ = token1 // Keep alive
            _ = token2 // Keep alive
        }
    }

    func testUpdateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let col = UpdateCollector()

            let token = try await db.addUpdateObserver { e in Task { await col.append(e) } }

            try await Self.createTableUsers(db)
            _ = try await db.query("INSERT INTO users(name) VALUES('Carla')", [])
            await XCTAssertEqualAsync(await col.count(), 1)

            token.cancel() // uninstall
            _ = try await db.query("INSERT INTO users(name) VALUES('Dana')", [])
            await XCTAssertEqualAsync(await col.count(), 1) // unchanged
        }
    }

    func testAuthorizerHookInvokedOnPrepare() async throws {
        try await withOpenedConnection { db in
            let col = AuthorizerCollector()

            try await db.withAuthorizerObserver({ event in
                Task { await col.append(event) }
                return .allow
            }) {
                _ = try await db.query("CREATE TABLE t(a INT)", [])
                _ = try await db.query("SELECT * FROM t", [])

                let count = await col.count()
                await XCTAssertTrueAsync(count > 0)
                let evs = await col.all()
                XCTAssertTrue(evs.contains { $0.action == .read && $0.parameter1 == "t" })
            }
        }
    }

    func testAuthorizerHookCanDeny() async throws {
        try await withOpenedConnection { db in
            let col = AuthorizerCollector()

            try await db.withAuthorizerObserver({ event in
                Task { await col.append(event) }
                if event.action == .read && event.parameter1 == "t" { return .deny }
                return .allow
            }) {
                _ = try await db.query("CREATE TABLE t(a INT)", [])
                await XCTAssertThrowsErrorAsync(try await db.query("SELECT * FROM t", []))
                let events = await col.all()
                let deniedEvent = events.first { $0.action == .read && $0.parameter1 == "t" }
                XCTAssertNotNil(deniedEvent)
            }
        }
    }

    func testAuthorizerHookDisable() async throws {
        try await withOpenedConnection { db in
            let col = AuthorizerCollector()
            let token = try await db.addAuthorizerObserver { event in
                Task { await col.append(event) }
                return .allow
            }

            _ = try await db.query("CREATE TABLE t(a INT)", [])
            _ = try await db.query("SELECT * FROM t", [])
            await XCTAssertTrueAsync(await col.count() > 0)

            // Remove hook
            let countBeforeCancel = await col.count()
            token.cancel()
            _ = try await db.query("SELECT * FROM t", [])
            await XCTAssertEqualAsync(await col.count(), countBeforeCancel)
        }
    }

    // MARK: - setup

    override class func setUp() {
        XCTAssert(isLoggingConfigured)
    }
}

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

fileprivate actor AuthorizerCollector {
    private var events: [SQLiteAuthorizerEvent] = []
    func append(_ e: SQLiteAuthorizerEvent) { events.append(e) }
    func all() -> [SQLiteAuthorizerEvent] { events }
    func count() -> Int { events.count }
}
