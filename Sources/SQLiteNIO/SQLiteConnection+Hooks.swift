import Foundation
import NIOConcurrencyHelpers
import NIOCore
import CSQLite

// MARK: - Hook Types and Events

/// Observer lifetime management for SQLite hooks.
public enum SQLiteObserverLifetime: Sendable, Hashable {
    /// Observer automatically cancels when the token is deallocated.
    case scoped
    /// Observer remains active until explicitly canceled.
    case pinned
}

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
public struct SQLiteUpdateEvent: Sendable, Hashable {
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

/// The response from a commit hook callback.
public struct SQLiteCommitResponse: Sendable, Hashable {
    /// The raw response value.
    public let rawValue: Int32

    /// Creates a new SQLiteCommitResponse with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known responses.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Allow the commit to proceed.
    public static let allow = SQLiteCommitResponse(rawValue: 0)
    /// Deny the commit (causes transaction rollback).
    public static let deny = SQLiteCommitResponse(rawValue: 1)
}

/// The response from an authorizer callback.
public struct SQLiteAuthorizerResponse: Sendable, Hashable {
    /// The raw response value.
    public let rawValue: Int32

    /// Creates a new SQLiteAuthorizerResponse with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known responses.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Allow the operation.
    public static let allow = SQLiteAuthorizerResponse(rawValue: 0) // SQLITE_OK
    /// Deny the operation.
    public static let deny = SQLiteAuthorizerResponse(rawValue: 1) // SQLITE_DENY
    /// Ignore the operation (treat column as NULL).
    public static let ignore = SQLiteAuthorizerResponse(rawValue: 2) // SQLITE_IGNORE
}

/// Event produced by the authorizer hook.
///
/// Contains information about a database access attempt that requires authorization.
public struct SQLiteAuthorizerEvent: Sendable, Hashable {
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
public struct SQLiteCommitEvent: Sendable, Hashable {
    /// Timestamp (in the connection's wall-clock) when the commit was about to occur.
    public let date = Date()
}

/// Event produced by the rollback hook.
///
/// Contains information about a transaction rollback that has occurred.
public struct SQLiteRollbackEvent: Sendable, Hashable {
    /// Timestamp (in the connection's wall-clock) when the rollback happened.
    public let date = Date()
}

// MARK: - Hook Tokens and Identifiers

/// Represents the different types of database hooks available.
public enum SQLiteHookKind: Sendable, Hashable {
    /// Update hook (fired on INSERT, UPDATE, DELETE operations)
    case update
    /// Commit hook (fired before transaction commits)
    case commit
    /// Rollback hook (fired when transaction rolls back)
    case rollback
    /// Authorizer hook (fired during statement preparation for access control)
    case authorizer
}

/// Returned by every `add…Observer` and `set…Validator` call, whether sync or async, of any type. Call
/// ``SQLiteHookToken/cancel()`` to unregister its associated callback.
///
/// ## Token Lifetime Behavior
///
/// The lifetime behavior depends on the ``SQLiteObserverLifetime`` parameter:
///
/// - ``SQLiteObserverLifetime/scoped`` - observer automatically cancels when token is deallocated:
///
///    ```swift
///    // Async usage:
///    let token = try await connection.addUpdateObserver(
///        lifetime: .scoped
///    ) { event in
///        print("Auto-canceled when token is deallocated")
///    }
///    // Sync usage:
///    let token = connection.addUpdateObserver(lifetime: .scoped) { event in
///        print("Auto-canceled when token is deallocated")
///    }
///    // Observer stops when `token` goes out of scope
///    ```
/// - ``SQLiteObserverLifetime/pinned`` - observer remains active until explicitly canceled:
///
///    ```swift
///    // Observer stays active until connection closes or explicit cancel
///    let token = try await connection.addUpdateObserver(
///        lifetime: .pinned
///    ) { [weak self] event in
///        self?.logger.info("This will be called until explicitly canceled!")
///    }
///    // Call token.cancel() when you want to stop the observer
///    ```
///
/// > Important: Use `[weak self]` or `[unowned self]` in observers to avoid retain cycles, especially with ``SQLiteObserverLifetime/pinned`` lifetime.
///
/// > Note: Calling ``SQLiteHookToken/cancel()`` after the connection has been closed is a no-op.
public final class SQLiteHookToken: Sendable, Hashable {
    public let id = UUID()
    public let lifetime: SQLiteObserverLifetime
    private let cancelBlock: @Sendable () -> Void

