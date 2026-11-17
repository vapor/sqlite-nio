import Synchronization

/// A protocol describing the minimum requirements for an object allowing access to a generic SQLite database.
///
/// This protocol is intended to assist with connection pooling and other "smells like a simple database but isn't"
/// use cases. In retrospect, it has become clear that it was poorly designed. Users and implementations alike
/// should try to use ``SQLiteConnection`` directly whenever possible.
public protocol SQLiteDatabase: Sendable {   
    /// Execute a query on the connection, calling the provided closure for each result row (if any).
    ///
    /// This is the primary Concurrency-based interface to connections vended via this protocol. A default
    /// implementation is provided for protocol implementors who predate the existence of this requirement.
    ///
    /// - Parameters:
    ///   - query: The query string to execute.
    ///   - binds: An ordered list of ``SQLiteData`` items to use as bound parameters for the query.
    ///   - onRow: A closure to invoke for each result row returned by the query, if any. It may be called on
    ///     a different thread from the caller, and is never called after this method returns.
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        _ onRow: @Sendable (SQLiteRow) -> Void
    ) async throws

    /// Call the provided closure with a concrete ``SQLiteConnection`` instance, concurrency version.
    ///
    /// This method is required to provide a connection object which executes all queries directed to it in the
    /// same "session" (e.g. always on the same connection, such as without rotating through a pool). A default
    /// implementation is provided for protocol implementors who predate the existence of this requirement.
    ///
    /// - Parameter closure: The closure to invoke. Unless the closure changes the connection's state itself or the
    ///   connection is closed by SQLite due to error, it is guaranteed to remain valid until the closure returns
    ///   or throws.
    /// - Returns: The closure's result, if any.
    func withConnection<T>(
        _ closure: @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T
}

/// Convenience helpers and Concurrency-aware variants.
extension SQLiteDatabase {        
    /// Wrapper for ``query(_:_:_:)`` which returns the result rows (if any) rather than calling a
    /// closure (async version).
    public func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        let rows = Mutex<[SQLiteRow]>([])

        try await self.query(query, binds) { row in rows.withLock { $0.append(row) } }
        return rows.withLock { $0 }
    }
}

/// Replaces the `Logger` of an existing ``SQLiteDatabase`` while forwarding all other properties and
/// methods to the original.
private struct SQLiteDatabaseCustomLogger<D: SQLiteDatabase>: SQLiteDatabase {
    /// The underlying database.
    let database: D
    
    // See `SQLiteDatabase.withConnection(_:)`.
    func withConnection<T: Sendable>(_ closure: @Sendable (SQLiteConnection) async throws -> T) async throws -> T {
        try await self.database.withConnection(closure)
    }

    // See `SQLiteDatabase.query(_:_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData], _ onRow: @Sendable (SQLiteRow) -> Void) async throws {
        try await self.database.query(query, binds, onRow)
    }
    
    // See `SQLiteDatabase.query(_:_:)`.
    func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        try await self.database.query(query, binds)
    }
}
