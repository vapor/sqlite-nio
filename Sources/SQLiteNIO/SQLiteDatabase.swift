import NIOCore
import NIOPosix
import CSQLite
import Logging

public protocol SQLiteDatabase {
    var logger: Logger { get }
    
    var eventLoop: any EventLoop { get }
    
    @preconcurrency
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void>
    
    @preconcurrency
    func withConnection<T>(
        _: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T>
}

extension SQLiteDatabase {
    /// Logger-less version of ``query(_:_:logger:_:)``.
    @preconcurrency
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = [],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.query(query, binds, logger: self.logger, onRow)
    }
    
    /// Logger-less async version of ``query(_:_:logger:_:)``.
    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) async throws {
        try await self.query(query, binds, logger: self.logger, onRow).get()
    }

    /// Data-returning version of ``query(_:_:_:)-2zmfi``.
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = []
    ) -> EventLoopFuture<[SQLiteRow]> {
        #if swift(<5.10)
        let rows: UnsafeMutableTransferBox<[SQLiteRow]> = .init([])
        
        return self.query(query, binds, logger: self.logger) { rows.wrappedValue.append($0) }.map { rows.wrappedValue }
        #else
        nonisolated(unsafe) var rows: [SQLiteRow] = []
        
        return self.query(query, binds, logger: self.logger) { rows.append($0) }.map { rows }
        #endif
    }
    
    /// Data-returning version of ``query(_:_:_:)-3s65n``.
    public func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        try await self.query(query, binds).get()
    }

    /// Async version of ``withConnection(_:)-48y34``.
    public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T {
        try await self.withConnection { conn in
            conn.eventLoop.makeFutureWithTask {
                try await closure(conn)
            }
        }.get()
    }
}

#if swift(<5.10)
fileprivate final class UnsafeMutableTransferBox<Wrapped: Sendable>: @unchecked Sendable {
    var wrappedValue: Wrapped
    init(_ wrappedValue: Wrapped) { self.wrappedValue = wrappedValue }
}
#endif

extension SQLiteDatabase {
    public func logging(to logger: Logger) -> any SQLiteDatabase {
        SQLiteDatabaseCustomLogger(database: self, logger: logger)
    }
}

private struct SQLiteDatabaseCustomLogger: SQLiteDatabase {
    let database: any SQLiteDatabase
    var eventLoop: any EventLoop { self.database.eventLoop }
    let logger: Logger
    
    func withConnection<T>(_ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.database.withConnection(closure)
    }
    func withConnection<T>(_ closure: @escaping @Sendable (SQLiteConnection) async throws -> T) async throws -> T {
        try await self.database.withConnection(closure)
    }
    
    func query(_ query: String, _ binds: [SQLiteData], logger: Logger, _ onRow: @escaping @Sendable (SQLiteRow) -> Void) -> EventLoopFuture<Void> {
        self.database.query(query, binds, logger: logger, onRow)
    }
    
    func query(_ query: String, _ binds: [SQLiteData] = [], _ onRow: @escaping @Sendable (SQLiteRow) -> Void) -> EventLoopFuture<Void> {
        self.database.query(query, binds, onRow)
    }
    func query(_ query: String, _ binds: [SQLiteData], _ onRow: @escaping @Sendable (SQLiteRow) -> Void) async throws {
        try await self.database.query(query, binds, onRow)
    }
    
    func query(_ query: String, _ binds: [SQLiteData] = []) -> EventLoopFuture<[SQLiteRow]> {
        self.database.query(query, binds)
    }
    func query(_ query: String, _ binds: [SQLiteData] = []) async throws -> [SQLiteRow] {
        try await self.database.query(query, binds)
    }
    
    func logging(to logger: Logger) -> any SQLiteDatabase {
        Self(database: self.database, logger: logger)
    }
}
