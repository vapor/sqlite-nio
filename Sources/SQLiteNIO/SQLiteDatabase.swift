#if canImport(NIOCore)
import NIOCore
import NIOPosix
#endif
import VaporCSQLite
import Logging

/// A protocol describing the minimum requirements for an object allowing access to a generic SQLite database.
///
/// This protocol is intended to assist with connection pooling and other "smells like a simple database but isn't"
/// use cases. In retrospect, it has become clear that it was poorly designed. Users and implementations alike
/// should try to use ``SQLiteConnection`` directly whenever possible.
public protocol SQLiteDatabase: Sendable {
    /// The logger used by the connection.
    var logger: Logger { get }
    
    #if canImport(NIOCore)
    /// The event loop on which operations on the connection execute.
    var eventLoop: any EventLoop { get }
    #endif
    
    #if canImport(NIOCore)
    /// Execute a query on the connection, calling the provided closure for each result row (if any).
    ///
    /// This is the primary interface to connections vended via this protocol.
    ///
    /// > Warning: The `logger` parameter of this method is a holdover from Fluent 4's development cycle that
    /// > should have been removed before the final release. Unfortunately, this didn't happen, and semantic
    /// > versioning has left the API stuck with it ever single. Callers of this API should either always pass
    /// > the value of the ``logger`` property or use ``query(_:_:_:)`` instead. Implementations that wish to
    /// > conform to this protocol should ignore the parameter entirely in favor of the ``logger`` property.
    /// > At no time during SQLiteNIO's lifetime has this parameter ever been honored; indeed, at the time of
    /// > this writing, ``SQLiteConnection``'s implementation of this method doesn't use _any_ logger at all.
    ///
    /// - Parameters:
    ///   - query: The query string to execute.
    ///   - binds: An ordered list of ``SQLiteData`` items to use as bound parameters for the query.
    ///   - logger: Ignored. See above discussion for details.
    ///   - onRow: A closure to invoke for each result row returned by the query, if any.
    /// - Returns: A future completed when the query has executed and returned all results (if any).
    @preconcurrency
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void>
    #endif  // canImport(NIOCore)

    /// Execute a query on the connection, calling the provided closure for each result row (if any).
    ///
    /// This is the primary Concurrency-based interface to connections vended via this protocol. A default
    /// implementation is provided for protocol implementors who predate the existence of this requirement.
    ///
    /// - Parameters:
    ///   - query: The query string to execute.
    ///   - binds: An ordered list of ``SQLiteData`` items to use as bound parameters for the query.
    ///   - onRow: A closure to invoke for each result row returned by the query, if any.
    /// - Returns: A future completed when the query has executed and returned all results (if any).
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) async throws

    #if canImport(NIOCore)
    /// Call the provided closure with a concrete ``SQLiteConnection`` instance.
    ///
    /// This method is required to provide a connection object which executes all queries directed to it in the
    /// same "session" (e.g. always on the same connection, such as without rotating through a pool).
    ///
    /// - Parameter closure: The closure to invoke. Unless the closure changes the connection's state itself or the
    ///   connection is closed by SQLite due to error, it is guaranteed to remain valid until the future returned by
    ///   the closure is completed or failed.
    /// - Returns: A future signaling completion of the closure and containing the closure's result, if any.
    @preconcurrency
    func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T>
    #endif  // canImport(NIOCore)

    /// Call the provided closure with a concrete ``SQLiteConnection`` instance, concurrency version.
    ///
    /// This method is required to provide a connection object which executes all queries directed to it in the
    /// same "session" (e.g. always on the same connection, such as without rotating through a pool). A default
    /// implementation is provided for protocol implementors who predate the existence of this requirement.
    ///
    /// - Parameter closure: The closure to invoke. Unless the closure changes the connection's state itself or the
    ///   connection is closed by SQLite due to error, it is guaranteed to remain valid until the future returned by
    ///   the closure is completed or failed.
    /// - Returns: A future signaling completion of the closure and containing the closure's result, if any.
    func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T
}

