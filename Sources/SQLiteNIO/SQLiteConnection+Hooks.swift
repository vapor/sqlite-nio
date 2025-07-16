import Foundation
import NIOConcurrencyHelpers
import NIOCore
import CSQLite

// MARK: - Observer API Overview

/// ## SQLite Observer API Summary
///
/// | API | Lifetime | Auto-cleanup? | Needs Retention? | Cancel Method |
/// |-----|----------|---------------|------------------|---------------|
/// | `add…Observer` | RAII | Yes (token deinit) | Retain ``SQLiteHookToken`` | `token.cancel()` |
/// | `install…Observer` | Persistent | No | Retain ``SQLiteObserverID`` if you intend to remove | `removeObserver` |
/// | `with…Observer` | Scoped | Auto (defer cancel) | No (internal) | _N/A_ |

// MARK: - Hook Types and Events

/// Represents the type of update operation that triggered the update hook.
public struct SQLiteUpdateOperation: Sendable, Hashable {
    /// The raw SQLite operation code.
    public let rawValue: Int32

    /// Creates a new SQLiteUpdateOperation with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known operations.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// An INSERT operation.
    public static let insert = SQLiteUpdateOperation(rawValue: SQLITE_INSERT)
    /// An UPDATE operation.
    public static let update = SQLiteUpdateOperation(rawValue: SQLITE_UPDATE)
    /// A DELETE operation.
    public static let delete = SQLiteUpdateOperation(rawValue: SQLITE_DELETE)
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
public struct SQLiteAuthorizerAction: Sendable, Hashable {
    /// The raw SQLite action code.
    public let rawValue: Int32

    /// Creates a new SQLiteAuthorizerAction with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known actions.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Create index.
    public static let createIndex = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_INDEX)
    /// Create table.
    public static let createTable = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TABLE)
    /// Create temporary index.
    public static let createTempIndex = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TEMP_INDEX)
    /// Create temporary table.
    public static let createTempTable = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TEMP_TABLE)
    /// Create temporary trigger.
    public static let createTempTrigger = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TEMP_TRIGGER)
    /// Create temporary view.
    public static let createTempView = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TEMP_VIEW)
    /// Create trigger.
    public static let createTrigger = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_TRIGGER)
    /// Create view.
    public static let createView = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_VIEW)
    /// Delete from table.
    public static let delete = SQLiteAuthorizerAction(rawValue: SQLITE_DELETE)
    /// Drop index.
    public static let dropIndex = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_INDEX)
    /// Drop table.
    public static let dropTable = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TABLE)
    /// Drop temporary index.
    public static let dropTempIndex = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TEMP_INDEX)
    /// Drop temporary table.
    public static let dropTempTable = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TEMP_TABLE)
    /// Drop temporary trigger.
    public static let dropTempTrigger = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TEMP_TRIGGER)
    /// Drop temporary view.
    public static let dropTempView = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TEMP_VIEW)
    /// Drop trigger.
    public static let dropTrigger = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_TRIGGER)
    /// Drop view.
    public static let dropView = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_VIEW)
    /// Insert into table.
    public static let insert = SQLiteAuthorizerAction(rawValue: SQLITE_INSERT)
    /// Pragma statement.
    public static let pragma = SQLiteAuthorizerAction(rawValue: SQLITE_PRAGMA)
    /// Read from table/column.
    public static let read = SQLiteAuthorizerAction(rawValue: SQLITE_READ)
    /// Select statement.
    public static let select = SQLiteAuthorizerAction(rawValue: SQLITE_SELECT)
    /// Transaction operation.
    public static let transaction = SQLiteAuthorizerAction(rawValue: SQLITE_TRANSACTION)
    /// Update table/column.
    public static let update = SQLiteAuthorizerAction(rawValue: SQLITE_UPDATE)
    /// Attach database.
    public static let attach = SQLiteAuthorizerAction(rawValue: SQLITE_ATTACH)
    /// Detach database.
    public static let detach = SQLiteAuthorizerAction(rawValue: SQLITE_DETACH)
    /// Alter table.
    public static let alterTable = SQLiteAuthorizerAction(rawValue: SQLITE_ALTER_TABLE)
    /// Reindex.
    public static let reindex = SQLiteAuthorizerAction(rawValue: SQLITE_REINDEX)
    /// Analyze.
    public static let analyze = SQLiteAuthorizerAction(rawValue: SQLITE_ANALYZE)
    /// Create virtual table.
    public static let createVTable = SQLiteAuthorizerAction(rawValue: SQLITE_CREATE_VTABLE)
    /// Drop virtual table.
    public static let dropVTable = SQLiteAuthorizerAction(rawValue: SQLITE_DROP_VTABLE)
    /// Function call.
    public static let function = SQLiteAuthorizerAction(rawValue: SQLITE_FUNCTION)
    /// Savepoint operation.
    public static let savepoint = SQLiteAuthorizerAction(rawValue: SQLITE_SAVEPOINT)
    /// Copy operation.
    public static let copy = SQLiteAuthorizerAction(rawValue: SQLITE_COPY)
    /// Recursive operation.
    public static let recursive = SQLiteAuthorizerAction(rawValue: SQLITE_RECURSIVE)
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

