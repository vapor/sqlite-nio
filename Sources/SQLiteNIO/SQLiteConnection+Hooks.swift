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

extension SQLiteConnection {
    /// The type signature for update hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteUpdateEvent`` containing details about the database modification.
    public typealias SQLiteUpdateHookCallback = @Sendable (SQLiteUpdateEvent) -> Void

    /// The type signature for commit hook callbacks.
    ///
    /// - Returns: `true` to abort the commit, `false` to allow it to proceed.
    public typealias SQLiteCommitHookCallback = @Sendable () -> Bool

    /// The type signature for rollback hook callbacks.
    public typealias SQLiteRollbackHookCallback = @Sendable () -> Void
}

// MARK: - Hook Management (Futures API)

extension SQLiteConnection {
    /// Installs **or replaces** the single SQLite *update-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// ```swift
    /// connection
    ///     .setUpdateHook { event in
    ///         print("\(event.table) row \(event.rowID) was \(event.operation)")
    ///     }
    ///     .whenSuccess { print("hook installed") }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setUpdateHook(
        _ callback: SQLiteUpdateHookCallback?
    ) -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            self._applyUpdateHook(callback)
        }
    }

    /// Installs **or replaces** the single SQLite *commit-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// The commit hook is invoked whenever a transaction is about to be committed.
    /// If the callback returns `true`, the commit is aborted and the transaction
    /// is rolled back.
    ///
    /// ```swift
    /// connection
    ///     .setCommitHook {
    ///         // Perform validation logic here
    ///         return false // Allow commit to proceed
    ///     }
    ///     .whenSuccess { print("commit hook installed") }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setCommitHook(
        _ callback: SQLiteCommitHookCallback?
    ) -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            self._applyCommitHook(callback)
        }
    }

    /// Installs **or replaces** the single SQLite *rollback-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// The rollback hook is invoked whenever a transaction is rolled back.
    ///
    /// ```swift
    /// connection
    ///     .setRollbackHook {
    ///         print("Transaction was rolled back")
    ///     }
    ///     .whenSuccess { print("rollback hook installed") }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setRollbackHook(
        _ callback: SQLiteRollbackHookCallback?
    ) -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            self._applyRollbackHook(callback)
        }
    }
}

// MARK: - Hook Management (Async API)

extension SQLiteConnection {
    /// Installs **or replaces** the single SQLite *update-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// ```swift
    /// try await connection.setUpdateHook { event in
    ///     print("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setUpdateHook(
        _ callback: SQLiteUpdateHookCallback?
    ) async throws {
        try await self.threadPool.runIfActive {
            self._applyUpdateHook(callback)
        }
    }

    /// Installs **or replaces** the single SQLite *commit-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// ```swift
    /// try await connection.setCommitHook {
    ///     // Perform validation logic here
    ///     return false // Allow commit to proceed
    /// }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setCommitHook(
        _ callback: SQLiteCommitHookCallback?
    ) async throws {
        try await self.threadPool.runIfActive {
            self._applyCommitHook(callback)
        }
    }

    /// Installs **or replaces** the single SQLite *rollback-hook* for this
    /// connection. Call again to replace the existing callback; pass `nil`
    /// to remove it.
    ///
    /// ```swift
    /// try await connection.setRollbackHook {
    ///     print("Transaction was rolled back")
    /// }
    /// ```
    /// - Parameter callback: The closure to invoke, or `nil` to remove it.
    public func setRollbackHook(
        _ callback: SQLiteRollbackHookCallback?
    ) async throws {
        try await self.threadPool.runIfActive {
            self._applyRollbackHook(callback)
        }
    }
}

// MARK: - Private Implementation

extension SQLiteConnection {
    /// Installs, replaces, or removes the C-level update hook and stores the Swift callback.
    fileprivate func _applyUpdateHook(_ callback: SQLiteUpdateHookCallback?) {
        // Persist (or clear) the Swift callback atomically.
        self.updateHookCallback.withLockedValue { $0 = callback }

        if callback != nil {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_update_hook(
                self.handle.raw,
                { ctx, op, db, tbl, row in
                    guard
                        let ctx    = ctx,
                        let dbPtr  = db,
                        let tblPtr = tbl,
                        let opEnum = SQLiteUpdateOperation(rawValue: op)
                    else { return }

                    let conn = Unmanaged<SQLiteConnection>
                        .fromOpaque(ctx)
                        .takeUnretainedValue()

                    // Snapshot under the lock to avoid races.
                    guard let cb = conn.updateHookCallback
                        .withLockedValue({ $0 })
                    else { return }

                    cb(SQLiteUpdateEvent(operation: opEnum,
                                         database: String(cString: dbPtr),
                                         table: String(cString: tblPtr),
                                         rowID: row))
                },
                ctx)
        } else {
            // Unregister the C-level hook when callback is `nil`.
            _ = sqlite_nio_sqlite3_update_hook(self.handle.raw, nil, nil)
        }
    }

    /// Installs, replaces, or removes the C-level commit hook and stores the Swift callback.
    fileprivate func _applyCommitHook(_ callback: SQLiteCommitHookCallback?) {
        // Persist (or clear) the Swift callback atomically.
        self.commitHookCallback.withLockedValue { $0 = callback }

        if callback != nil {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_commit_hook(
                self.handle.raw,
                { ctx in
                    guard let ctx = ctx else { return 0 }

                    let conn = Unmanaged<SQLiteConnection>
                        .fromOpaque(ctx)
                        .takeUnretainedValue()

                    // Snapshot under the lock to avoid races.
                    guard let cb = conn.commitHookCallback
                        .withLockedValue({ $0 })
                    else { return 0 }

                    return cb() ? 1 : 0 // 1 = abort, 0 = allow
                },
                ctx)
        } else {
            // Unregister the C-level hook when callback is `nil`.
            _ = sqlite_nio_sqlite3_commit_hook(self.handle.raw, nil, nil)
        }
    }

    /// Installs, replaces, or removes the C-level rollback hook and stores the Swift callback.
    fileprivate func _applyRollbackHook(_ callback: SQLiteRollbackHookCallback?) {
        // Persist (or clear) the Swift callback atomically.
        self.rollbackHookCallback.withLockedValue { $0 = callback }

        if callback != nil {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            sqlite_nio_sqlite3_rollback_hook(
                self.handle.raw,
                { ctx in
                    // Previous hook pointer returned by sqlite3_rollback_hook, currently ignored
                    guard let ctx = ctx else { return }

                    let conn = Unmanaged<SQLiteConnection>
                        .fromOpaque(ctx)
                        .takeUnretainedValue()

                    // Snapshot under the lock to avoid races.
                    guard let cb = conn.rollbackHookCallback
                        .withLockedValue({ $0 })
                    else { return }

                    cb()
                },
                ctx)
        } else {
            // Unregister the C-level hook when callback is `nil`.
            // Previous hook pointer returned by sqlite3_rollback_hook, currently ignored
            sqlite_nio_sqlite3_rollback_hook(self.handle.raw, nil, nil)
        }
    }

    /// Clear all hooks when connection is being closed.
    func _clearAllHooks() {
        self._applyUpdateHook(nil)
        self._applyCommitHook(nil)
        self._applyRollbackHook(nil)
    }
}