    fileprivate init(lifetime: SQLiteObserverLifetime, cancel: @escaping @Sendable () -> Void) {
        self.lifetime = lifetime
        self.cancelBlock = cancel
    }

    /// Cancels the associated hook callback.
    ///
    /// After calling this method, the callback will no longer be invoked.
    /// It is safe to call this method multiple times.
    public func cancel() {
        self.cancelBlock() // safe no-op if connection already closed
    }

    deinit {
        if lifetime == .scoped {
            self.cancelBlock()
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SQLiteHookToken, rhs: SQLiteHookToken) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Type Aliases

extension SQLiteConnection {
    /// The type signature for update hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteUpdateEvent`` containing details about the database modification.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteUpdateHookCallback = @Sendable (SQLiteUpdateEvent) -> Void

    /// The type signature for commit observer callbacks (pure observation, cannot veto).
    ///
    /// Commit observers are for logging, metrics, and other side effects that should not
    /// interfere with the commit process. They cannot veto or abort commits.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteCommitObserver = @Sendable (SQLiteCommitEvent) -> Void

    /// The type signature for commit validator callbacks (can veto commits).
    ///
    /// Commit validators can examine the transaction and decide whether to allow or deny
    /// the commit. Use this for business rule validation, constraints, or access control.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    /// - Returns: A ``SQLiteCommitResponse`` indicating whether to allow or deny the commit.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteCommitValidator = @Sendable (SQLiteCommitEvent) -> SQLiteCommitResponse

    /// The type signature for rollback hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteRollbackEvent`` containing details about the rollback.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteRollbackHookCallback = @Sendable (SQLiteRollbackEvent) -> Void

    /// The type signature for authorizer observer callbacks.
    ///
    /// Authorizer observers perform pure observation (logging, metrics, auditing) without
    /// the ability to influence access control decisions. They are notified only if
    /// the authorizer validator (if any) has not denied the operation.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteAuthorizerObserver = @Sendable (SQLiteAuthorizerEvent) -> Void

    /// The type signature for authorizer validator callbacks.
    ///
    /// The authorizer validator examines database access attempts and decides whether to
    /// allow, deny, or ignore them. Only one validator can be active per connection.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    /// - Returns: A ``SQLiteAuthorizerResponse`` indicating whether to allow, deny, or ignore the operation.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor or event loop as needed.
    public typealias SQLiteAuthorizerValidator = @Sendable (SQLiteAuthorizerEvent) -> SQLiteAuthorizerResponse
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
        let token = addUpdateObserver(lifetime: .scoped, callback)
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
        let token = try await addUpdateObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary commit observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes.
    /// Observers cannot veto commits - they are for logging and metrics only.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withCommitObserver<T>(
        _ callback: @escaping SQLiteCommitObserver,
        body: () throws -> T
    ) rethrows -> T {
        let token = addCommitObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary commit observer (async version).
    ///
    /// The observer is automatically removed when the block completes.
    /// Observers cannot veto commits - they are for logging and metrics only.
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withCommitObserver<T>(
        _ callback: @escaping SQLiteCommitObserver,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addCommitObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary authorizer observer (synchronous version).
    ///
    /// The observer is automatically removed when the block completes.
    /// Authorizer observers perform pure observation without influencing access control.
    ///
    /// ```swift
    /// let result = connection.withAuthorizerObserver({ event in
    ///     print("Database access: \(event.action)")
    /// }) {
    ///     // perform operations - observer is active
    ///     return someComputation()
    /// }
    /// // observer is automatically removed here
    /// ```
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withAuthorizerObserver<T>(
        _ callback: @escaping SQLiteAuthorizerObserver,
        body: () throws -> T
    ) rethrows -> T {
        let token = addAuthorizerObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try body()
    }

    /// Execute a block with a temporary authorizer observer (async version).
    ///
    /// The observer is automatically removed when the block completes.
    /// Authorizer observers perform pure observation without influencing access control.
    ///
    /// ```swift
    /// let result = try await connection.withAuthorizerObserver({ event in
    ///     print("Database access: \(event.action)")
    /// }) {
    ///     // perform async operations - observer is active
    ///     return await someAsyncComputation()
    /// }
    /// // observer is automatically removed here
    /// ```
    ///
    /// - Parameters:
    ///   - callback: The observer callback to register temporarily.
    ///   - body: The block to execute with the observer active.
    /// - Returns: The return value of the body block.
    /// - Throws: Any error thrown by the body block.
    public func withAuthorizerObserver<T>(
        _ callback: @escaping SQLiteAuthorizerObserver,
        body: () async throws -> T
    ) async throws -> T {
        let token = try await addAuthorizerObserver(lifetime: .scoped, callback)
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
        let token = addRollbackObserver(lifetime: .scoped, callback)
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
        let token = try await addRollbackObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }
}

// MARK: - Token-Based Observers

/// Token-Based Observer APIs
///
/// - Tag: TokenObservers
extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// Fired whenever a row is inserted, updated, or deleted. Multiple observers
    /// can be registered on the same connection.
    ///
    /// ```swift
    /// let token = connection.addUpdateObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // Clean up the observer when no longer needed:
    /// token.cancel()
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addUpdateObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteUpdateHookCallback) -> SQLiteHookToken {
        let id = UUID()
        self.withBuckets { $0.update[id] = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.update.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .update)
        }
    }