// MARK: - Hook Tokens and Identifiers

extension SQLiteConnection {
    /// Represents the different types of database hooks available.
    public enum HookKind: Sendable {
        /// Update hook (fired on INSERT, UPDATE, DELETE operations)
        case update
        /// Commit hook (fired before transaction commits)
        case commit
        /// Rollback hook (fired when transaction rolls back)
        case rollback
        /// Authorizer hook (fired during statement preparation for access control)
        case authorizer
    }
}

/// Returned by every `add…Observer` call (sync **or** async; update / commit / rollback / authorizer). Call
/// `cancel()` (or just let the token fall out of scope) to unregister its
/// associated callback.
///
/// - Important: **Token lifetime**
///
/// The observer remains active only as long as this token is retained. If you
/// don't store the token in a variable it is deallocated immediately and the
/// observer is canceled:
///
/// ```swift
/// // ❌ WRONG – token dropped immediately; observer canceled in deinit
/// _ = try await connection.addUpdateObserver { event in
///     print("This will never be called!")
/// }
///
/// // ✅ CORRECT – retain the token while you need callbacks
/// let token = try await connection.addUpdateObserver { event in
///     print("Update: \(event.table) row \(event.rowID) was \(event.operation)")
/// }
/// // Keep `token` alive as long as you need the observer
/// ```
///
/// Hook tokens automatically cancel themselves when deallocated, ensuring that
/// callbacks are cleaned up even if you never call `cancel()` explicitly.
/// Calling `cancel()` after the connection has been closed is a no-op.
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
        cancelBlock() // safe no-op if connection already closed
    }

    deinit {
        cancelBlock()
    }
}

/// Identifier for persistent observers installed with the persistent observer
/// methods (e.g., `installUpdateObserver(_:)`, `installCommitObserver(_:)`, etc.).
///
/// Use this identifier with `removeObserver(_:)` to unregister
/// the observer when it is no longer needed.
///
/// Unlike ``SQLiteHookToken``, this identifier does **not** automatically clean up
/// when deallocated—you must explicitly call `removeObserver(_:)`.
public struct SQLiteObserverID: Sendable, Hashable {
    internal let uuid: UUID
    /// The type of hook this observer ID represents.
    public let type: SQLiteConnection.HookKind

    internal init(type: SQLiteConnection.HookKind) {
        self.uuid = UUID()
        self.type = type
    }
}

// MARK: - Type Aliases

extension SQLiteConnection {
    /// The type signature for update hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteUpdateEvent`` containing details about the database modification.
    ///
    /// - Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteUpdateHookCallback = @Sendable (SQLiteUpdateEvent) -> Void

    /// The type signature for commit hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    /// - Returns: `true` to abort the commit, `false` to allow it to proceed.
    ///
    /// - Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteCommitHookCallback = @Sendable (SQLiteCommitEvent) -> Bool

    /// The type signature for rollback hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteRollbackEvent`` containing details about the rollback.
    ///
    /// - Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteRollbackHookCallback = @Sendable (SQLiteRollbackEvent) -> Void

