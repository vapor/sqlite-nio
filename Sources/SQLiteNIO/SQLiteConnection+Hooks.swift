#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif
import Synchronization
import VaporCSQLite

// MARK: - Hook Types and Events

/// Observer lifetime management for SQLite hooks.
public struct SQLiteObserverLifetime: RawRepresentable, Hashable, Sendable {
    /// The raw lifetime value.
    public let rawValue: Int32

    /// Creates a new SQLiteObserverLifetime with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known lifetimes.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Observer automatically cancels when the token is deallocated.
    public static let scoped = SQLiteObserverLifetime(rawValue: 0)
    /// Observer remains active until explicitly canceled.
    public static let pinned = SQLiteObserverLifetime(rawValue: 1)
}

/// Represents the type of update operation that triggered the update hook.
public struct SQLiteUpdateOperation: RawRepresentable, Hashable, Sendable {
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
public struct SQLiteUpdateEvent: Hashable, Sendable {
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
public struct SQLiteAuthorizerAction: RawRepresentable, Hashable, Sendable {
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
public struct SQLiteCommitResponse: RawRepresentable, Hashable, Sendable {
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
public struct SQLiteAuthorizerResponse: RawRepresentable, Hashable, Sendable {
    /// The raw response value.
    public let rawValue: Int32

