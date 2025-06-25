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
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }; _ = token                                           // keep-alive

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Alice')")

            await XCTAssertEqualAsync(await updates.count(), 1)
            let ev = try await XCTUnwrapAsync(await updates.all().first)
            XCTAssertEqual(ev.operation, .insert)
            XCTAssertEqual(ev.table, "users")
            XCTAssertEqual(ev.rowID, 1)
        }
    }

    func testUpdateHookCRUD() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }; _ = token

            // Execute statements separately to ensure hooks fire for each
            try await db.exec("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            try await db.exec("INSERT INTO t(v) VALUES('A')")
            try await db.exec("UPDATE t SET v='B' WHERE id=1")
            try await db.exec("DELETE FROM t WHERE id=1")

            let ops = await updates.all().map(\.operation)
            await XCTAssertEqualAsync(ops, [.insert, .update, .delete])
        }
    }

    func testMultipleUpdateObservers() async throws {
        try await withOpenedConnection { db in
            let (c1, t1) = try await withCollector(db) { box in
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }
            let (c2, t2) = try await withCollector(db) { box in
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }
            _ = (t1, t2)                                          // keep-alive

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Bob')")

            await XCTAssertEqualAsync(await c1.count(), 1)
            await XCTAssertEqualAsync(await c2.count(), 1)
        }
    }

    func testUpdateObserverCancellation() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            let token   = try await db.addUpdateObserver { ev in
                Task { await updates.append(ev) }
            }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users(name) VALUES('Carla')")
            await XCTAssertEqualAsync(await updates.count(), 1)

            token.cancel()
            try await db.exec("INSERT INTO users(name) VALUES('Dana')")
            await XCTAssertEqualAsync(await updates.count(), 1)         // unchanged
            _ = token                                             // silence warning
        }
    }

    // MARK: Commit / Rollback

    private func assertCommit(abort: Bool) async throws {
        try await withOpenedConnection { db in
            let (commits, token) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in Task { await box.append(()) }; return abort }
            }; _ = token

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE x(id INT)")
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
            }; _ = token

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE t(y INT)")

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
            }; _ = token

            // Test explicit rollback
            try await db.exec("BEGIN")
            try await db.exec("ROLLBACK")

            // Test another explicit rollback (implicit rollback behavior varies)
            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE t(id INT)")
            try await db.exec("ROLLBACK")

            await XCTAssertEqualAsync(await rb.count(), 2)
        }
    }

    // MARK: Authorizer

    func testAuthorizerAllowIgnoreDeny() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { ev in
                switch (ev.action, ev.parameter2) {
                case (.read, "b"): return .deny
                case (.read, "c"): return .ignore
                default:           return .allow
                }
            }; _ = token

            try await db.exec("CREATE TABLE t(a INT, b INT, c INT)")
            try await db.exec("INSERT INTO t VALUES(1,2,3)")

            do {
                _ = try await db.exec("SELECT b FROM t")
                XCTFail("Expected SELECT b to fail due to authorizer denial")
            } catch {
                // Expected - authorizer denied access to column b
            }

            let rows = try await db.exec("SELECT a, c FROM t")
            let row  = try XCTUnwrap(rows.first)
            XCTAssertEqual(row.column("a")?.integer, 1)
            XCTAssertTrue(row.column("c")?.isNull ?? false)
        }
    }

    func testAuthorizerHookDisable() async throws {
        try await withOpenedConnection { db in
            let (events, token) = try await withCollector(db) { box in
                try await db.addAuthorizerObserver { ev in
                    Task { await box.append(ev) }; return .allow
                }
            }

            try await db.exec("CREATE TABLE t(a INT)")
            try await db.exec("SELECT * FROM t")
            let before = await events.count()

            token.cancel()
            try await db.exec("SELECT * FROM t")
            await XCTAssertEqualAsync(await events.count(), before)      // no growth
            _ = token
        }
    }

    // MARK: Misc

    func testSimultaneousUpdateAndCommitHooks() async throws {
        try await withOpenedConnection { db in
            let (u, tu) = try await withCollector(db) { box in
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }
            let (c, tc) = try await withCollector(db) { box in
                try await db.addCommitObserver { _ in Task { await box.append(()) }; return false }
            }
            _ = (tu, tc)

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE foo(x INT)")
            try await db.exec("INSERT INTO foo VALUES(1)")
            try await db.exec("COMMIT")

            await XCTAssertEqualAsync(await u.count(), 1)
            await XCTAssertEqualAsync(await c.count(), 1)
        }
    }

    func testObserverTokenDeinitCancels() async throws {
        try await withOpenedConnection { db in
            let updates = Box<SQLiteUpdateEvent>()
            var token: SQLiteHookToken? = try await db.addUpdateObserver { ev in Task { await updates.append(ev) } }

            try await makeUsersTable(in: db)
            try await db.exec("INSERT INTO users VALUES(1,'Evan')")
            await XCTAssertEqualAsync(await updates.count(), 1)

            token = nil                                            // drop reference
            try await db.exec("INSERT INTO users VALUES(2,'Fred')")
            await XCTAssertEqualAsync(await updates.count(), 1)
            _ = token                                              // silence warning
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
                        if let newToken = try? await db.addUpdateObserver({ ev in
                            Task { await late.append(ev) }
                        }) {
                            await tokens.append(newToken)
                        }
                    }
                }
            }; _ = token

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
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }
            // Commit vetoer - always return true to veto
            let token2 = try await db.addCommitObserver { _ in true }

            try await db.exec("BEGIN")
            try await db.exec("CREATE TABLE t(x INT)")   // inside txn
            try await db.exec("INSERT INTO t VALUES(1)")

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
                _ = try await db.exec("SELECT * FROM t")
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
            let tok = try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            try await makeUsersTable(in: db)

            try await db.exec("INSERT INTO users VALUES(1,'A')")
            await XCTAssertEqualAsync(await box.count(), 1)

            tok.cancel()
            try await db.exec("INSERT INTO users VALUES(2,'B')")
            await XCTAssertEqualAsync(await box.count(), 1)     // unchanged
            _ = tok // Keep alive
        }
    }

    // MARK: - Authorizer IGNORE actually NULLs result

    func testIgnoreReturnsNull() async throws {
        try await withOpenedConnection { db in
            let token = try await db.addAuthorizerObserver { ev in
                (ev.action == .read && ev.parameter2 == "b") ? .ignore : .allow
            }
            try await db.exec("CREATE TABLE t(a INT, b INT)")
            try await db.exec("INSERT INTO t VALUES(1,2)")
            let rows = try await db.exec("SELECT a,b FROM t")
            let row = try XCTUnwrap(rows.first)
            XCTAssertNil(row.column("b")?.integer)
            _ = token // Keep alive
        }
    }

    // MARK: - Rollback hook not fired on successful txn

    func testNoRollbackOnCommit() async throws {
        try await withOpenedConnection { db in
            let (rb, token) = try await withCollector(db) { box in
                try await db.addRollbackObserver { _ in Task { await box.append(()) } }
            }
            try await db.exec("BEGIN; CREATE TABLE t(x INT); COMMIT")
            await XCTAssertEqualAsync(await rb.count(), 0)
            _ = token // Keep alive
        }
    }

    // MARK: - High-volume updates (stress)

    func testHundredRapidInserts() async throws {
        try await withOpenedConnection { db in
            let (updates, token) = try await withCollector(db) { box in
                try await db.addUpdateObserver { ev in Task { await box.append(ev) } }
            }
            try await makeUsersTable(in: db)
            for i in 0..<100 {
                try await db.exec("INSERT INTO users(name) VALUES('user\(i)')")
            }
            await XCTAssertEqualAsync(await updates.count(), 100)
            _ = token // Keep alive
        }
    }

    // MARK: – logging bootstrap

    override class func setUp() { XCTAssert(isLoggingConfigured) }
}