    /// The type signature for authorizer hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    /// - Returns: A ``SQLiteAuthorizerResponse`` indicating whether to allow, deny, or ignore the operation.
    ///
    /// - Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteAuthorizerHookCallback = @Sendable (SQLiteAuthorizerEvent) -> SQLiteAuthorizerResponse
}

// MARK: - Scoped Observers (Automatic Cleanup)

/// Scoped Observer APIs
///
/// - Tag: ScopedObservers
extension SQLiteConnection {
    /// Execute a block with a temporary update observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes,
    /// making this ideal for testing or temporary observation scenarios.
    /// The observer is removed regardless of whether the body throws.
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
    /// The observer is removed regardless of whether the body throws.
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

// MARK: - RAII Observers (Token-Based Cleanup)

/// RAII Observer APIs
///
/// - Tag: RAIIObservers
extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// Fired whenever a row is inserted, updated, or deleted. Multiple observers
    /// can be registered on the same connection.
    ///
    /// ```swift
    /// let token = connection.addUpdateObserver { event in
    ///     print("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // ...later
    /// token.cancel()
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Fired whenever a transaction is about to be committed. All registered
    /// observers are invoked. If **any** observer returns `true`, the commit is
    /// aborted and the transaction is rolled back.
    ///
    /// ```swift
    /// let token = connection.addCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Fired whenever a transaction is rolled back. Multiple observers can be
    /// registered on the same connection.
    ///
    /// ```swift
    /// let token = connection.addRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Called during statement preparation to authorize database access operations.
    /// This enables precise read-set detection and access control at the table/column level.
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
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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

// MARK: - RAII Observers (Async Token-Based Cleanup)

/// Async RAII Observer APIs
///
/// - Tag: AsyncRAIIObservers
extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// Fired whenever a row is inserted, updated, or deleted. Multiple observers
    /// can be registered on the same connection.
    ///
    /// ```swift
    /// let token = try await connection.addUpdateObserver { event in
    ///     print("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // ...later
    /// token.cancel()
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Fired whenever a transaction is about to be committed. All registered
    /// observers are invoked. If **any** observer returns `true`, the commit is
    /// aborted and the transaction is rolled back.
    ///
    /// ```swift
    /// let token = try await connection.addCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Fired whenever a transaction is rolled back. Multiple observers can be
    /// registered on the same connection.
    ///
    /// ```swift
    /// let token = try await connection.addRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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
    /// Called during statement preparation to authorize database access operations.
    /// This enables precise read-set detection and access control at the table/column level.
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
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
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

// MARK: - Persistent Observers (Explicit Removal)

/// Persistent Observer APIs
///
/// - Tag: PersistentObservers
extension SQLiteConnection {
    /// Install a **persistent** update observer (row-level DML).
    ///
    /// Unlike `addUpdateObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// ```swift
    /// let id = connection.installUpdateObserver { event in
    ///     print("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // ...later
    /// connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = connection.installUpdateObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop as needed.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installUpdateObserver(_ callback: @escaping SQLiteUpdateHookCallback) -> SQLiteObserverID {
        let id = SQLiteObserverID(type: SQLiteConnection.HookKind.update)
        withBuckets { $0.update[id.uuid] = callback }
        installDispatcherIfNeeded()
        return id
    }