    /// Creates a new SQLiteAuthorizerResponse with the given raw value.
    /// For unknown values, this still creates an instance - use the static properties for known responses.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Allow the operation.
    public static let allow = SQLiteAuthorizerResponse(rawValue: SQLITE_OK)
    /// Deny the operation.
    public static let deny = SQLiteAuthorizerResponse(rawValue: SQLITE_DENY)
    /// Ignore the operation (treat column as NULL).
    public static let ignore = SQLiteAuthorizerResponse(rawValue: SQLITE_IGNORE)
}

/// Event produced by the authorizer hook.
///
/// Contains information about a database access attempt that requires authorization.
public struct SQLiteAuthorizerEvent: Hashable, Sendable {
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
public struct SQLiteCommitEvent: Hashable, Sendable {
    /// Timestamp (in the connection's wall-clock) when the commit was about to occur.
    public let date = Date()
}

/// Event produced by the rollback hook.
///
/// Contains information about a transaction rollback that has occurred.
public struct SQLiteRollbackEvent: Hashable, Sendable {
    /// Timestamp (in the connection's wall-clock) when the rollback happened.
    public let date = Date()
}

// MARK: - Hook Tokens and Identifiers

/// Represents the different types of database hooks available.
fileprivate struct SQLiteHookKind: RawRepresentable, Hashable, Sendable {
    /// The raw hook kind value.
    fileprivate let rawValue: Int32

    /// Creates a new SQLiteHookKind with the given raw value.
    fileprivate init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Update hook (fired on INSERT, UPDATE, DELETE operations)
    fileprivate static let update = SQLiteHookKind(rawValue: 0)
    /// Commit hook (fired before transaction commits)
    fileprivate static let commit = SQLiteHookKind(rawValue: 1)
    /// Rollback hook (fired when transaction rolls back)
    fileprivate static let rollback = SQLiteHookKind(rawValue: 2)
    /// Authorizer hook (fired during statement preparation for access control)
    fileprivate static let authorizer = SQLiteHookKind(rawValue: 3)
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
public final class SQLiteHookToken: Hashable, Sendable {
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
        if self.lifetime == .scoped {
            self.cancelBlock()
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
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
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteUpdateHookCallback = @Sendable (SQLiteUpdateEvent) -> Void

    /// The type signature for commit observer callbacks (pure observation, cannot veto).
    ///
    /// Commit observers are for logging, metrics, and other side effects that should not
    /// interfere with the commit process. They cannot veto or abort commits.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteCommitObserver = @Sendable (SQLiteCommitEvent) -> Void

    /// The type signature for commit validator callbacks (can veto commits).
    ///
    /// Commit validators can examine the transaction and decide whether to allow or deny
    /// the commit. Use this for business rule validation, constraints, or access control.
    ///
    /// - Parameter event: A ``SQLiteCommitEvent`` containing details about the commit attempt.
    /// - Returns: A ``SQLiteCommitResponse`` indicating whether to allow or deny the commit.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteCommitValidator = @Sendable (SQLiteCommitEvent) -> SQLiteCommitResponse

    /// The type signature for rollback hook callbacks.
    ///
    /// - Parameter event: A ``SQLiteRollbackEvent`` containing details about the rollback.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteRollbackHookCallback = @Sendable (SQLiteRollbackEvent) -> Void

    /// The type signature for authorizer observer callbacks.
    ///
    /// Authorizer observers perform pure observation (logging, metrics, auditing) without
    /// the ability to influence access control decisions. They are notified only if
    /// the authorizer validator (if any) has not denied the operation.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteAuthorizerObserver = @Sendable (SQLiteAuthorizerEvent) -> Void

    /// The type signature for authorizer validator callbacks.
    ///
    /// The authorizer validator examines database access attempts and decides whether to
    /// allow, deny, or ignore them. Only one validator can be active per connection.
    ///
    /// - Parameter event: A ``SQLiteAuthorizerEvent`` containing details about the access attempt.
    /// - Returns: A ``SQLiteAuthorizerResponse`` indicating whether to allow, deny, or ignore the operation.
    ///
    /// > Note: Callbacks run on SQLite's internal thread. Hop to an actor as needed.
    public typealias SQLiteAuthorizerValidator = @Sendable (SQLiteAuthorizerEvent) -> SQLiteAuthorizerResponse
}

// MARK: - Scoped Observers (Automatic Cleanup)

/// Scoped Observer APIs
///
/// - Tag: ScopedObservers
extension SQLiteConnection {
    /// Execute a block with a temporary update observer.
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
        let token = try await self.addUpdateObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary commit observer.
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
        let token = try await self.addCommitObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary authorizer observer.
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
        let token = try await self.addAuthorizerObserver(lifetime: .scoped, callback)
        defer { token.cancel() }
        return try await body()
    }

    /// Execute a block with a temporary rollback observer.
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
        let token = try await self.addRollbackObserver(lifetime: .scoped, callback)
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when update events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addUpdateObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteUpdateHookCallback) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .update) { $0.updateHooks[id] = callback }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                self?.removeHook { $0.updateHooks[id] = nil }
            }
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addCommitObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitObserver) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .commit) { $0.commitObservers[id] = callback }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                self?.removeHook { $0.commitObservers[id] = nil }
            }
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when commit events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setCommitValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteCommitValidator) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .commit) { $0.commitValidator = (id, callback) }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                // Only remove the validator this token registered, not one that has since replaced it.
                self?.removeHook { if $0.commitValidator?.id == id { $0.commitValidator = nil } }
            }
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when rollback events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addRollbackObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteRollbackHookCallback) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .rollback) { $0.rollbackHooks[id] = callback }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                self?.removeHook { $0.rollbackHooks[id] = nil }
            }
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the observer when canceled.
    public func addAuthorizerObserver(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerObserver) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .authorizer) { $0.authorizerObservers[id] = callback }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                self?.removeHook { $0.authorizerObservers[id] = nil }
            }
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
    /// > Important: Registration is safe from any thread. Callbacks are invoked on SQLite's
    ///   internal thread; hop to your own actor as needed.
    ///
    /// - Parameter lifetime: The observer lifetime behavior. See ``SQLiteObserverLifetime`` for details.
    ///    Use ``SQLiteObserverLifetime/scoped`` for automatic cleanup on token deallocation, or
    ///    ``SQLiteObserverLifetime/pinned`` for explicit cleanup only.
    /// - Parameter callback: Closure to invoke when authorization events occur.
    /// - Returns: A ``SQLiteHookToken`` that removes the validator when canceled.
    public func setAuthorizerValidator(lifetime: SQLiteObserverLifetime, _ callback: @escaping SQLiteAuthorizerValidator) async throws -> SQLiteHookToken {
        try await self.onExecutor {
            let id = UUID()

            self.addHook(kind: .authorizer) { $0.authorizerValidator = (id, callback) }
            return .init(lifetime: lifetime) { @Sendable [weak self = self] in
                // Only remove the validator this token registered, not one that has since replaced it.
                self?.removeHook { if $0.authorizerValidator?.id == id { $0.authorizerValidator = nil } }
            }
        }
    }
}

// MARK: - Private Implementation Details

extension SQLiteConnection {
    struct ObserverBuckets: Sendable {
        var updateHooks: [UUID: SQLiteUpdateHookCallback] = [:]
        var commitObservers: [UUID: SQLiteCommitObserver] = [:]
        var commitValidator: (id: UUID, validate: SQLiteCommitValidator)? = nil
        var rollbackHooks: [UUID: SQLiteRollbackHookCallback] = [:]
        var authorizerObservers: [UUID: SQLiteAuthorizerObserver] = [:]
        var authorizerValidator: (id: UUID, validate: SQLiteAuthorizerValidator)? = nil