    /// Register a pure observer for SQLite commit events (cannot veto commits).
    ///
    /// Commit observers are for logging, metrics, and other side effects that should
    /// not interfere with the commit process. They cannot veto commits.
    ///
    /// ```swift
    /// let token = connection.addCommitObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Transaction committed: \(event)")
    ///     self?.metrics.increment("commits")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addCommitObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitObserver) -> SQLiteHookToken {
        let id = UUID()
        self.withBuckets { $0.commitObservers[id] = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.commitObservers.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .commit)
        }
    }

    /// Register a validator for SQLite commit events (can veto commits).
    ///
    /// Commit validators can examine the transaction and decide whether to allow or deny
    /// the commit. Use this for business rule validation, constraints, or access control.
    ///
    /// ```swift
    /// let token = connection.setCommitValidator(lifetime: .pinned) { [weak self] event in
    ///     // Perform validation logic here
    ///     return self?.businessRules.validate(event) == true ? .allow : .deny
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setCommitValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitValidator) -> SQLiteHookToken {
        self.withBuckets { $0.commitValidator = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.commitValidator = nil }
            self.uninstallDispatcherIfNeeded(kind: .commit)
        }
    }

    /// Register an observer for the SQLite *rollback* hook.
    ///
    /// Fired whenever a transaction is rolled back. Multiple observers can be
    /// registered on the same connection.
    ///
    /// ```swift
    /// let token = connection.addRollbackObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addRollbackObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteRollbackHookCallback) -> SQLiteHookToken {
        let id = UUID()
        self.withBuckets { $0.rollback[id] = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.rollback.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .rollback)
        }
    }

    /// Register an observer for the SQLite *authorizer* hook.
    ///
    /// Authorizer observers perform pure observation (logging, metrics, auditing)
    /// without influencing access control decisions. They are notified only if
    /// the authorizer validator (if any) has not denied the operation.
    ///
    /// ```swift
    /// let token = connection.addAuthorizerObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Database access: \(event.action) on \(event.parameter1 ?? "N/A")")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addAuthorizerObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerObserver) -> SQLiteHookToken {
        let id = UUID()
        self.withBuckets { $0.authorizerObservers[id] = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.authorizerObservers.removeValue(forKey: id) }
            self.uninstallDispatcherIfNeeded(kind: .authorizer)
        }
    }

    /// Set the validator for the SQLite *authorizer* hook.
    ///
    /// The authorizer validator examines database access attempts and decides whether to
    /// allow, deny, or ignore them. Only one validator can be active per connection.
    /// Setting a new validator replaces any existing validator.
    ///
    /// ```swift
    /// let token = connection.setAuthorizerValidator(lifetime: .pinned) { [weak self] event in
    ///     if event.action == .delete && event.parameter1 == "sensitive_table" {
    ///         return self?.accessControl.allowDelete() == true ? .allow : .deny
    ///     }
    ///     return .allow
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setAuthorizerValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerValidator) -> SQLiteHookToken {
        self.withBuckets { $0.authorizerValidator = callback }
        self.installDispatcherIfNeeded()
        return SQLiteHookToken(lifetime: lifetime) { [weak self] in
            guard let self else { return }
            self.withBuckets { $0.authorizerValidator = nil }
            self.uninstallDispatcherIfNeeded(kind: .authorizer)
        }
    }
}

