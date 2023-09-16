import NIOCore
import NIOPosix
import CSQLite
import Logging

public protocol SQLiteDatabase {
    var logger: Logger { get }
    var eventLoop: EventLoop { get }
    
    #if swift(>=5.7)
    @preconcurrency func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void>
    #else
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void>
    #endif
    
    #if swift(>=5.7)
    @preconcurrency func withConnection<T>(
        _: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T>
    #else
    func withConnection<T>(
        _: @escaping (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T>
    #endif
}

extension SQLiteDatabase {
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = [],
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.query(query, binds, logger: self.logger, onRow)
    }
    
    public func query(
        _ query: String,
        _ binds: [SQLiteData] = []
    ) -> EventLoopFuture<[SQLiteRow]> {
        var rows: [SQLiteRow] = []
        return self.query(query, binds, logger: self.logger) { row in
            rows.append(row)
        }.map { rows }
    }
  }

extension SQLiteDatabase {
    public func logging(to logger: Logger) -> SQLiteDatabase {
        _SQLiteDatabaseCustomLogger(database: self, logger: logger)
    }
}

private struct _SQLiteDatabaseCustomLogger: SQLiteDatabase {
    let database: SQLiteDatabase
    var eventLoop: EventLoop {
        self.database.eventLoop
    }
    let logger: Logger
    
    #if swift(>=5.7)
    @preconcurrency func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        self.database.withConnection(closure)
    }
    #else
    func withConnection<T>(
        _ closure: @escaping (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        self.database.withConnection(closure)
    }
    #endif
    
    #if swift(>=5.7)
    @preconcurrency func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.database.query(query, binds, logger: logger, onRow)
    }
    #else
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.database.query(query, binds, logger: logger, onRow)
    }
    #endif
}

public final class SQLiteConnection: SQLiteDatabase {
    /// Available SQLite storage methods.
    public enum Storage {
        /// In-memory storage. Not persisted between application launches.
        /// Good for unit testing or caching.
        case memory

        /// File-based storage, persisted between application launches.
        case file(path: String)
    }

    public let eventLoop: EventLoop
    
    internal var handle: OpaquePointer?
    internal let threadPool: NIOThreadPool
    public let logger: Logger
    
    public var isClosed: Bool {
        return self.handle == nil
    }

    public static func open(
        storage: Storage = .memory,
        threadPool: NIOThreadPool,
        logger: Logger = .init(label: "codes.vapor.sqlite"),
        on eventLoop: EventLoop
    ) -> EventLoopFuture<SQLiteConnection> {
        let path: String
        switch storage {
        case .memory:
            path = ":memory:"
        case .file(let file):
            path = file
        }

        return threadPool.runIfActive(eventLoop: eventLoop) {
            var handle: OpaquePointer?
            let options = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI

            if sqlite_nio_sqlite3_open_v2(path, &handle, options, nil) == SQLITE_OK, sqlite_nio_sqlite3_busy_handler(handle, { _, _ in 1 }, nil) == SQLITE_OK {
                let connection = SQLiteConnection(
                    handle: handle,
                    threadPool: threadPool,
                    logger: logger,
                    on: eventLoop
                )
                logger.debug("Connected to sqlite db: \(path)")
                return connection
            } else {
                logger.error("Failed to connect to sqlite db: \(path)")
                throw SQLiteError(reason: .cantOpen, message: "Cannot open SQLite database: \(storage)")
            }
        }
    }

    init(
        handle: OpaquePointer?,
        threadPool: NIOThreadPool,
        logger: Logger,
        on eventLoop: EventLoop
    ) {
        self.handle = handle
        self.threadPool = threadPool
        self.logger = logger
        self.eventLoop = eventLoop
    }
    
    public static func libraryVersion() -> Int32 {
        sqlite_nio_sqlite3_libversion_number()
    }
    
    public static func libraryVersionString() -> String {
        String(cString: sqlite_nio_sqlite3_libversion())
    }
    
    public func lastAutoincrementID() -> EventLoopFuture<Int> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            let rowid = sqlite_nio_sqlite3_last_insert_rowid(self.handle)
            return numericCast(rowid)
        }
    }

    internal var errorMessage: String? {
        if let raw = sqlite_nio_sqlite3_errmsg(self.handle) {
            return String(cString: raw)
        } else {
            return nil
        }
    }
    
    #if swift(>=5.7)
    @preconcurrency public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }
    #else
    public func withConnection<T>(
        _ closure: @escaping (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }
    #endif
    
    #if swift(>=5.7)
    @preconcurrency public func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self._query(query, binds, logger: logger, onRow)
    }
    #else
    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self._query(query, binds, logger: logger, onRow)
    }
    #endif
    
    private func _query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
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
                let statement = try SQLiteStatement(query: query, on: self)
                let columns = try statement.columns()
                try statement.bind(binds)
                while let row = try statement.nextRow(for: columns) {
                    futures.append(self.eventLoop.submit { onRow(row) })
                }
            } catch {
                return promise.fail(error) // EventLoopPromise.fail(_:), conveniently, returns Void
            }
            EventLoopFuture.andAllSucceed(futures, promise: promise)
        }
        return promise.futureResult
    }

    public func close() -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) { 
            sqlite_nio_sqlite3_close(self.handle)
        }.map { _ in
            self.handle = nil
        }
    }

	public func install(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		logger.trace("Adding custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.install(in: self)
		}
	}

	public func uninstall(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		logger.trace("Removing custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.uninstall(in: self)
		}
	}

    deinit {
        assert(self.handle == nil, "SQLiteConnection was not closed before deinitializing")
    }
}

extension SQLiteConnection {
    static func open(
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
}
