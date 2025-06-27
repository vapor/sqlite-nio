import Foundation
import NIOConcurrencyHelpers
import NIOCore
import CSQLite

// MARK: - Hook Types and Events

/// Represents the type of update operation that triggered the update hook.
public enum SQLiteUpdateOperation: Int32, Sendable {
    /// An INSERT operation.
    case insert = 18 // SQLITE_INSERT
    /// An UPDATE operation.
    case update = 23 // SQLITE_UPDATE
    /// A DELETE operation.
    case delete = 9  // SQLITE_DELETE
}

/// Event produced by the update hook.
///
/// Contains information about a database modification operation that triggered an update hook.
public struct SQLiteUpdateEvent: Sendable {
    /// The type of database operation that was performed.
    public let operation: SQLiteUpdateOperation
    /// The name of the database that was modified.
    public let database: String
    /// The name of the table that was modified.
    public let table: String
    /// The rowid of the row that was affected by the operation.
    public let rowID: Int64
}

/// Represents the type of database access being authorized.
public enum SQLiteAuthorizerAction: Int32, Sendable {
    /// Create index.
    case createIndex = 1 // SQLITE_CREATE_INDEX
    /// Create table.
    case createTable = 2 // SQLITE_CREATE_TABLE
    /// Create temporary index.
    case createTempIndex = 3 // SQLITE_CREATE_TEMP_INDEX
    /// Create temporary table.
    case createTempTable = 4 // SQLITE_CREATE_TEMP_TABLE
    /// Create temporary trigger.
    case createTempTrigger = 5 // SQLITE_CREATE_TEMP_TRIGGER
    /// Create temporary view.
    case createTempView = 6 // SQLITE_CREATE_TEMP_VIEW
    /// Create trigger.
    case createTrigger = 7 // SQLITE_CREATE_TRIGGER
    /// Create view.
    case createView = 8 // SQLITE_CREATE_VIEW
    /// Delete from table.
    case delete = 9 // SQLITE_DELETE
    /// Drop index.
    case dropIndex = 10 // SQLITE_DROP_INDEX
    /// Drop table.
    case dropTable = 11 // SQLITE_DROP_TABLE
    /// Drop temporary index.
    case dropTempIndex = 12 // SQLITE_DROP_TEMP_INDEX
    /// Drop temporary table.
    case dropTempTable = 13 // SQLITE_DROP_TEMP_TABLE
    /// Drop temporary trigger.
    case dropTempTrigger = 14 // SQLITE_DROP_TEMP_TRIGGER
    /// Drop temporary view.
    case dropTempView = 15 // SQLITE_DROP_TEMP_VIEW
    /// Drop trigger.
    case dropTrigger = 16 // SQLITE_DROP_TRIGGER
    /// Drop view.
    case dropView = 17 // SQLITE_DROP_VIEW
    /// Insert into table.
    case insert = 18 // SQLITE_INSERT
    /// Pragma statement.
    case pragma = 19 // SQLITE_PRAGMA
    /// Read from table/column.
    case read = 20 // SQLITE_READ
    /// Select statement.
    case select = 21 // SQLITE_SELECT
    /// Transaction operation.
    case transaction = 22 // SQLITE_TRANSACTION
    /// Update table/column.
    case update = 23 // SQLITE_UPDATE
    /// Attach database.
    case attach = 24 // SQLITE_ATTACH
    /// Detach database.
    case detach = 25 // SQLITE_DETACH
    /// Alter table.
    case alterTable = 26 // SQLITE_ALTER_TABLE
    /// Reindex.
    case reindex = 27 // SQLITE_REINDEX
    /// Analyze.
    case analyze = 28 // SQLITE_ANALYZE
    /// Create virtual table.
    case createVTable = 29 // SQLITE_CREATE_VTABLE
    /// Drop virtual table.
    case dropVTable = 30 // SQLITE_DROP_VTABLE
    /// Function call.
    case function = 31 // SQLITE_FUNCTION
    /// Savepoint operation.
    case savepoint = 32 // SQLITE_SAVEPOINT
    /// Copy operation.
    case copy = 33 // SQLITE_COPY
    /// Recursive operation.
    case recursive = 34 // SQLITE_RECURSIVE
}

/// The response from an authorizer callback.
public enum SQLiteAuthorizerResponse: Int32, Sendable {
    /// Allow the operation.
    case allow = 0 // SQLITE_OK
    /// Deny the operation.
    case deny = 1 // SQLITE_DENY
    /// Ignore the operation (treat column as NULL).
    case ignore = 2 // SQLITE_IGNORE
}