// MARK: - Token-Based Observers

/// Async Token-Based Observer APIs
///
/// - Tag: AsyncTokenObservers
extension SQLiteConnection {
    /// Register an observer for the SQLite *update* hook (row-level DML).
    ///
    /// Fired whenever a row is inserted, updated, or deleted. Multiple observers
    /// can be registered on the same connection.
    ///
    /// ```swift
    /// let token = try await connection.addUpdateObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("\(event.table) row \(event.rowID) was \(event.operation)")
    /// }
    /// // Clean up the observer when no longer needed:
    /// token.cancel()
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addUpdateObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteUpdateHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.update[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.update.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .update)
            }
        }
    }

    /// Register a pure observer for SQLite commit events (cannot veto commits).
    ///
    /// Commit observers are for logging, metrics, and other side effects that should
    /// not interfere with the commit process. They cannot veto commits.
    ///
    /// ```swift
    /// let token = try await connection.addCommitObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Transaction committed: \(event)")
    ///     self?.metrics.increment("commits")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addCommitObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitObserver) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.commitObservers[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.commitObservers.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .commit)
            }
        }
    }

    /// Register a validator for SQLite commit events (can veto commits).
    ///
    /// Commit validators can examine the transaction and decide whether to allow or deny
    /// the commit. Use this for business rule validation, constraints, or access control.
    ///
    /// ```swift
    /// let token = try await connection.setCommitValidator(lifetime: .pinned) { [weak self] event in
    ///     // Perform validation logic here
    ///     return self?.businessRules.validate(event) == true ? .allow : .deny
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setCommitValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitValidator) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            self.withBuckets { $0.commitValidator = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.commitValidator = nil }
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
    /// let token = try await connection.addRollbackObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Transaction was rolled back at \(event.date)")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addRollbackObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteRollbackHookCallback) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.rollback[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.rollback.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .rollback)
            }
        }
    }

    /// Register an observer for the SQLite *authorizer* hook (async version).
    ///
    /// Authorizer observers perform pure observation (logging, metrics, auditing)
    /// without influencing access control decisions. They are notified only if
    /// the authorizer validator (if any) has not denied the operation.
    ///
    /// ```swift
    /// let token = try await connection.addAuthorizerObserver(lifetime: .pinned) { [weak self] event in
    ///     self?.logger.info("Database access: \(event.action) on \(event.parameter1 ?? "N/A")")
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addAuthorizerObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerObserver) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            let id = UUID()
            self.withBuckets { $0.authorizerObservers[id] = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.authorizerObservers.removeValue(forKey: id) }
                self.uninstallDispatcherIfNeeded(kind: .authorizer)
            }
        }
    }

    /// Set the validator for the SQLite *authorizer* hook (async version).
    ///
    /// The authorizer validator examines database access attempts and decides whether to
    /// allow, deny, or ignore them. Only one validator can be active per connection.
    /// Setting a new validator replaces any existing validator.
    ///
    /// ```swift
    /// let token = try await connection.setAuthorizerValidator(lifetime: .pinned) { [weak self] event in
    ///     if event.action == .delete && event.parameter1 == "sensitive_table" {
    ///         return self?.accessControl.allowDelete() == true ? .allow : .deny
    ///     }
    ///     return .allow
    /// }
    /// ```
    ///
    /// > Important: Registration is /safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor or event loop as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setAuthorizerValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerValidator) async throws -> SQLiteHookToken {
        try await self.threadPool.runIfActive {
            self.withBuckets { $0.authorizerValidator = callback }
            self.installDispatcherIfNeeded()
            return SQLiteHookToken(lifetime: lifetime) { [weak self] in
                guard let self else { return }
                self.withBuckets { $0.authorizerValidator = nil }
                self.uninstallDispatcherIfNeeded(kind: .authorizer)
            }
        }
    }
}

// MARK: - Private Implementation Details

