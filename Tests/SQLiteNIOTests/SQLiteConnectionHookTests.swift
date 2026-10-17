import SQLiteNIO
import Testing
#if canImport(NIOCore)
import NIOConcurrencyHelpers
#endif

@Suite("SQLite Connection Hook Tests")
struct SQLiteConnectionHookTests {
    // MARK: Update

    @Test
    func updateHookInsert() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")

            #expect(updates.count() == 1)
            let event = try #require(updates.all().first)
            #expect(event.operation == .insert)
            #expect(event.table == "users")
            #expect(event.rowID == 1)
        }
    }

    @Test
    func updateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }

            try await db.exec("CREATE TABLE products(id INTEGER PRIMARY KEY, value TEXT)")
            try await db.exec("INSERT INTO products(value) VALUES('A')")
            try await db.exec("UPDATE products SET value='B' WHERE id=1")
            try await db.exec("DELETE FROM products WHERE id=1")

            #expect(updates.count() == 3)
            let ops = updates.all().map(\.operation)
            #expect(ops == [.insert, .update, .delete])
        }
    }

    @Test
    func multipleUpdateObservers() async throws {
        try await withOpenedConnection { db in
            let (c1, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }
            let (c2, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Bob')")

            #expect(c1.count() == 1)
            #expect(c2.count() == 1)
        }
    }

    @Test
    func updateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let token = try await db.addUpdateObserver(lifetime: .pinned) { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Carla')")
            #expect(updates.count() == 1)

            token.cancel()
            try await db.exec("INSERT INTO users(name) VALUES('Dana')")
            #expect(updates.count() == 1) // unchanged
        }
    }

    // MARK: Commit / Rollback

    private func assertCommit(abort: Bool, sourceLocation: SourceLocation = #_sourceLocation()) async throws {
        try await withOpenedConnection { db in
            let (commits, _) = try await withCollector(db) { box in
                try await db.setCommitValidator(lifetime: .pinned) { _ in box.append(()); return abort ? .deny : .allow }
            }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE items(id INT)")
            if abort {
                await #expect(throws: (any Error).self, sourceLocation: sourceLocation) { try await db.exec("COMMIT") }
            } else {
                try await db.exec("COMMIT")
            }
            #expect(commits.count() == 1)
        }
    }

    @Test
    func commitHookAllow()  async throws { try await assertCommit(abort: false) }

    @Test
    func commitHookAbort()  async throws { try await assertCommit(abort: true ) }

    @Test
    func commitObserversAggregateVeto() async throws {
        try await withOpenedConnection { db in
            _ = try await db.addCommitObserver(lifetime: .pinned) { _ in }
            let (vetoes, _) = try await withCollector(db) { box in
                try await db.setCommitValidator(lifetime: .pinned) { _ in box.append(()); return .deny }
            }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE orders(order_number INT)")
            await #expect(throws: (any Error).self) { try await db.exec("COMMIT") }
            #expect(vetoes.count() == 1)
        }
    }

    @Test
    func rollbackHookExplicitAndImplicit() async throws {
        try await withOpenedConnection { db in
            let (rb, _) = try await withCollector(db) { box in
                try await db.addRollbackObserver(lifetime: .pinned) { _ in box.append(()) }
            }

            try await db.exec("BEGIN")
            try await db.exec("ROLLBACK")

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE inventory(id INT)")
            try await db.exec("ROLLBACK")

            #expect(rb.count() == 2)
        }
    }

    // MARK: Authorizer

    @Test
    func authorizerAllowIgnoreDeny() async throws {
        try await withOpenedConnection { db in
            let _ = try await db.setAuthorizerValidator(lifetime: .pinned) { event in
                switch (event.action, event.parameter2) {
                case (.read, "content"):  .deny
                case (.read, "metadata"): .ignore
                default:                  .allow
                }
            }

            try await db.exec("CREATE TABLE documents(title INT, content INT, metadata INT)")
            try await db.exec("INSERT INTO documents VALUES(1,2,3)")

            await #expect(throws: (any Error).self) { _ = try await db.exec("SELECT content FROM documents") }

            let rows = try await db.exec("SELECT title, metadata FROM documents")
            let row  = try #require(rows.first)
            #expect(row.column("title")?.integer == 1)
            #expect(row.column("metadata")?.isNull ?? false)
        }
    }

    @Test
    func testAuthorizerHookDisable() async throws {
        try await withOpenedConnection { db in
            let (events, token) = try await withCollector(db) { box in
                try await db.addAuthorizerObserver(lifetime: .pinned) { event in box.append(event) }
            }

            try await db.exec("CREATE TABLE settings(value INT)")
            try await db.exec("SELECT * FROM settings")
            let before = events.count()

            token.cancel()
            try await db.exec("SELECT * FROM settings")
            #expect(events.count() == before) // no growth
        }
    }

    // MARK: Misc

    @Test
    func simultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let (u, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }
            let (c, _) = try await withCollector(db) { box in
                try await db.addCommitObserver(lifetime: .pinned) { _ in box.append(()) }
            }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE transactions(amount INT)")
            try await db.exec("INSERT INTO transactions VALUES(1)")
            try await db.exec("COMMIT")

            #expect(u.count() == 1)
            #expect(c.count() == 1)
        }
    }

    @Test
    func observerTokenDeinitCancels() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            var token: SQLiteHookToken? = try await db.addUpdateObserver(lifetime: .scoped) { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users VALUES(1,'Evan')")
            #expect(updates.count() == 1)

            token = nil // drop reference; deinit cancels
            _ = token // silence unused warning
            try await db.exec("INSERT INTO users VALUES(2,'Fred')")
            #expect(updates.count() == 1)
        }
    }

    // MARK: - Order-of-execution

    @Test
    func commitObserversCheckedAfterUpdateHooks() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }
            // Commit vetoer - always return .deny to veto
            let _ = try await db.setCommitValidator(lifetime: .pinned) { _ in .deny }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE logs(entry INT)") // inside txn
            try await db.exec("INSERT INTO logs VALUES(1)")

            await #expect(throws: (any Error).self) { try await db.exec("COMMIT") }

            #expect(updates.count() == 1)

            // Table should not exist after rollback
            await #expect(throws: (any Error).self) { _ = try await db.exec("SELECT * FROM logs") }
        }
    }

    // MARK: - No-hook-after-cancel

    @Test
    func cancelStopsFurtherEvents() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()
            let token = try await db.addUpdateObserver(lifetime: .scoped) { event in box.append(event) }
            try await makeUsersTable(in: db)

            try await db.exec("INSERT INTO users VALUES(1,'A')")
            #expect(box.count() == 1)

            token.cancel()
            try await db.exec("INSERT INTO users VALUES(2,'B')")
            #expect(box.count() == 1)     // unchanged
        }
    }

    // MARK: - Authorizer IGNORE actually NULLs result

    @Test
    func ignoreReturnsNull() async throws {
        try await withOpenedConnection { db in
            let _ = try await db.setAuthorizerValidator(lifetime: .pinned) { event in
                (event.action == .read && event.parameter2 == "secret") ? .ignore : .allow
            }

            try await db.exec("CREATE TABLE accounts(id INT, secret INT)")
            try await db.exec("INSERT INTO accounts VALUES(1,2)")
            let rows = try await db.exec("SELECT id,secret FROM accounts")
            let row = try #require(rows.first)
            #expect(row.column("secret")?.integer == nil)
        }
    }

    // MARK: - Rollback hook not fired on successful txn

    @Test
    func moRollbackOnCommit() async throws {
        try await withOpenedConnection { db in
            let (rb, _) = try await withCollector(db) { box in
                try await db.addRollbackObserver(lifetime: .pinned) { _ in box.append(()) }
            }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE sessions(session_id INT)")
            try await db.exec("COMMIT")

            #expect(rb.count() == 0)
        }
    }

    // MARK: - High-volume updates (stress)

    @Test
    func hundredRapidInserts() async throws {
        try await withOpenedConnection { db in
            let (updates, _) = try await withCollector(db) { box in
                try await db.addUpdateObserver(lifetime: .pinned) { event in box.append(event) }
            }

            try await makeUsersTable(in: db)
            for i in 0..<100 {
                try await db.exec("INSERT INTO users(name) VALUES('user\(i)')")
            }
            #expect(updates.count() == 100)
        }
    }

    // MARK: Scoped Observer Tests

    @Test
    func withUpdateObserverScopesRegistration() async throws {
        try await withOpenedConnection { db in
            let box = Box<SQLiteUpdateEvent>()

            try await db.withUpdateObserver({ event in box.append(event) }) {
                try await makeUsersTable(in: db)  // DDL doesn't fire update hooks
                try await db.exec("INSERT INTO users(name) VALUES('Scoped')")  // DML fires update hooks
            }

            #expect(box.count() == 1)  // Only the INSERT fires the hook

            try await db.exec("INSERT INTO users(name) VALUES('Outside')")
            #expect(box.count() == 1)
        }
    }

    @Test
    func commitObserversSkippedOnVeto() async throws {
        try await withOpenedConnection { db in
            let runCount = Box<Void>()

            let _ = try await db.setCommitValidator(lifetime: .pinned) { _ in runCount.append(()); return .deny  } // veto
            let _ = try await db.addCommitObserver(lifetime: .pinned) { _ in runCount.append(()) }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test_table(x INT)")

            await #expect(throws: (any Error).self) { try await db.exec("COMMIT") }

            #expect(runCount.count() == 1) // Only validator should run, observer skipped on veto
        }
    }

    // NOTE: Removed testAuthorizerMultipleObserversAggregation -
    // With single validator design, multiple validators no longer supported

    // MARK: - New API Tests

    @Test
    func pinnedTokenDroppedObserverPersists() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            // Drop token immediately - observer should persist since lifetime is .pinned
            _ = try await db.addUpdateObserver(lifetime: .pinned) { event in updates.append(event) }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")
            #expect(updates.count() == 1) // Observer should still work
        }
    }

    @Test
    func tokensNoOpAfterConnectionClose() async throws {
        let updates = Box<SQLiteUpdateEvent>()
        var token: SQLiteHookToken?

        let connection = try await SQLiteConnection.open(storage: .memory)
        token = try await connection.addUpdateObserver(lifetime: .scoped) { event in updates.append(event) }

        try await connection.close()

        // Token should now be a no-op
        token?.cancel() // Should not crash or cause issues
        #expect(updates.count() == 0)
    }

    @Test
    func validatorReplacementAndCancellation() async throws {
        try await withOpenedConnection { db in
            let calls1 = Box<Void>()
            let calls2 = Box<Void>()

            // Set first validator
            let token1 = try await db.setCommitValidator(lifetime: .scoped) { _ in calls1.append(()); return .allow }

            // First validator should work
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test1(id INT)")
            try await db.exec("COMMIT")
            #expect(calls1.count() == 1)

            // Replace with second validator
            let token2 = try await db.setCommitValidator(lifetime: .scoped) { _ in calls2.append(()); return .allow }

            // Only second validator should be called now
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test2(id INT)")
            try await db.exec("COMMIT")
            #expect(calls1.count() == 1) // Should still be 1 (no new calls)
            #expect(calls2.count() == 1) // Second validator called

            // Cancel second validator
            token2.cancel()

            // No validator should be called now
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test3(id INT)")
            try await db.exec("COMMIT")
            #expect(calls1.count() == 1) // Still 1
            #expect(calls2.count() == 1) // Still 1

            // Clean up first token (should be no-op since it was replaced)
            token1.cancel()
        }
    }

    @Test
    func multipleObserversWithValidator() async throws {
        try await withOpenedConnection { db in
            let observer1 = Box<Void>()
            let observer2 = Box<Void>()
            let validatorCalls = Box<Void>()

            _ = try await db.addCommitObserver(lifetime: .pinned) { _ in observer1.append(()) }
            _ = try await db.setCommitValidator(lifetime: .pinned) { _ in validatorCalls.append(()); return .allow }
            _ = try await db.addCommitObserver(lifetime: .pinned) { _ in observer2.append(()) }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE test(id INT)")
            try await db.exec("COMMIT")

            #expect(validatorCalls.count() == 1)
            #expect(observer1.count() == 1) // Both observers should run
            #expect(observer2.count() == 1)
        }
    }

    // MARK: – logging bootstrap

    init() {
        #expect(isLoggingConfigured)
    }
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
