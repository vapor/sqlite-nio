import SQLiteNIO
import XCTest
import NIOConcurrencyHelpers

final class SQLiteConnectionHookTests: XCTestCase {

    // MARK: Update

    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            _ = token // Keep token alive

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")

            XCTAssertEqual(updates.count(), 1)
            let event = try XCTUnwrap(updates.all().first)
            XCTAssertEqual(event.operation, .insert)
            XCTAssertEqual(event.table, "users")
            XCTAssertEqual(event.rowID, 1)
        }
    }

    func testUpdateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            _ = token

            try await db.exec("CREATE TABLE products(id INTEGER PRIMARY KEY, value TEXT)")
            try await db.exec("INSERT INTO products(value) VALUES('A')")
            try await db.exec("UPDATE products SET value='B' WHERE id=1")
            try await db.exec("DELETE FROM products WHERE id=1")

            XCTAssertEqual(updates.count(), 3)
            let ops = updates.all().map(\.operation)
            XCTAssertEqual(ops, [.insert, .update, .delete])
        }
    }

    func testMultipleUpdateObservers() async throws {
        try await withOpenedConnection { db in
            let (c1, t1) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            let (c2, t2) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            _ = (t1, t2)

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Bob')")

            XCTAssertEqual(c1.count(), 1)
            XCTAssertEqual(c2.count(), 1)
        }
    }

    func testUpdateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let token   = try await db.addUpdateObserver { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Carla')")
            XCTAssertEqual(updates.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users(name) VALUES('Dana')")
            XCTAssertEqual(updates.count(), 1) // unchanged
            _ = token // Keep token alive (even though cancelled)
        }
    }

    // MARK: Persistent Observers

    func testPersistentUpdateObserver() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let observerID = try await db.installUpdateObserver { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")
            XCTAssertEqual(updates.count(), 1)

            let wasRemoved = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved)

            try await db.exec("INSERT INTO users(name) VALUES('Bob')")
            XCTAssertEqual(updates.count(), 1) // unchanged
        }
    }

    func testPersistentCommitObserver() async throws {
        try await withOpenedConnection { db in
            let commits = Box<Void>()
            let observerID = try await db.installCommitObserver { _ in commits.append(()); return false }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE items(id INT)")
            try await db.exec("COMMIT")
            XCTAssertEqual(commits.count(), 1)

            let wasRemoved = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE more_items(id INT)")
            try await db.exec("COMMIT")
            XCTAssertEqual(commits.count(), 1) // unchanged
        }
    }

    func testPersistentRollbackObserver() async throws {
        try await withOpenedConnection { db in
            let rollbacks = Box<Void>()
            let observerID = try await db.installRollbackObserver { _ in rollbacks.append(()) }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE temp_table(id INT)")
            try await db.exec("ROLLBACK")
            XCTAssertEqual(rollbacks.count(), 1)

            let wasRemoved = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE another_temp_table(id INT)")
            try await db.exec("ROLLBACK")
            XCTAssertEqual(rollbacks.count(), 1) // unchanged
        }
    }

    func testPersistentAuthorizerObserver() async throws {
        try await withOpenedConnection { db in
            let authorizations = Box<SQLiteAuthorizerEvent>()
            let observerID = try await db.installAuthorizerObserver { event in
                authorizations.append(event)
                return .allow
            }

            try await db.exec("CREATE TABLE documents(title TEXT, content TEXT)")
            try await db.exec("INSERT INTO documents VALUES('Test', 'Secret')")
            _ = try await db.exec("SELECT * FROM documents")

            let authCount = authorizations.count()
            XCTAssertGreaterThan(authCount, 0)

            let wasRemoved = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved)

            _ = try await db.exec("SELECT * FROM documents")
            XCTAssertEqual(authorizations.count(), authCount) // unchanged
        }
    }

    func testRemoveNonExistentObserver() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let observerID = try await db.installUpdateObserver { event in updates.append(event) }
            let wasRemoved1 = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved1)
            let wasRemoved2 = try await db.removeObserver(observerID)
            XCTAssertFalse(wasRemoved2)
        }
    }

    func testRemoveObserverTwice() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let observerID = try await db.installUpdateObserver { event in updates.append(event) }
            let wasRemoved1 = try await db.removeObserver(observerID)
            XCTAssertTrue(wasRemoved1)
            let wasRemoved2 = try await db.removeObserver(observerID)
            XCTAssertFalse(wasRemoved2)
        }
    }

    func testMixedObserverTypes() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let commits = Box<Void>()
            let rollbacks = Box<Void>()

            let updateID = try await db.installUpdateObserver { event in updates.append(event) }
            let commitID = try await db.installCommitObserver { _ in commits.append(()); return false }
            let rollbackID = try await db.installRollbackObserver { _ in rollbacks.append(()) }

            try await db.exec("BEGIN")
            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Test')")
            try await db.exec("COMMIT")

            XCTAssertEqual(updates.count(), 1)
            XCTAssertEqual(commits.count(), 1)
            XCTAssertEqual(rollbacks.count(), 0)

            let wasRemoved = try await db.removeObserver(updateID)
            XCTAssertTrue(wasRemoved)

            try await db.exec("BEGIN")
            try await db.exec("INSERT INTO users(name) VALUES('Test2')")
            try await db.exec("COMMIT")

            XCTAssertEqual(updates.count(), 1) // unchanged
            XCTAssertEqual(commits.count(), 2) // incremented

            _ = try await db.removeObserver(commitID)
            _ = try await db.removeObserver(rollbackID)
        }
    }

    func testPersistentObserversSurviveTokenDeallocation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            var observerID: SQLiteObserverID?

            do {
                observerID = try await db.installUpdateObserver { event in updates.append(event) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")
            XCTAssertEqual(updates.count(), 1)

            if let id = observerID {
                let wasRemoved = try await db.removeObserver(id)
                XCTAssertTrue(wasRemoved)
            }

            try await db.exec("INSERT INTO users(name) VALUES('Bob')")
            XCTAssertEqual(updates.count(), 1) // unchanged
        }
    }

    // MARK: Commit / Rollback

    private func assertCommit(abort: Bool) async throws {
        try await withOpenedConnection { db in
            let (commits, token) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in box.append(()); return abort }
            }
            _ = token

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE items(id INT)")
            if abort {
                do {
                    try await db.exec("COMMIT")
                    XCTFail("Expected COMMIT to fail due to observer veto")
                } catch {
                    // expected
                }
            } else {
                try await db.exec("COMMIT")
            }
            XCTAssertEqual(commits.count(), 1)
        }
    }

    func testCommitHookAllow()  async throws { try await assertCommit(abort: false) }
    func testCommitHookAbort()  async throws { try await assertCommit(abort: true ) }

    func testCommitObserversAggregateVeto() async throws {
        try await withOpenedConnection { db in
            _ = try await db.addCommitObserver { _ in false } // token dropped; auto-cancelled
            let (vetoes, token) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in box.append(()); return true }
            }
            _ = token

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE orders(order_number INT)")
            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to observer veto")
            } catch {
                // expected
            }
            XCTAssertEqual(vetoes.count(), 1)
        }
    }

    func testRollbackHookExplicitAndImplicit() async throws {
        try await withOpenedConnection { db in
            let (rb, token) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in box.append(()) }
            }
            _ = token

            try await db.exec("BEGIN")
            try await db.exec("ROLLBACK")

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE inventory(id INT)")
            try await db.exec("ROLLBACK")

            XCTAssertEqual(rb.count(), 2)
        }
    }

    // MARK: Authorizer

    func testAuthorizerAllowIgnoreDeny() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { event in
                switch (event.action, event.parameter2) {
                case (.read, "content"): return .deny
                case (.read, "metadata"): return .ignore
                default:                  return .allow
                }
            }
            _ = token

            try await db.exec("CREATE TABLE documents(title INT, content INT, metadata INT)")
            try await db.exec("INSERT INTO documents VALUES(1,2,3)")

            do {
                _ = try await db.exec("SELECT content FROM documents")
                XCTFail("Expected SELECT content to fail due to authorizer denial")
            } catch {
                // expected
            }

            let rows = try await db.exec("SELECT title, metadata FROM documents")
            let row  = try XCTUnwrap(rows.first)
            XCTAssertEqual(row.column("title")?.integer, 1)
            XCTAssertTrue(row.column("metadata")?.isNull ?? false)
        }
    }

    func testAuthorizerHookDisable() async throws {
        try await withOpenedConnection { db in
            let (events, token) = try await withCollector(db) { box in
                try await db.addAuthorizerObserver { event in box.append(event); return .allow }
            }

            try await db.exec("CREATE TABLE settings(value INT)")
            try await db.exec("SELECT * FROM settings")
            let before = events.count()

            token.cancel()
            try await db.exec("SELECT * FROM settings")
            XCTAssertEqual(events.count(), before) // no growth
            _ = token // Keep token alive even after cancellation
        }
    }

    // MARK: Misc

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let (u, tu) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            let (c, tc) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in box.append(()); return false }
            }
            _ = (tu, tc)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE transactions(amount INT)")
            try await db.exec("INSERT INTO transactions VALUES(1)")
            try await db.exec("COMMIT")

            XCTAssertEqual(u.count(), 1)
            XCTAssertEqual(c.count(), 1)
        }
    }

    func testObserverTokenDeinitCancels() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            var token: SQLiteHookToken? = try await db.addUpdateObserver { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users VALUES(1,'Evan')")
            XCTAssertEqual(updates.count(), 1)

            token = nil // drop reference; deinit cancels
            try await db.exec("INSERT INTO users VALUES(2,'Fred')")
            XCTAssertEqual(updates.count(), 1)
            _ = token // silence unused warning
        }
    }

    // MARK: - Order-of-execution

    func testCommitObserversCheckedAfterUpdateHooks() async throws {
        try await withOpenedConnection { db in
            let (updates, token1) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            // Commit vetoer - always return true to veto
            let token2 = try await db.addCommitObserver { _ in true }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE logs(entry INT)") // inside txn
            try await db.exec("INSERT INTO logs VALUES(1)")

            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to observer veto")
            } catch {
                // expected
            }

            XCTAssertEqual(updates.count(), 1)

            // Table should not exist after rollback
            do {
                _ = try await db.exec("SELECT * FROM logs")
                XCTFail("Table should not exist after rollback")
            } catch {
                // expected
            }

            _ = (token1, token2) // Keep alive
        }
    }

    // MARK: - No-hook-after-cancel

    func testCancelStopsFurtherEvents() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()
            let token = try await db.addUpdateObserver { event in box.append(event) }
            try await makeUsersTable(in: db)

            try await db.exec("INSERT INTO users VALUES(1,'A')")
            XCTAssertEqual(box.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users VALUES(2,'B')")
            XCTAssertEqual(box.count(), 1)     // unchanged
            _ = token // Keep alive
        }
    }

    // MARK: - Authorizer IGNORE actually NULLs result

    func testIgnoreReturnsNull() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { event in
                (event.action == .read && event.parameter2 == "secret") ? .ignore : .allow
            }
            _ = token

            try await db.exec("CREATE TABLE accounts(id INT, secret INT)")
            try await db.exec("INSERT INTO accounts VALUES(1,2)")
            let rows = try await db.exec("SELECT id,secret FROM accounts")
            let row = try XCTUnwrap(rows.first)
            XCTAssertNil(row.column("secret")?.integer)
        }
    }

    // MARK: - Rollback hook not fired on successful txn

    func testNoRollbackOnCommit() async throws {
        try await withOpenedConnection { db in
            let (rb, token) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in box.append(()) }
            }
            _ = token

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE sessions(session_id INT)")
            try await db.exec("COMMIT")

            XCTAssertEqual(rb.count(), 0)
        }
    }

    // MARK: - High-volume updates (stress)

    func testHundredRapidInserts() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            _ = token

            try await makeUsersTable(in: db)
            for i in 0..<100 {
                try await db.exec("INSERT INTO users(name) VALUES('user\(i)')")
            }
            XCTAssertEqual(updates.count(), 100)
        }
    }

    // MARK: Scoped Observer Tests

    func testWithUpdateObserverScopesRegistration() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()

            try await db.withUpdateObserver({ event in box.append(event) }) {
                try await makeUsersTable(in: db)  // DDL doesn't fire update hooks
                try await db.exec("INSERT INTO users(name) VALUES('Scoped')")  // DML fires update hooks
            }

            XCTAssertEqual(box.count(), 1)  // Only the INSERT fires the hook

            try await db.exec("INSERT INTO users(name) VALUES('Outside')")
            XCTAssertEqual(box.count(), 1)
        }
    }

    func testDiscardedPersistentObserverLivesForConnection() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()

            _ = try await db.installUpdateObserver { event in box.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('A')")
            XCTAssertEqual(box.count(), 1)

            try await db.exec("INSERT INTO users(name) VALUES('B')")
            XCTAssertEqual(box.count(), 2)
        }
    }

    func testCommitObserversAllRunEvenOnVeto() async throws {
        try await withOpenedConnection { db in
            let runCount = Box<Void>()

            let token1 = try await db.addCommitObserver { _ in runCount.append(()); return true  } // veto
            let token2 = try await db.addCommitObserver { _ in runCount.append(()); return false }
            _ = (token1, token2)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test_table(x INT)")

            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to observer veto")
            } catch {
                // expected
            }

            XCTAssertEqual(runCount.count(), 2) // Both observers should run
        }
    }

    func testAuthorizerMultipleObserversAggregation() async throws {
        try await withOpenedConnection { db in
            let token1 = try await db.addAuthorizerObserver { _ in .allow }
            let token2 = try await db.addAuthorizerObserver { event in
                switch (event.action, event.parameter2) {
                case (.read, "secret"): return .deny
                default: return .allow
                }
            }
            let token3 = try await db.addAuthorizerObserver { event in
                switch (event.action, event.parameter2) {
                case (.read, "secret"): return .ignore
                default: return .allow
                }
            }
            _ = (token1, token2, token3)

            try await db.exec("CREATE TABLE docs(id INT, secret INT, public INT)")
            try await db.exec("INSERT INTO docs VALUES(1, 42, 100)")

            // Deny should win over ignore and allow
            do {
                _ = try await db.exec("SELECT secret FROM docs")
                XCTFail("Expected SELECT secret to fail due to authorizer denial")
            } catch {
                // expected
            }

            let rows = try await db.exec("SELECT public FROM docs")
            let row = try XCTUnwrap(rows.first)
            XCTAssertEqual(row.column("public")?.integer, 100)
        }
    }

    // MARK: – logging bootstrap

    override class func setUp() { XCTAssert(isLoggingConfigured) }
}

// MARK: – helpers

private extension SQLiteConnection {
    @discardableResult
    func exec(_ sql: String) async throws -> [SQLiteRow] { try await query(sql, []) }
}

/// Simple thread-safe collector used in tests.
/// We deliberately avoid `actor` here so hook callbacks (which are synchronous
/// and run on SQLite’s internal thread) can record events deterministically
/// without spawning Tasks and introducing scheduling races.
private final class Box<Element>: @unchecked Sendable {
    private let lock = NIOLock()
    private var items: [Element] = []

    func append(_ item: Element) {
        lock.withLockVoid { items.append(item) }
    }

    func count() -> Int {
        lock.withLock { items.count }
    }

    func all() -> [Element] {
        lock.withLock { items }
    }
}

@inline(__always)
private func withCollector<E>(
    _ db: SQLiteConnection,
    _ register: (Box<E>) async throws -> SQLiteHookToken
) async throws -> (Box<E>, SQLiteHookToken) {
    let box   = Box<E>()
    let token = try await register(box)
    return (box, token)
}

private func makeUsersTable(in db: SQLiteConnection) async throws {
    try await db.exec("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)")
}