/// Event produced by the authorizer hook.
///
/// Contains information about a database access attempt that requires authorization.
public struct SQLiteAuthorizerEvent: Sendable {
    /// The type of database access being attempted.
    public let action: SQLiteAuthorizerAction
    /// The first parameter (meaning depends on action).
    public let parameter1: String?
    /// The second parameter (meaning depends on action).
    public let parameter2: String?
    /// The database name.
    public let database: String?
    /// The trigger or view name that caused the access.
    public let trigger: String?
}

// MARK: - Commit & Rollback events

/// Event produced by the commit hook.
///
/// Contains information about a transaction commit that is about to occur.
public struct SQLiteCommitEvent: Sendable {
    /// Timestamp (in the connection's wall-clock) when the commit was about to occur.
    public let date: Date = Date()
}

/// Event produced by the rollback hook.
///
/// Contains information about a transaction rollback that has occurred.
public struct SQLiteRollbackEvent: Sendable {
    /// Timestamp (in the connection's wall-clock) when the rollback happened.
    public let date: Date = Date()
}

// MARK: - Hook token

/// Returned by every `add*Observer(…)` call. Call `cancel()` (or just let the
/// token fall out of scope) to unregister its associated callback.
///
/// ## Important: Token Lifetime
///
/// **The observer remains active only as long as this token is retained.**
/// If you don't store the token in a variable, the observer will be immediately
/// deinitialized and stop working:
///
/// ```swift
/// // ❌ WRONG - Observer stops immediately
/// _ = try await connection.addUpdateObserver { event in
///     print("This will never be called!")
/// }
///
/// // ✅ CORRECT - Observer stays active
/// let token = try await connection.addUpdateObserver { event in
///     print("This will be called for updates")
/// }
/// // Keep token alive as long as you need the observer
/// ```
///
/// Hook tokens automatically cancel themselves when deallocated, ensuring that
/// callbacks are properly cleaned up even if `cancel()` is not called explicitly.
public final class SQLiteHookToken: Sendable {
    private let cancelBlock: @Sendable () -> Void

    internal init(cancel: @escaping @Sendable () -> Void) {
        self.cancelBlock = cancel
    }

    /// Cancels the associated hook callback.
    ///
    /// After calling this method, the callback will no longer be invoked.
    /// It is safe to call this method multiple times.
    public func cancel() {
        cancelBlock()
    }

    deinit {
        cancelBlock()
    }
}

// MARK: - Type aliases used by clients

extension SQLiteConnection {
    /// The type signature for update hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteUpdateEvent`` containing details about the database modification.
    public typealias SQLiteUpdateHookCallback = @Sendable (SQLiteUpdateEvent) -> Void

    /// The type signature for commit hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    /// - Returns: `true` to abort the commit, `false` to allow it to proceed.
    public typealias SQLiteCommitHookCallback = @Sendable (SQLiteCommitEvent) -> Bool

    /// The type signature for rollback hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteRollbackEvent`` containing details about the rollback.
    public typealias SQLiteRollbackHookCallback = @Sendable (SQLiteRollbackEvent) -> Void

    /// The type signature for authorizer hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    /// - Returns: A ``SQLiteAuthorizerResponse`` indicating whether to allow, deny, or ignore the operation.
    public typealias SQLiteAuthorizerHookCallback = @Sendable (SQLiteAuthorizerEvent) -> SQLiteAuthorizerResponse
}

// MARK: - Observer Registration (Synchronous API)

extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// The update hook is triggered whenever a row is inserted, updated, or deleted
    /// in the database. Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let token = connection.addUpdateObserver { event in
    ///     print("\(event.table) row \(event.row.rawValue) was \(event.operation)")
    /// }
    /// // Later, to unregister:
    /// token.cancel()
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addUpdateObserver(_ callback: @escaping SQLiteUpdateHookCallback) -> SQLiteHookToken {
        let id = UUID()
        withBuckets { $0.update[id] = callback }
        installDispatcherIfNeeded()
        return SQLiteHookToken { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.update.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .update)
        }
    }

    /// Register an observer for the SQLite *commit* hook.
    ///
    /// The commit hook is invoked whenever a transaction is about to be committed.
    /// If **any** observer returns `true`, the commit is aborted and the transaction
    /// is rolled back.
    ///
    /// ```swift
    /// let token = connection.addCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addCommitObserver(_ callback: @escaping SQLiteCommitHookCallback) -> SQLiteHookToken {
        let id = UUID()
        withBuckets { $0.commit[id] = callback }
        installDispatcherIfNeeded()
        return SQLiteHookToken { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.commit.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .commit)
        }
    }

    /// Register an observer for the SQLite *rollback* hook.
    ///
    /// The rollback hook is invoked whenever a transaction is rolled back.
    /// Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let token = connection.addRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addRollbackObserver(_ callback: @escaping SQLiteRollbackHookCallback) -> SQLiteHookToken {
        let id = UUID()
        withBuckets { $0.rollback[id] = callback }
        installDispatcherIfNeeded()
        return SQLiteHookToken { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.rollback.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .rollback)
        }
    }

    /// Register an observer for the SQLite *authorizer* hook.
    ///
    /// The authorizer hook is called during statement preparation to authorize
    /// database access operations. This enables precise read-set detection and
    /// access control at the table/column level.
    ///
    /// When multiple observers are registered, the most restrictive response is used:
    /// - If any observer returns `.deny`, the operation is denied
    /// - If any observer returns `.ignore` (and none return `.deny`), the operation is ignored
    /// - Otherwise, the operation is allowed
    ///
    /// ```swift
    /// let token = connection.addAuthorizerObserver { event in
    ///     if event.action == .read {
    ///         print("Reading from \(event.parameter1 ?? "unknown") table")
    ///     }
    ///     return .allow
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addAuthorizerObserver(_ callback: @escaping SQLiteAuthorizerHookCallback) -> SQLiteHookToken {
        let id = UUID()
        withBuckets { $0.authorizer[id] = callback }
        installDispatcherIfNeeded()
        return SQLiteHookToken { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.authorizer.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .authorizer)
        }
    }
}

// MARK: - Observer Registration (Async API)

extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// The update hook is triggered whenever a row is inserted, updated, or deleted
    /// in the database. Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let token = try await connection.addUpdateObserver { event in
    ///     print("\(event.table) row \(event.row.rawValue) was \(event.operation)")
    /// }
    /// // Later, to unregister:
    /// token.cancel()
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addUpdateObserver(_ callback: @escaping SQLiteUpdateHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.update[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.update.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .update)
            }
        }
    }

    /// Register an observer for the SQLite *commit* hook.
    ///
    /// The commit hook is invoked whenever a transaction is about to be committed.
    /// If **any** observer returns `true`, the commit is aborted and the transaction
    /// is rolled back.
    ///
    /// ```swift
    /// let token = try await connection.addCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addCommitObserver(_ callback: @escaping SQLiteCommitHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.commit[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.commit.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .commit)
            }
        }
    }

    /// Register an observer for the SQLite *rollback* hook.
    ///
    /// The rollback hook is invoked whenever a transaction is rolled back.
    /// Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let token = try await connection.addRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addRollbackObserver(_ callback: @escaping SQLiteRollbackHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.rollback[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.rollback.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .rollback)
            }
        }
    }

    /// Register an observer for the SQLite *authorizer* hook.
    ///
    /// The authorizer hook is called during statement preparation to authorize
    /// database access operations. This enables precise read-set detection and
    /// access control at the table/column level.
    ///
    /// When multiple observers are registered, the most restrictive response is used:
    /// - If any observer returns `.deny`, the operation is denied
    /// - If any observer returns `.ignore` (and none return `.deny`), the operation is ignored
    /// - Otherwise, the operation is allowed
    ///
    /// ```swift
    /// let token = try await connection.addAuthorizerObserver { event in
    ///     if event.action == .read {
    ///         print("Reading from \(event.parameter1 ?? "unknown") table")
    ///     }
    ///     return .allow
    /// }
    /// ```
    ///
    /// - Parameter callback: The closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when cancelled.
    public func addAuthorizerObserver(_ callback: @escaping SQLiteAuthorizerHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.authorizer[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.authorizer.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .authorizer)
            }
        }
    }
}

// MARK: - Scoped Observer Helpers