    /// Install a **persistent** commit observer.
    ///
    /// Unlike `addCommitObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// The commit hook is invoked whenever a transaction is about to be committed.
    /// All registered observers are invoked. If **any** observer returns `true`,
    /// the commit is aborted and the transaction is rolled back.
    ///
    /// ```swift
    /// let id = connection.installCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// // ...later
    /// connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = connection.installCommitObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop as needed.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installCommitObserver(_ callback: @escaping SQLiteCommitHookCallback) -> SQLiteObserverID {
        let id = SQLiteObserverID(type: SQLiteConnection.HookKind.commit)
        withBuckets { $0.commit[id.uuid] = callback }
        installDispatcherIfNeeded()
        return id
    }

    /// Install a **persistent** rollback observer.
    ///
    /// Unlike `addRollbackObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// The rollback hook is invoked whenever a transaction is rolled back.
    /// Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let id = connection.installRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// // ...later
    /// connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = connection.installRollbackObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop as needed.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installRollbackObserver(_ callback: @escaping SQLiteRollbackHookCallback) -> SQLiteObserverID {
        let id = SQLiteObserverID(type: SQLiteConnection.HookKind.rollback)
        withBuckets { $0.rollback[id.uuid] = callback }
        installDispatcherIfNeeded()
        return id
    }

    /// Install a **persistent** authorizer observer.
    ///
    /// Unlike `addAuthorizerObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
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
    /// let id = connection.installAuthorizerObserver { event in
    ///     if event.action == .read {
    ///         print("Reading from \(event.parameter1 ?? "unknown") table")
    ///     }
    ///     return .allow
    /// }
    /// // ...later
    /// connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = connection.installAuthorizerObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop as needed.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installAuthorizerObserver(_ callback: @escaping SQLiteAuthorizerHookCallback) -> SQLiteObserverID {
        let id = SQLiteObserverID(type: SQLiteConnection.HookKind.authorizer)
        withBuckets { $0.authorizer[id.uuid] = callback }
        installDispatcherIfNeeded()
        return id
    }

    /// Remove a persistent observer previously installed via one of the
    /// `install…Observer` methods (`installUpdateObserver`, `installCommitObserver`,
    /// `installRollbackObserver`, `installAuthorizerObserver`).
    ///
    /// - Parameter observerID: The identifier returned when the observer was installed.
    /// - Returns: `true` if an observer with that ID was removed; `false` if no such observer existed (already removed or never installed).
    ///
    /// - Note: Calling this after the connection has closed is safe and returns `false`.
    @discardableResult
    public func removeObserver(_ observerID: SQLiteObserverID) -> Bool {
        let wasRemoved = withBuckets { buckets in
            switch observerID.type {
            case .update:
                return buckets.update.removeValue(forKey: observerID.uuid) != nil
            case .commit:
                return buckets.commit.removeValue(forKey: observerID.uuid) != nil
            case .rollback:
                return buckets.rollback.removeValue(forKey: observerID.uuid) != nil
            case .authorizer:
                return buckets.authorizer.removeValue(forKey: observerID.uuid) != nil
            }
        }
        if wasRemoved {
            uninstallDispatcherIfNeeded(kind: observerID.type)
        }
        return wasRemoved
    }
}

// MARK: - Persistent Observers (Async Explicit Removal)

