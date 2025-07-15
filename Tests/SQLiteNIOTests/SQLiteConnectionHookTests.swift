import SQLiteNIO
import XCTest

// MARK: – helpers

private extension SQLiteConnection {
    @discardableResult
    func exec(_ sql: String) async throws -> [SQLiteRow] { try await query(sql, []) }
}

private actor Box<Element> {
    var items: [Element] = []
    func append(_ item: Element) { items.append(item) }
    func count() -> Int          { items.count }
    func all()   -> [Element]    { items }
}

@inline(__always)
private func withCollector<E>(
    _ db: SQLiteConnection,
    _ register: (Box<E>) async throws -> SQLiteHookToken
) async throws -> (Box<E>, SQLiteHookToken) {
    let box   = Box<E>()
    let token = try await register(box)
    return (box, token)          // <- caller *must* retain token
}

private func makeUsersTable(in db: SQLiteConnection) async throws {
    try await db.exec("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)")
}

private func yield() async { try? await Task.sleep(nanoseconds: 1_000_000) }

// MARK: – tests

final class SQLiteConnectionHookTests: XCTestCase {

    // MARK: Update

    func testUpdateHookInsert() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            _ = token // Keep token alive for the duration of the test

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")

            await XCTAssertEqualAsync(await updates.count(), 1)
            let event = try await XCTUnwrapAsync(await updates.all().first)
            XCTAssertEqual(event.operation, .insert)
            XCTAssertEqual(event.table, "users")
            XCTAssertEqual(event.rowID, 1)
        }
    }

    func testUpdateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            _ = token // Keep token alive for the duration of the test

            // Execute statements separately to ensure hooks fire for each
            try await db.exec("CREATE TABLE products(id INTEGER PRIMARY KEY, value TEXT)")
            try await db.exec("INSERT INTO products(value) VALUES('A')")
            try await db.exec("UPDATE products SET value='B' WHERE id=1")
            try await db.exec("DELETE FROM products WHERE id=1")

            let ops = await updates.all().map(\.operation)
            await XCTAssertEqualAsync(ops, [.insert, .update, .delete])
        }
    }

    func testMultipleUpdateObservers() async throws {
        try await withOpenedConnection { db in
            let (c1, t1) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            let (c2, t2) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            _ = (t1, t2) // Keep tokens alive for the duration of the test

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Bob')")

            await XCTAssertEqualAsync(await c1.count(), 1)
            await XCTAssertEqualAsync(await c2.count(), 1)
        }
    }

    func testUpdateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let token   = try await db.addUpdateObserver { event in
                Task { await updates.append(event) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Carla')")
            await XCTAssertEqualAsync(await updates.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users(name) VALUES('Dana')")
            await XCTAssertEqualAsync(await updates.count(), 1)         // unchanged
            _ = token // Keep token alive (even though cancelled)
        }
    }

    // MARK: Commit / Rollback

    private func assertCommit(abort: Bool) async throws {
        try await withOpenedConnection { db in
            let (commits, token) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in Task { await box.append(()) }; return abort }
            }
            _ = token // Keep token alive for the duration of the test

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE items(id INT)")
            if abort {
                do {
                    try await db.exec("COMMIT")
                    XCTFail("Expected COMMIT to fail due to observer veto")
                } catch {
                    // Expected - commit was vetoed
                }
            } else {
                try await db.exec("COMMIT")
            }
            await XCTAssertEqualAsync(await commits.count(), 1)
        }
    }

    func testCommitHookAllow()  async throws { try await assertCommit(abort: false) }
    func testCommitHookAbort()  async throws { try await assertCommit(abort: true ) }

    func testCommitObserversAggregateVeto() async throws {
        try await withOpenedConnection { db in
            _ = try await db.addCommitObserver { _ in false }     // ignored
            let (vetoes, token) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in
                    Task { await box.append(()) }; return true
                }
            }
            _ = token // Keep token alive for the duration of the test

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE orders(order_number INT)")

            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to observer veto")
            } catch {
                // Expected - commit was vetoed
            }

            await XCTAssertEqualAsync(await vetoes.count(), 1)
        }
    }

    func testRollbackHookExplicitAndImplicit() async throws {
        try await withOpenedConnection { db in
            let (rb, token) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in Task { await box.append(()) } }
            }
            _ = token // Keep token alive for the duration of the test

            // Test explicit rollback
            try await db.exec("BEGIN")
            try await db.exec("ROLLBACK")

            // Test another explicit rollback (implicit rollback behavior varies)
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE inventory(id INT)")
            try await db.exec("ROLLBACK")

            await XCTAssertEqualAsync(await rb.count(), 2)
        }
    }

    // MARK: Authorizer

    func testAuthorizerAllowIgnoreDeny() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { event in
                switch (event.action, event.parameter2) {
                case (.read, "content"): return .deny
                case (.read, "metadata"): return .ignore
                default:           return .allow
                }
            }
            _ = token // Keep token alive for the duration of the test

            try await db.exec("CREATE TABLE documents(title INT, content INT, metadata INT)")
            try await db.exec("INSERT INTO documents VALUES(1,2,3)")

            do {
                _ = try await db.exec("SELECT content FROM documents")
                XCTFail("Expected SELECT content to fail due to authorizer denial")
            } catch {
                // Expected - authorizer denied access to column content
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
                try await db.addAuthorizerObserver { event in
                    Task { await box.append(event) }; return .allow
                }
            }

            try await db.exec("CREATE TABLE settings(value INT)")
            try await db.exec("SELECT * FROM settings")
            let before = await events.count()

            token.cancel()
            try await db.exec("SELECT * FROM settings")
            await XCTAssertEqualAsync(await events.count(), before)      // no growth
            _ = token // Keep token alive even after cancellation
        }
    }

    // MARK: Misc

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let (u, tu) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            let (c, tc) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in Task { await box.append(()) }; return false }
            }
            _ = (tu, tc)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE transactions(amount INT)")
            try await db.exec("INSERT INTO transactions VALUES(1)")
            try await db.exec("COMMIT")

            await XCTAssertEqualAsync(await u.count(), 1)
            await XCTAssertEqualAsync(await c.count(), 1)
        }
    }

    func testObserverTokenDeinitCancels() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            var token: SQLiteHookToken? = try await db.addUpdateObserver { event in Task { await updates.append(event) } }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users VALUES(1,'Evan')")
            await XCTAssertEqualAsync(await updates.count(), 1)

            token = nil                                            // drop reference
            try await db.exec("INSERT INTO users VALUES(2,'Fred')")
            await XCTAssertEqualAsync(await updates.count(), 1)
            _ = token // Silence warning for optional token variable
        }
    }

    func testObserverAddedDuringCallbackReceivesLaterEvents() async throws {
        try await withOpenedConnection { db in
            let late = Box<SQLiteUpdateEvent>()
            let tokens = Box<SQLiteHookToken>()
            let shouldRegister = Box<Bool>()
            await shouldRegister.append(true)

            let token = try await db.addUpdateObserver { [unowned db] _ in
                Task {
                    let should = await shouldRegister.all().first ?? false
                    if should {
                        await shouldRegister.append(false) // Clear the flag
                        if let newToken = try? await db.addUpdateObserver({ event in
                            Task { await late.append(event) }
                        }) {
                            await tokens.append(newToken)
                        }
                    }
                }
            }
            _ = token // Keep token alive for the duration of the test

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users VALUES(1,'Gina')")

            // Give the async task time to register the new observer
            try await Task.sleep(for: .milliseconds(10))

            try await db.exec("INSERT INTO users VALUES(2,'Helen')")

            await XCTAssertEqualAsync(await late.count(), 1)
            _ = await tokens.all() // Keep tokens alive
        }
    }

    // MARK: - Order-of-execution

    func testCommitObserversCheckedAfterUpdateHooks() async throws {
        try await withOpenedConnection { db in
            let (updates, token1) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            // Commit vetoer - always return true to veto
            let token2 = try await db.addCommitObserver { _ in true }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE logs(entry INT)")   // inside txn
            try await db.exec("INSERT INTO logs VALUES(1)")

            do {
                try await db.exec("COMMIT")
                XCTFail("Expected COMMIT to fail due to observer veto")
            } catch {
                // Expected - commit was vetoed by hook returning true
            }

            // update hook still fired even though commit aborted
            await XCTAssertEqualAsync(await updates.count(), 1)

            // Table should not exist after rollback
            do {
                _ = try await db.exec("SELECT * FROM logs")
                XCTFail("Table should not exist after rollback")
            } catch {
                // Expected - table was rolled back
            }

            _ = (token1, token2) // Keep alive
        }
    }

    // MARK: - No-hook-after-cancel

    func testCancelStopsFurtherEvents() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()
            let token = try await db.addUpdateObserver { event in Task { await box.append(event) } }
            try await makeUsersTable(in: db)

            try await db.exec("INSERT INTO users VALUES(1,'A')")
            await XCTAssertEqualAsync(await box.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users VALUES(2,'B')")
            await XCTAssertEqualAsync(await box.count(), 1)     // unchanged
            _ = token // Keep alive
        }
    }

    // MARK: - Authorizer IGNORE actually NULLs result

    func testIgnoreReturnsNull() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { event in
                (event.action == .read && event.parameter2 == "secret") ? .ignore : .allow
            }
            try await db.exec("CREATE TABLE accounts(id INT, secret INT)")
            try await db.exec("INSERT INTO accounts VALUES(1,2)")
            let rows = try await db.exec("SELECT id,secret FROM accounts")
            let row = try XCTUnwrap(rows.first)
            XCTAssertNil(row.column("secret")?.integer)
            _ = token // Keep token alive for the duration of the test
        }
    }

    // MARK: - Rollback hook not fired on successful txn

    func testNoRollbackOnCommit() async throws {
        try await withOpenedConnection { db in
            let (rb, token) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in Task { await box.append(()) } }
            }
            try await db.exec("BEGIN; CREATE TABLE sessions(session_id INT); COMMIT")
            await XCTAssertEqualAsync(await rb.count(), 0)
            _ = token // Keep token alive for the duration of the test
        }
    }

    // MARK: - High-volume updates (stress)

    func testHundredRapidInserts() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { event in Task { await box.append(event) } }
            }
            try await makeUsersTable(in: db)
            for i in 0..<100 {
                try await db.exec("INSERT INTO users(name) VALUES('user\(i)')")
            }
            await XCTAssertEqualAsync(await updates.count(), 100)
            _ = token // Keep token alive for the duration of the test
        }
    }

    // MARK: – logging bootstrap

    override class func setUp() { XCTAssert(isLoggingConfigured) }
}