extension SQLiteConnection {
    struct ObserverBuckets: Sendable {
        var update: [UUID: SQLiteUpdateHookCallback] = [:]
        var commitObservers: [UUID: SQLiteCommitObserver] = [:]
        var commitValidator: SQLiteCommitValidator? = nil
        var rollback: [UUID: SQLiteRollbackHookCallback] = [:]
        var authorizerObservers: [UUID: SQLiteAuthorizerObserver] = [:]
        var authorizerValidator: SQLiteAuthorizerValidator? = nil

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
        self.withBuckets { buckets in
            // Install update hook dispatcher if needed
            if !buckets.updateDispatcherInstalled && !buckets.update.isEmpty {
                buckets.updateDispatcherInstalled = true
                self.applyUpdateHook(enabled: true)
            }

            // Install commit hook dispatcher if needed (observers or validator)
            if !buckets.commitDispatcherInstalled &&
                (!buckets.commitObservers.isEmpty || buckets.commitValidator != nil) {
                buckets.commitDispatcherInstalled = true
                self.applyCommitHook(enabled: true)
            }

            // Install rollback hook dispatcher if needed
            if !buckets.rollbackDispatcherInstalled && !buckets.rollback.isEmpty {
                buckets.rollbackDispatcherInstalled = true
                self.applyRollbackHook(enabled: true)
            }

            // Install authorizer hook dispatcher if needed (observers or validator)
            if !buckets.authorizerDispatcherInstalled &&
                (!buckets.authorizerObservers.isEmpty || buckets.authorizerValidator != nil) {
                buckets.authorizerDispatcherInstalled = true
                self.applyAuthorizerHook(enabled: true)
            }
        }
    }

    /// Called after removing an observer to tear down the C-hook if nobody
    /// is listening any longer.
    fileprivate func uninstallDispatcherIfNeeded(kind: SQLiteHookKind) {
        self.withBuckets { buckets in
            switch kind {
            case .update where buckets.update.isEmpty && buckets.updateDispatcherInstalled:
                buckets.updateDispatcherInstalled = false
                self.applyUpdateHook(enabled: false)
            case .commit where buckets.commitObservers.isEmpty && buckets.commitValidator == nil && buckets.commitDispatcherInstalled:
                buckets.commitDispatcherInstalled = false
                self.applyCommitHook(enabled: false)
            case .rollback where buckets.rollback.isEmpty && buckets.rollbackDispatcherInstalled:
                buckets.rollbackDispatcherInstalled = false
                self.applyRollbackHook(enabled: false)
            case .authorizer where buckets.authorizerObservers.isEmpty && buckets.authorizerValidator == nil && buckets.authorizerDispatcherInstalled:
                buckets.authorizerDispatcherInstalled = false
                self.applyAuthorizerHook(enabled: false)
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
                // Copy validator and observers while locked, then invoke unlocked (avoid deadlock)
                let (validator, observers): (SQLiteCommitValidator?, [SQLiteCommitObserver]) =
                connection.withBuckets { buckets in
                    (buckets.commitValidator, Array(buckets.commitObservers.values))
                }

                // First check validator (if any)
                if let validator {
                    let validatorResponse = validator(event)
                    // If validator denies, short-circuit (don't run observers)
                    if validatorResponse == .deny {
                        return 1 // abort commit
                    }
                }

                // Run all observers (side effects only, cannot veto)
                for observer in observers {
                    observer(event)
                }

                return 0 // allow commit
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
                // Copy validator and observers while locked, then invoke unlocked (avoid deadlock)
                let (validator, observers): (SQLiteAuthorizerValidator?, [SQLiteAuthorizerObserver]) =
                connection.withBuckets { buckets in
                    (buckets.authorizerValidator, Array(buckets.authorizerObservers.values))
                }

                // First check validator (if any)
                let validatorResponse: SQLiteAuthorizerResponse
                if let validator = validator {
                    validatorResponse = validator(event)
                    // If validator denies, short-circuit (don't run observers)
                    if validatorResponse == .deny {
                        return SQLiteAuthorizerResponse.deny.rawValue
                    }
                } else {
                    validatorResponse = .allow
                }

                // Run all observers (side effects only, cannot veto)
                for observer in observers {
                    observer(event)
                }

                return validatorResponse.rawValue
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