/// Async Persistent Observer APIs
///
/// - Tag: AsyncPersistentObservers
extension SQLiteConnection {
    /// Install a **persistent** update observer (row-level DML).
    ///
    /// Unlike `addUpdateObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// ```swift
    /// let id = try await connection.installUpdateObserver { event in
    ///     print("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // ...later
    /// try await connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = try await connection.installUpdateObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installUpdateObserver(_ callback: @escaping SQLiteUpdateHookCallback) async throws -> SQLiteObserverID {
        try await self.threadPool.runIfActive {
            let id = SQLiteObserverID(type: SQLiteConnection.HookKind.update)
            self.withBuckets { $0.update[id.uuid] = callback }
            self.installDispatcherIfNeeded()
            return id
        }
    }

    /// Install a **persistent** commit observer.
    ///
    /// Unlike `addCommitObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// The commit hook is invoked whenever a transaction is about to be committed.
    /// All registered observers are invoked. If **any** observer returns `true`,
    /// the commit is aborted and the transaction is rolled back.
    ///
    /// ```swift
    /// let id = try await connection.installCommitObserver { event in
    ///     // Perform validation logic here
    ///     print("Commit attempted at \(event.date)")
    ///     return false // Allow commit to proceed
    /// }
    /// // ...later
    /// try await connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = try await connection.installCommitObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installCommitObserver(_ callback: @escaping SQLiteCommitHookCallback) async throws -> SQLiteObserverID {
        try await self.threadPool.runIfActive {
            let id = SQLiteObserverID(type: SQLiteConnection.HookKind.commit)
            self.withBuckets { $0.commit[id.uuid] = callback }
            self.installDispatcherIfNeeded()
            return id
        }
    }

    /// Install a **persistent** rollback observer.
    ///
    /// Unlike `addRollbackObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
    ///
    /// The rollback hook is invoked whenever a transaction is rolled back.
    /// Multiple observers can be registered for the same connection.
    ///
    /// ```swift
    /// let id = try await connection.installRollbackObserver { event in
    ///     print("Transaction was rolled back at \(event.date)")
    /// }
    /// // ...later
    /// try await connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = try await connection.installRollbackObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installRollbackObserver(_ callback: @escaping SQLiteRollbackHookCallback) async throws -> SQLiteObserverID {
        try await self.threadPool.runIfActive {
            let id = SQLiteObserverID(type: SQLiteConnection.HookKind.rollback)
            self.withBuckets { $0.rollback[id.uuid] = callback }
            self.installDispatcherIfNeeded()
            return id
        }
    }

    /// Install a **persistent** authorizer observer.
    ///
    /// Unlike `addAuthorizerObserver(_:)` the returned observer remains active
    /// until you explicitly call `removeObserver(_:)` *or*
    /// the connection closes. The observer does **not** auto-remove when the
    /// returned ``SQLiteObserverID`` is deallocated.
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
    /// let id = try await connection.installAuthorizerObserver { event in
    ///     if event.action == .read {
    ///         print("Reading from \(event.parameter1 ?? "unknown") table")
    ///     }
    ///     return .allow
    /// }
    /// // ...later
    /// try await connection.removeObserver(id)
    /// ```
    ///
    /// - Important: Retain the returned ``SQLiteObserverID`` if you plan to
    ///   remove this observer before the connection closes. To install a
    ///   connection-lifetime observer intentionally, discard it:
    ///
    /// ```swift
    /// _ = try await connection.installAuthorizerObserver { event in /* connection lifetime */ }
    /// ```
    ///
    /// - Important: Registration is thread-safe. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteObserverID`` that can be used to remove the observer.
    public func installAuthorizerObserver(_ callback: @escaping SQLiteAuthorizerHookCallback) async throws -> SQLiteObserverID {
        try await self.threadPool.runIfActive {
            let id = SQLiteObserverID(type: SQLiteConnection.HookKind.authorizer)
            self.withBuckets { $0.authorizer[id.uuid] = callback }
            self.installDispatcherIfNeeded()
            return id
        }
    }

    /// Remove a persistent observer previously installed via one of the
    /// `install…Observer` methods (`installUpdateObserver`, `installCommitObserver`,
    /// `installRollbackObserver`, `installAuthorizerObserver`).
    ///
    /// - Parameter observerID: The identifier returned when the observer was installed.
    /// - Returns: `true` if an observer with that ID was removed; `false` if no such observer existed (already removed or never installed).
    ///
    /// - Note: Calling this after the connection has closed is safe and returns `false`.
    @discardableResult
    public func removeObserver(_ observerID: SQLiteObserverID) async throws -> Bool {
        try await self.threadPool.runIfActive {
            let wasRemoved = self.withBuckets { buckets in
                switch observerID.type {
                case .update:
                    return buckets.update.removeValue(forKey: observerID.uuid) != nil
                case .commit:
                    return buckets.commit.removeValue(forKey: observerID.uuid) != nil
                case .rollback:
                    return buckets.rollback.removeValue(forKey: observerID.uuid) != nil
                case .authorizer:
                    return buckets.authorizer.removeValue(forKey: observerID.uuid) != nil
                }
            }
            if wasRemoved {
                self.uninstallDispatcherIfNeeded(kind: observerID.type)
            }
            return wasRemoved
        }
    }
}

// MARK: - Private Implementation Details

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
    fileprivate func withBuckets<T>(_ body: (inout ObserverBuckets) -> T) -> T {
        observerBuckets.withLockedValue(body)
    }
}

// MARK: - Dispatcher Management