        // Track whether low-level dispatchers are installed. Once installed, a dispatcher stays installed until
        // the connection is closed, even if every observer has since been removed.
        var updateDispatcherInstalled = false
        var commitDispatcherInstalled = false
        var rollbackDispatcherInstalled = false
        var authorizerDispatcherInstalled = false
    }

    // Convenience to mutate buckets
    @discardableResult
    fileprivate func withBuckets<T>(_ body: (inout ObserverBuckets) -> sending T) -> sending T {
        self.observerBuckets.withLock(body)
    }
}

// MARK: - Dispatcher Management

// Lock ordering: SQLite invokes the dispatchers from inside a call on the connection, with the connection's
// own mutex held, and each dispatcher then takes the observer lock. Installing or removing a C hook takes
// that same connection mutex, so it must never happen while the observer lock is held.

extension SQLiteConnection {
    /// Register an observer and make sure the C hook that dispatches to it is installed.
    ///
    /// Must be run on the connection's executor.
    fileprivate func addHook(kind: SQLiteHookKind, _ register: (inout ObserverBuckets) -> Void) {
        let isInstalled = self.withBuckets { buckets in
            register(&buckets)

            return switch kind {
            case .update:     buckets.updateDispatcherInstalled
            case .commit:     buckets.commitDispatcherInstalled
            case .rollback:   buckets.rollbackDispatcherInstalled
            case .authorizer: buckets.authorizerDispatcherInstalled
            default:          true
            }
        }
        guard !isInstalled else { return }

        // Two registrations racing each other may both get here. Installing a dispatcher twice is harmless,
        // and it means neither returns before the dispatcher is in place.
        switch kind {
        case .update:
            self.applyUpdateHook(enabled: true)
            self.withBuckets { $0.updateDispatcherInstalled = true }
        case .commit:
            self.applyCommitHook(enabled: true)
            self.withBuckets { $0.commitDispatcherInstalled = true }
        case .rollback:
            self.applyRollbackHook(enabled: true)
            self.withBuckets { $0.rollbackDispatcherInstalled = true }
        case .authorizer:
            self.applyAuthorizerHook(enabled: true)
            self.withBuckets { $0.authorizerDispatcherInstalled = true }
        default:
            break
        }
    }

    /// Unregister an observer.
    ///
    /// This is what ``SQLiteHookToken/cancel()`` runs, so it may be called from any thread, including from
    /// inside a hook callback. It only updates the observer table and never calls into SQLite: the dispatcher
    /// is left installed, and does nothing while there are no observers for it to call.
    fileprivate func removeHook(_ unregister: (inout ObserverBuckets) -> Void) {
        self.withBuckets { unregister(&$0) }
    }
}

// MARK: - Low-Level C Hook Implementation

extension SQLiteConnection {
    /// The connection as the context pointer handed to SQLite when installing a hook.
    ///
    /// The pointer is unretained. SQLite only invokes a hook from inside a call made on this connection's
    /// handle, and every such call is made through this connection, so the connection is alive whenever the
    /// pointer is used. ``clearAllHooks()`` removes the hooks before the handle is closed.
    private var hookContext: UnsafeMutableRawPointer {
        unsafe Unmanaged.passUnretained(self).toOpaque()
    }

    /// Recover the connection from the context pointer SQLite passed to a hook callback.
    ///
    /// `context` must be a pointer produced by ``hookContext``.
    private static func connection(forHookContext context: UnsafeMutableRawPointer?) -> SQLiteConnection? {
        guard let context = unsafe context else { return nil }
        return unsafe Unmanaged<SQLiteConnection>.fromOpaque(context).takeUnretainedValue()
    }

