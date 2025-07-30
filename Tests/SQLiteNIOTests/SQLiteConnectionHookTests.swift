import SQLiteNIO
import XCTest
import NIOConcurrencyHelpers

final class SQLiteConnectionHookTests: XCTestCase {

    // MARK: Update

    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }

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
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }

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
            let (c1, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            let (c2, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Bob')")

            XCTAssertEqual(c1.count(), 1)
            XCTAssertEqual(c2.count(), 1)
        }
    }

    func testUpdateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let token = try await db.addUpdateObserver(autoCancel: false) { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Carla')")
            XCTAssertEqual(updates.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users(name) VALUES('Dana')")
            XCTAssertEqual(updates.count(), 1) // unchanged
        }
    }

    // MARK: Commit / Rollback

    private func assertCommit(abort: Bool) async throws {
        try await withOpenedConnection { db in
            let (commits, _) = try await withCollector(db) { box in
                try await db.setCommitValidator { _ in box.append(()); return abort ? .deny : .allow }
            }

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
            _ = try await db.addCommitObserver { _ in }
            let (vetoes, _) = try await withCollector(db) { box in
                try await db.setCommitValidator { _ in box.append(()); return .deny }
            }

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
            let (rb, _) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in box.append(()) }
            }

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
            let _ = try await db.setAuthorizerValidator { event in
                switch (event.action, event.parameter2) {
                case (.read, "content"): return .deny
                case (.read, "metadata"): return .ignore
                default:                  return .allow
                }
            }

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
                try await db.addAuthorizerObserver { event in box.append(event) }
            }

            try await db.exec("CREATE TABLE settings(value INT)")
            try await db.exec("SELECT * FROM settings")
            let before = events.count()

            token.cancel()
            try await db.exec("SELECT * FROM settings")
            XCTAssertEqual(events.count(), before) // no growth
        }
    }

    // MARK: Misc

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let (u, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            let (c, _) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in box.append(()) }
            }

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
            var token: SQLiteHookToken? = try await db.addUpdateObserver(autoCancel: true) { event in updates.append(event) }

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
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }
            // Commit vetoer - always return .deny to veto
            let _ = try await db.setCommitValidator { _ in .deny }

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
        }
    }

    // MARK: - Authorizer IGNORE actually NULLs result

    func testIgnoreReturnsNull() async throws {
        try await withOpenedConnection { db in
            let _ = try await db.setAuthorizerValidator { event in
                (event.action == .read && event.parameter2 == "secret") ? .ignore : .allow
            }

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
            let (rb, _) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in box.append(()) }
            }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE sessions(session_id INT)")
            try await db.exec("COMMIT")

            XCTAssertEqual(rb.count(), 0)
        }
    }

    // MARK: - High-volume updates (stress)

    func testHundredRapidInserts() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in box.append(event) }
            }

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

    func testCommitObserversSkippedOnVeto() async throws {
        try await withOpenedConnection { db in
            let runCount = Box<Void>()

            let _ = try await db.setCommitValidator { _ in runCount.append(()); return .deny  } // veto
            let _ = try await db.addCommitObserver { _ in runCount.append(()) }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test_table(x INT)")

            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to validator veto")
            } catch {
                // expected
            }

            XCTAssertEqual(runCount.count(), 1) // Only validator should run, observer skipped on veto
        }
    }

    // NOTE: Removed testAuthorizerMultipleObserversAggregation -
    // With single validator design, multiple validators no longer supported

    // MARK: - New API Tests

    func testDefaultAutoCancelFalseTokenDroppedObserverPersists() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            // Drop token immediately - observer should persist since autoCancel defaults to false
            _ = try await db.addUpdateObserver { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")
            XCTAssertEqual(updates.count(), 1) // Observer should still work
        }
    }

    func testTokensNoOpAfterConnectionClose() async throws {
        let updates = Box<SQLiteUpdateEvent>()
        var token: SQLiteHookToken?

        let connection = try await SQLiteConnection.open(storage: .memory)
        token = try await connection.addUpdateObserver { event in updates.append(event) }

        try await connection.close()

        // Token should now be a no-op
        token?.cancel() // Should not crash or cause issues
        XCTAssertEqual(updates.count(), 0)
    }

    func testValidatorReplacementAndCancellation() async throws {
        try await withOpenedConnection { db in
            let calls1 = Box<Void>()
            let calls2 = Box<Void>()

            // Set first validator
            let token1 = try await db.setCommitValidator { _ in calls1.append(()); return .allow }

            // First validator should work
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test1(id INT)")
            try await db.exec("COMMIT")
            XCTAssertEqual(calls1.count(), 1)

            // Replace with second validator
            let token2 = try await db.setCommitValidator { _ in calls2.append(()); return .allow }

            // Only second validator should be called now
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test2(id INT)")
            try await db.exec("COMMIT")
            XCTAssertEqual(calls1.count(), 1) // Should still be 1 (no new calls)
            XCTAssertEqual(calls2.count(), 1) // Second validator called

            // Cancel second validator
            token2.cancel()

            // No validator should be called now
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test3(id INT)")
            try await db.exec("COMMIT")
            XCTAssertEqual(calls1.count(), 1) // Still 1
            XCTAssertEqual(calls2.count(), 1) // Still 1

            // Clean up first token (should be no-op since it was replaced)
            token1.cancel()
        }
    }

    func testMultipleObserversWithValidator() async throws {
        try await withOpenedConnection { db in
            let observer1 = Box<Void>()
            let observer2 = Box<Void>()
            let validatorCalls = Box<Void>()

            _ = try await db.addCommitObserver { _ in observer1.append(()) }
            _ = try await db.setCommitValidator { _ in validatorCalls.append(()); return .allow }
            _ = try await db.addCommitObserver { _ in observer2.append(()) }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test(id INT)")
            try await db.exec("COMMIT")

            XCTAssertEqual(validatorCalls.count(), 1)
            XCTAssertEqual(observer1.count(), 1) // Both observers should run
            XCTAssertEqual(observer2.count(), 1)
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