extension SQLiteConnection {
    fileprivate func installDispatcherIfNeeded() {
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
    fileprivate func uninstallDispatcherIfNeeded(kind: SQLiteConnection.HookKind) {
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

// MARK: - Low-Level C Hook Implementation

extension SQLiteConnection {
    fileprivate func applyUpdateHook(enabled: Bool) {
        if enabled {
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_update_hook(handle.raw, { context, operation, database, table, row in
                guard
                    let context,
                    let databasePtr = database,
                    let tablePtr = table
                else { return }
                let operationEnum = SQLiteUpdateOperation(rawValue: operation)
                let connection = Unmanaged<SQLiteConnection>.fromOpaque(context).takeUnretainedValue()
                let event = SQLiteUpdateEvent(operation: operationEnum,
                                              database: String(cString: databasePtr),
                                              table: String(cString: tablePtr),
                                              rowID: row)
                // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
                let callbacks: [SQLiteUpdateHookCallback] = connection.withBuckets { Array($0.update.values) }
                callbacks.forEach { $0(event) }
            }, context)
        } else {
            _ = sqlite_nio_sqlite3_update_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyCommitHook(enabled: Bool) {
        if enabled {
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_commit_hook(handle.raw, { context in
                guard let context else { return 0 }
                let connection = Unmanaged<SQLiteConnection>.fromOpaque(context).takeUnretainedValue()
                let event = SQLiteCommitEvent()
                // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
                let callbacks: [SQLiteCommitHookCallback] = connection.withBuckets { Array($0.commit.values) }
                // Run all observers so side-effects (logging, metrics) occur even if a prior observer vetoes.
                var veto = false
                for cb in callbacks {
                    if cb(event) { veto = true }
                }
                return veto ? 1 : 0
            }, context)
        } else {
            _ = sqlite_nio_sqlite3_commit_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyRollbackHook(enabled: Bool) {
        if enabled {
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_rollback_hook(handle.raw, { context in
                guard let context else { return }
                let connection = Unmanaged<SQLiteConnection>.fromOpaque(context).takeUnretainedValue()
                let event = SQLiteRollbackEvent()
                // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
                let callbacks: [SQLiteRollbackHookCallback] = connection.withBuckets { Array($0.rollback.values) }
                callbacks.forEach { $0(event) }
            }, context)
        } else {
            _ = sqlite_nio_sqlite3_rollback_hook(handle.raw, nil, nil)
        }
    }

    fileprivate func applyAuthorizerHook(enabled: Bool) {
        if enabled {
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = sqlite_nio_sqlite3_set_authorizer(handle.raw, { context, action, parameter1, parameter2, database, trigger in
                guard let context else { return SQLiteAuthorizerResponse.deny.rawValue }
                let actionType = SQLiteAuthorizerAction(rawValue: action)
                let connection = Unmanaged<SQLiteConnection>.fromOpaque(context).takeUnretainedValue()
                let event = SQLiteAuthorizerEvent(action: actionType,
                                                  parameter1: parameter1.map { String(cString: $0) },
                                                  parameter2: parameter2.map { String(cString: $0) },
                                                  database: database.map { String(cString: $0) },
                                                  trigger: trigger.map { String(cString: $0) })
                // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
                let callbacks: [SQLiteAuthorizerHookCallback] = connection.withBuckets { Array($0.authorizer.values) }
                // Aggregate results: DENY > IGNORE > ALLOW
                var result: SQLiteAuthorizerResponse = .allow
                for response in callbacks.map({ $0(event) }) {
                    switch response {
                    case .deny:
                        return SQLiteAuthorizerResponse.deny.rawValue    // short-circuit
                    case .ignore:
                        result = .ignore // keep going; maybe someone denies
                    case .allow:
                        continue
                    }
                }
                return result.rawValue
            }, context)
        } else {
            _ = sqlite_nio_sqlite3_set_authorizer(handle.raw, nil, nil)
        }
    }

    internal func clearAllHooks() {
        applyUpdateHook(enabled: false)
        applyCommitHook(enabled: false)
        applyRollbackHook(enabled: false)
        applyAuthorizerHook(enabled: false)
        observerBuckets.withLockedValue { $0 = ObserverBuckets() }
    }
}