/// Convenience helpers and Concurrency-aware variants.
extension SQLiteDatabase {
    #if canImport(NIOCore)
    /// Convenience method for calling ``query(_:_:logger:_:)`` with the connection's logger.
    ///
    /// Callers are strongly encouraged to always use this method or its async equivalent (``query(_:_:_:)``) instead
    /// of the protocol requirement.
    @preconcurrency
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = [],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.query(query, binds, logger: self.logger, onRow)
    }
    
    /// Convenience method for calling ``query(_:_:logger:_:)`` with the connection's logger (async version).
    ///
    /// Callers are strongly encouraged to always use this method or its futures-based equivalent (``query(_:_:_:)``)
    /// instead of the protocol requirement.
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = [],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) async throws {
        try await self.query(query, binds, logger: self.logger, onRow).get()
    }

    /// Wrapper for ``query(_:_:_:)`` which returns the result rows (if any) rather than calling a closure.
    public func query(_ query: String, _ binds: [SQLiteData] = []) -> EventLoopFuture<[SQLiteRow]> {
        nonisolated(unsafe) var rows: [SQLiteRow] = []
        
        return self.query(query, binds, logger: self.logger) { rows.append($0) }.map { rows }
    }
    #endif  // canImport(NIOCore)
    
    /// Wrapper for ``query(_:_:_:)`` which returns the result rows (if any) rather than calling a
    /// closure (async version).
    public func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        nonisolated(unsafe) var rows: [SQLiteRow] = []

        try await self.query(query, binds) { rows.append($0) }
        return rows
    }

    #if canImport(NIOCore)
    /// Async version of ``withConnection(_:)-48y34``.
    public func withConnection<T: Sendable>(
        _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T {
        try await self.withConnection { conn in
            conn.eventLoop.makeFutureWithTask {
                try await closure(conn)
            }
        }.get()
    }
    #endif  // canImport(NIOCore)
}

#if swift(<5.10)
/// A wrapper type to avoid `Sendable` warnings for mutable captures that are otherwise safe.
///
/// This effectively acts as workaround for the absence of `nonisolated(unsafe)` before Swift 5.10.
fileprivate final class UnsafeMutableTransferBox<Wrapped: Sendable>: @unchecked Sendable {
    var wrappedValue: Wrapped
    init(_ wrappedValue: Wrapped) { self.wrappedValue = wrappedValue }
}
#endif

extension SQLiteDatabase {
    /// Return a new ``SQLiteDatabase`` which is indistinguishable from the original save that its
    /// ``SQLiteDatabase/logger`` property is replaced by the given `Logger`.
    ///
    /// This has the effect of redirecting logging performed on or by the original database to the
    /// provided `Logger`.
    ///
    /// > Warning: The log redirection applies only to the new ``SQLiteDatabase`` that is returned from
    /// > this method; logging operations performed on the original (i.e. `self`) are unaffected.
    ///
    /// > Note: Because this method returns a generic ``SQLiteDatabase``, the type it returns need not be public
    /// > API. Unfortunately, this also means that no inlining or static dispatch of the implementation is
    /// > possible, thus imposing a performance penalty on the use of this otherwise trivial utility.
    ///
    /// - Parameter logger: The new `Logger` to use.
    /// - Returns: A database object which logs to the new `Logger`.
    public func logging(to logger: Logger) -> any SQLiteDatabase {
        SQLiteDatabaseCustomLogger(database: self, logger: logger)
    }
}

/// Replaces the `Logger` of an existing ``SQLiteDatabase`` while forwarding all other properties and
/// methods to the original.
private struct SQLiteDatabaseCustomLogger<D: SQLiteDatabase>: SQLiteDatabase {
    /// The underlying database.
    let database: D

    // See `SQLiteDatabase.logger`.
    let logger: Logger

    #if canImport(NIOCore)
    // See `SQLiteDatabase.eventLoop`.
    var eventLoop: any EventLoop { self.database.eventLoop }
    
    // See `SQLiteDatabase.withConnection(_:)`.
    func withConnection<T>(_ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.database.withConnection(closure)
    }
    #endif  // canImport(NIOCore)
    // See `SQLiteDatabase.withConnection(_:)`.
    func withConnection<T: Sendable>(_ closure: @escaping @Sendable (SQLiteConnection) async throws -> T) async throws -> T {
        try await self.database.withConnection(closure)
    }
    
    #if canImport(NIOCore)
    // See `SQLiteDatabase.query(_:_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData], logger: Logger, _ onRow: @escaping @Sendable (SQLiteRow) -> Void) -> EventLoopFuture<Void> {
        self.database.query(query, binds, logger: logger, onRow)
    }
    
    // See `SQLiteDatabase.query(_:_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData] = [], _ onRow: @escaping @Sendable (SQLiteRow) -> Void) -> EventLoopFuture<Void> {
        self.database.query(query, binds, onRow)
    }
    #endif  // canImport(NIOCore)

    // See `SQLiteDatabase.query(_:_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData], _ onRow: @escaping @Sendable (SQLiteRow) -> Void) async throws {
        try await self.database.query(query, binds, onRow)
    }
    
    #if canImport(NIOCore)
    // See `SQLiteDatabase.query(_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData] = []) -> EventLoopFuture<[SQLiteRow]> {
        self.database.query(query, binds)
    }
    #endif
    
    // See `SQLiteDatabase.query(_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        try await self.database.query(query, binds)
    }
    
    // See `SQLiteDatabase.logger(_:)`.
    func logging(to logger: Logger) -> any SQLiteDatabase {
        /// N.B.: We explicitly override this method so that if ``SQLiteDatabase/logging(to:)`` is called in a nested
        /// or chained fashion, methods still only have to be forwarded at most once.
        Self(database: self.database, logger: logger)
    }
}
