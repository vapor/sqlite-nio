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

final class SQLiteConnectionHandle: @unchecked Sendable {
    var raw: OpaquePointer?
    
    init(_ raw: OpaquePointer?) {
        self.raw = raw
    }
}

public final class SQLiteConnection: SQLiteDatabase, Sendable {
    /// Available SQLite storage methods.
    public enum Storage: Equatable, Sendable {
        /// In-memory storage. Not persisted between application launches.
        /// Good for unit testing or caching.
        case memory

        /// File-based storage, persisted between application launches.
        case file(path: String)
    }

    // See `SQLiteDatabase.eventLoop`.
    public let eventLoop: any EventLoop
    
    // See `SQLiteDatabase.logger`.
    public let logger: Logger
    
    let handle: SQLiteConnectionHandle
    let threadPool: NIOThreadPool
    
    public var isClosed: Bool {
        self.handle.raw == nil
    }

    public static func open(
        storage: Storage = .memory,
        logger: Logger = .init(label: "codes.vapor.sqlite")
    ) -> EventLoopFuture<SQLiteConnection> {
        Self.open(
            storage: storage,
            threadPool: NIOThreadPool.singleton,
            logger: logger,
            on: MultiThreadedEventLoopGroup.singleton.any()
        )
    }
    
    public static func open(
        storage: Storage = .memory,
        logger: Logger = .init(label: "codes.vapor.sqlite")
    ) async throws -> SQLiteConnection {
        try await Self.open(
            storage: storage,
            threadPool: NIOThreadPool.singleton,
            logger: logger,
            on: MultiThreadedEventLoopGroup.singleton.any()
        )
    }
    
    public static func open(
        storage: Storage = .memory,
        threadPool: NIOThreadPool,
        logger: Logger = .init(label: "codes.vapor.sqlite"),
        on eventLoop: any EventLoop
    ) -> EventLoopFuture<SQLiteConnection> {
        threadPool.runIfActive(eventLoop: eventLoop) {
            try self.openInternal(storage: storage, threadPool: threadPool, logger: logger, eventLoop: eventLoop)
        }
    }
    
    public static func open(
        storage: Storage = .memory,
        threadPool: NIOThreadPool,
        logger: Logger = .init(label: "codes.vapor.sqlite"),
        on eventLoop: any EventLoop
    ) async throws -> SQLiteConnection {
        try await threadPool.runIfActive {
            try self.openInternal(storage: storage, threadPool: threadPool, logger: logger, eventLoop: eventLoop)
        }
    }
    
    private static func openInternal(storage: Storage, threadPool: NIOThreadPool, logger: Logger, eventLoop: any EventLoop) throws -> SQLiteConnection {
        let path: String
        switch storage {
        case .memory: path = ":memory:"
        case .file(let file): path = file
        }

        var handle: OpaquePointer?
        let openOptions = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
        let openRet = sqlite_nio_sqlite3_open_v2(path, &handle, openOptions, nil)
        guard openRet == SQLITE_OK else {
            throw SQLiteError(reason: .init(statusCode: openRet), message: "Failed to open to SQLite database at \(path)")
        }
        
        let busyRet = sqlite_nio_sqlite3_busy_handler(handle, { _, _ in 1 }, nil)
        guard busyRet == SQLITE_OK else {
            sqlite_nio_sqlite3_close(handle)
            throw SQLiteError(reason: .init(statusCode: busyRet), message: "Failed to set busy handler for SQLite database at \(path)")
        }

        logger.debug("Connected to sqlite db: \(path)")
        return SQLiteConnection(handle: handle, threadPool: threadPool, logger: logger, on: eventLoop)
    }

    init(
        handle: OpaquePointer?,
        threadPool: NIOThreadPool,
        logger: Logger,
        on eventLoop: any EventLoop
    ) {
        self.handle = .init(handle)
        self.threadPool = threadPool
        self.logger = logger
        self.eventLoop = eventLoop
    }
    
    var errorMessage: String? {
        sqlite_nio_sqlite3_errmsg(self.handle.raw).map { String(cString: $0) }
    }
    
    public static func libraryVersion() -> Int32 {
        sqlite_nio_sqlite3_libversion_number()
    }
    
    public static func libraryVersionString() -> String {
        String(cString: sqlite_nio_sqlite3_libversion())
    }
    
    public func lastAutoincrementID() -> EventLoopFuture<Int> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            numericCast(sqlite_nio_sqlite3_last_insert_rowid(self.handle.raw))
        }
    }

    public func lastAutoincrementID() async throws -> Int {
        try await self.threadPool.runIfActive {
            numericCast(sqlite_nio_sqlite3_last_insert_rowid(self.handle.raw))
        }
    }

    @preconcurrency
    public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }
    
    public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T {
        try await closure(self)
    }
    
    @preconcurrency
    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        logger.debug("\(query) \(binds)")
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.threadPool.submit {
            guard case $0 = NIOThreadPool.WorkItemState.active else {
                // Note: We should be throwing NIOThreadPoolError.ThreadPoolInactive here, but we can't
                // 'cause its initializer isn't public so we let `SQLITE_MISUSE` get the point across.
                return promise.fail(SQLiteError(reason: .misuse, message: "Thread pool is inactive"))
            }
            var futures: [EventLoopFuture<Void>] = []
            do {
                var statement = try SQLiteStatement(query: query, on: self)
                let columns = try statement.columns()
                try statement.bind(binds)
                while let row = try statement.nextRow(for: columns) {
                    futures.append(promise.futureResult.eventLoop.submit { onRow(row) })
                }
            } catch {
                return promise.fail(error) // EventLoopPromise.fail(_:), conveniently, returns Void
            }
            EventLoopFuture.andAllSucceed(futures, promise: promise)
        }
        return promise.futureResult
    }

    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) async throws {
        try await self.query(query, binds, onRow).get()
    }

    public func close() -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            sqlite_nio_sqlite3_close(self.handle.raw)
            self.handle.raw = nil
        }
    }

    public func close() async throws {
        try await self.threadPool.runIfActive {
            sqlite_nio_sqlite3_close(self.handle.raw)
            self.handle.raw = nil
        }
    }

	public func install(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		self.logger.trace("Adding custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.install(in: self)
		}
	}

	public func install(customFunction: SQLiteCustomFunction) async throws {
		self.logger.trace("Adding custom function \(customFunction.name)")
		return try await self.threadPool.runIfActive {
            try customFunction.install(in: self)
		}
	}

	public func uninstall(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		self.logger.trace("Removing custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.uninstall(in: self)
		}
	}

	public func uninstall(customFunction: SQLiteCustomFunction) async throws {
		self.logger.trace("Removing custom function \(customFunction.name)")
		return try await self.threadPool.runIfActive {
            try customFunction.uninstall(in: self)
		}
	}

    deinit {
        assert(self.handle.raw == nil, "SQLiteConnection was not closed before deinitializing")
    }
}