    /// Must be run on the connection's executor.
    fileprivate func applyUpdateHook(enabled: Bool) {
        guard enabled else {
            _ = unsafe sqlite_nio_sqlite3_update_hook(self.handle.raw, nil, nil)
            return
        }

        _ = unsafe sqlite_nio_sqlite3_update_hook(self.handle.raw, { context, operation, database, table, row in
            guard let connection = unsafe SQLiteConnection.connection(forHookContext: context) else { return }

            // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
            let callbacks = connection.withBuckets { Array($0.updateHooks.values) }

            guard !callbacks.isEmpty,
                  let database = unsafe database.map(String.init(cString:)),
                  let table = unsafe table.map(String.init(cString:))
            else { return }

            let event = SQLiteUpdateEvent(operation: SQLiteUpdateOperation(rawValue: operation),
                                          database: database,
                                          table: table,
                                          rowID: row)

            for callback in callbacks {
                callback(event)
            }
        }, self.hookContext)
    }

    /// Must be run on the connection's executor.
    fileprivate func applyCommitHook(enabled: Bool) {
        guard enabled else {
            _ = unsafe sqlite_nio_sqlite3_commit_hook(self.handle.raw, nil, nil)
            return
        }

        _ = unsafe sqlite_nio_sqlite3_commit_hook(self.handle.raw, { context in
            guard let connection = unsafe SQLiteConnection.connection(forHookContext: context) else { return 0 }

            // Copy validator and observers while locked, then invoke unlocked (avoid deadlock)
            let (validator, observers): (SQLiteCommitValidator?, [SQLiteCommitObserver]) =
            connection.withBuckets { buckets in
                (buckets.commitValidator?.validate, Array(buckets.commitObservers.values))
            }

            guard validator != nil || !observers.isEmpty else { return 0 }

            let event = SQLiteCommitEvent()

            // First check validator (if any). If validator denies, short-circuit (don't run observers)
            if let validator, validator(event) == .deny {
                return 1 // abort commit
            }

            // Run all observers (side effects only, cannot veto)
            for observer in observers {
                observer(event)
            }

            return 0 // allow commit
        }, self.hookContext)
    }

    /// Must be run on the connection's executor.
    fileprivate func applyRollbackHook(enabled: Bool) {
        guard enabled else {
            _ = unsafe sqlite_nio_sqlite3_rollback_hook(self.handle.raw, nil, nil)
            return
        }

        _ = unsafe sqlite_nio_sqlite3_rollback_hook(self.handle.raw, { context in
            guard let connection = unsafe SQLiteConnection.connection(forHookContext: context) else { return }

            // Copy callbacks while locked, then invoke unlocked (avoid deadlock)
            let callbacks = connection.withBuckets { Array($0.rollbackHooks.values) }

            guard !callbacks.isEmpty else { return }

            let event = SQLiteRollbackEvent()

            for callback in callbacks {
                callback(event)
            }
        }, self.hookContext)
    }

    /// Must be run on the connection's executor.
    fileprivate func applyAuthorizerHook(enabled: Bool) {
        guard enabled else {
            _ = unsafe sqlite_nio_sqlite3_set_authorizer(self.handle.raw, nil, nil)
            return
        }

        _ = unsafe sqlite_nio_sqlite3_set_authorizer(self.handle.raw, { context, action, parameter1, parameter2, database, trigger in
            guard let connection = unsafe SQLiteConnection.connection(forHookContext: context) else {
                return SQLiteAuthorizerResponse.deny.rawValue
            }

            // Copy validator and observers while locked, then invoke unlocked (avoid deadlock)
            let (validator, observers) = connection.withBuckets { buckets in
                (buckets.authorizerValidator?.validate, Array(buckets.authorizerObservers.values))
            }

            guard validator != nil || !observers.isEmpty else { return SQLiteAuthorizerResponse.allow.rawValue }

            let event = unsafe SQLiteAuthorizerEvent(action: SQLiteAuthorizerAction(rawValue: action),
                                                     parameter1: parameter1.map(String.init(cString:)),
                                                     parameter2: parameter2.map(String.init(cString:)),
                                                     database: database.map(String.init(cString:)),
                                                     trigger: trigger.map(String.init(cString:)))

            // First check validator (if any)
            let validatorResponse = validator?(event) ?? .allow

            // If validator denies, short-circuit (don't run observers)
            if validatorResponse != .deny {
                // Run all observers (side effects only, cannot veto)
                for observer in observers {
                    observer(event)
                }
            }

            return validatorResponse.rawValue
        }, self.hookContext)
    }

    /// Must be run on the connection's executor.
    internal func clearAllHooks() {
        self.applyUpdateHook(enabled: false)
        self.applyCommitHook(enabled: false)
        self.applyRollbackHook(enabled: false)
        self.applyAuthorizerHook(enabled: false)
        self.observerBuckets.withLock { $0 = .init() }
    }
}