extension SQLiteConnection {
    /// Execute a block with a temporary update observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes,
    /// making this ideal for testing or temporary observation scenarios.
    ///
    /// ```swift
    /// connection.withUpdateObserver({ event in
    ///     print("Update: \(event)")
    /// }) {
    ///     // All database operations in this block will trigger the observer
    ///     _ = try connection.query("INSERT INTO users(name) VALUES('Alice')", []).wait()
    ///     // Observer is automatically cleaned up when block exits
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withUpdateObserver<T>(
        _ callback: @escaping SQLiteUpdateHookCallback,
        body: () throws -> T
    ) rethrows -> T {
        let token = addUpdateObserver(callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary update observer (async version).
    ///
    /// The observer is automatically removed when the block completes,
    /// making this ideal for testing or temporary observation scenarios.
    ///
    /// ```swift
    /// try await connection.withUpdateObserver({ event in
    ///     print("Update: \(event)")
    /// }) {
    ///     // All database operations in this block will trigger the observer
    ///     _ = try await connection.query("INSERT INTO users(name) VALUES('Alice')", [])
    ///     _ = try await connection.query("UPDATE users SET name='Bob' WHERE id=1", [])
    ///     // Observer is automatically cleaned up when block exits
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withUpdateObserver<T>(
        _ callback: @escaping SQLiteUpdateHookCallback,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addUpdateObserver(callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary commit observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withCommitObserver<T>(
        _ callback: @escaping SQLiteCommitHookCallback,
        body: () throws -> T
    ) rethrows -> T {
        let token = addCommitObserver(callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary commit observer (async version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withCommitObserver<T>(
        _ callback: @escaping SQLiteCommitHookCallback,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addCommitObserver(callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary rollback observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withRollbackObserver<T>(
        _ callback: @escaping SQLiteRollbackHookCallback,
        body: () throws -> T
    ) rethrows -> T {
        let token = addRollbackObserver(callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary rollback observer (async version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withRollbackObserver<T>(
        _ callback: @escaping SQLiteRollbackHookCallback,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addRollbackObserver(callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary authorizer observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withAuthorizerObserver<T>(
        _ callback: @escaping SQLiteAuthorizerHookCallback,
        body: () throws -> T
    ) rethrows -> T {
        let token = addAuthorizerObserver(callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary authorizer observer (async version).
    ///
    /// The observer is automatically removed when the block completes.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withAuthorizerObserver<T>(
        _ callback: @escaping SQLiteAuthorizerHookCallback,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addAuthorizerObserver(callback)
        defer { token.cancel() }
        return try await body()
    }
}

// MARK: - Private per-connection observer store

extension SQLiteConnection {
    struct ObserverBuckets: Sendable {
        var update: [UUID: SQLiteUpdateHookCallback] = [:]
        var commit: [UUID: SQLiteCommitHookCallback] = [:]
        var rollback: [UUID: SQLiteRollbackHookCallback] = [:]
        var authorizer: [UUID: SQLiteAuthorizerHookCallback] = [:]

        // Track whether low-level dispatchers are installed
        var updateDispatcherInstalled = false
        var commitDispatcherInstalled = false
        var rollbackDispatcherInstalled = false
        var authorizerDispatcherInstalled = false
    }

    // Convenience to mutate buckets
    @discardableResult
    private func withBuckets<T>(_ body: (inout ObserverBuckets) -> T) -> T {
        observerBuckets.withLockedValue(body)
    }
}

// MARK: - Dispatcher install / uninstall helpers

extension SQLiteConnection {
    private enum HookKind {
        case update, commit, rollback, authorizer
    }

    private func installDispatcherIfNeeded() {
        withBuckets { buckets in
            // Install update hook dispatcher if needed
            if !buckets.updateDispatcherInstalled && !buckets.update.isEmpty {
                buckets.updateDispatcherInstalled = true
                applyUpdateHook(enabled: true)
            }

            // Install commit hook dispatcher if needed
            if !buckets.commitDispatcherInstalled && !buckets.commit.isEmpty {
                buckets.commitDispatcherInstalled = true
                applyCommitHook(enabled: true)
            }

            // Install rollback hook dispatcher if needed
            if !buckets.rollbackDispatcherInstalled && !buckets.rollback.isEmpty {
                buckets.rollbackDispatcherInstalled = true
                applyRollbackHook(enabled: true)
            }

            // Install authorizer hook dispatcher if needed
            if !buckets.authorizerDispatcherInstalled && !buckets.authorizer.isEmpty {
                buckets.authorizerDispatcherInstalled = true
                applyAuthorizerHook(enabled: true)
            }
        }
    }

    /// Called after **removing** an observer to tear down the C-hook if nobody
    /// is listening any longer.
    private func uninstallDispatcherIfNeeded(kind: HookKind) {
        withBuckets { buckets in
            switch kind {
            case .update where buckets.update.isEmpty && buckets.updateDispatcherInstalled:
                buckets.updateDispatcherInstalled = false
                applyUpdateHook(enabled: false)
            case .commit where buckets.commit.isEmpty && buckets.commitDispatcherInstalled:
                buckets.commitDispatcherInstalled = false
                applyCommitHook(enabled: false)
            case .rollback where buckets.rollback.isEmpty && buckets.rollbackDispatcherInstalled:
                buckets.rollbackDispatcherInstalled = false
                applyRollbackHook(enabled: false)
            case .authorizer where buckets.authorizer.isEmpty && buckets.authorizerDispatcherInstalled:
                buckets.authorizerDispatcherInstalled = false
                applyAuthorizerHook(enabled: false)
            default:
                break
            }
        }
    }
}

// MARK: - Low-level C-hook plumbing

extension SQLiteConnection {
    fileprivate func applyUpdateHook(enabled: Bool) {
        if enabled {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_update_hook(handle.raw, { ctx, op, db, tbl, row in
                guard
                    let ctx,
                    let dbPtr = db,
                    let tblPtr = tbl,
                    let opEnum = SQLiteUpdateOperation(rawValue: op)
                else { return }
                let conn = Unmanaged<SQLiteConnection>.fromOpaque(ctx).takeUnretainedValue()
                let event = SQLiteUpdateEvent(operation: opEnum,
                                              database: String(cString: dbPtr),
                                              table: String(cString: tblPtr),
                                              rowID: row)
                // Dispatch to all registered update observers
                conn.withBuckets { buckets in
                    buckets.update.values.forEach { $0(event) }
                }
            }, ctx)
        } else {
            _ = sqlite_nio_sqlite3_update_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyCommitHook(enabled: Bool) {
        if enabled {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_commit_hook(handle.raw, { ctx in
                guard let ctx else { return 0 }
                let conn = Unmanaged<SQLiteConnection>.fromOpaque(ctx).takeUnretainedValue()
                let event = SQLiteCommitEvent()
                // Dispatch to all registered commit observers
                let veto = conn.withBuckets { buckets in
                    buckets.commit.values.contains { $0(event) }
                }
                return veto ? 1 : 0
            }, ctx)
        } else {
            _ = sqlite_nio_sqlite3_commit_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyRollbackHook(enabled: Bool) {
        if enabled {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            sqlite_nio_sqlite3_rollback_hook(handle.raw, { ctx in
                guard let ctx else { return }
                let conn = Unmanaged<SQLiteConnection>.fromOpaque(ctx).takeUnretainedValue()
                let event = SQLiteRollbackEvent()
                // Dispatch to all registered rollback observers
                conn.withBuckets { buckets in
                    buckets.rollback.values.forEach { $0(event) }
                }
            }, ctx)
        } else {
            sqlite_nio_sqlite3_rollback_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyAuthorizerHook(enabled: Bool) {
        if enabled {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_set_authorizer(handle.raw, { ctx, action, p1, p2, db, trg in
                guard let ctx, let kind = SQLiteAuthorizerAction(rawValue: action) else { return 1 } // SQLITE_DENY
                let conn = Unmanaged<SQLiteConnection>.fromOpaque(ctx).takeUnretainedValue()
                let event = SQLiteAuthorizerEvent(action: kind,
                                                  parameter1: p1.map { String(cString: $0) },
                                                  parameter2: p2.map { String(cString: $0) },
                                                  database: db.map { String(cString: $0) },
                                                  trigger: trg.map { String(cString: $0) })
                // Dispatch to all registered authorizer observers and aggregate results
                let result = conn.withBuckets { buckets in
                    // Aggregation rules: DENY > IGNORE > ALLOW
                    var result: SQLiteAuthorizerResponse = .allow
                    for response in buckets.authorizer.values.lazy.map({ $0(event) }) {
                        switch response {
                        case .deny:
                            return SQLiteAuthorizerResponse.deny    // short-circuit
                        case .ignore:
                            result = .ignore // keep going; maybe someone denies
                        case .allow:
                            continue
                        }
                    }
                    return result
                }
                return result.rawValue
            }, ctx)
        } else {
            _ = sqlite_nio_sqlite3_set_authorizer(handle.raw, nil, nil)
        }
    }

    /// Clears C-level hooks + Swift buckets when connection closes
    func clearAllHooks() {
        applyUpdateHook(enabled: false)
        applyCommitHook(enabled: false)
        applyRollbackHook(enabled: false)
        applyAuthorizerHook(enabled: false)
        observerBuckets.withLockedValue { $0 = ObserverBuckets() }
    }
}
