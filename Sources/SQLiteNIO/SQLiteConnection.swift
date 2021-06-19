import NIO
import CSQLite
import Logging

public protocol SQLiteDatabase {
    var logger: Logger { get }
    var eventLoop: EventLoop { get }
    
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void>
    
    func withConnection<T>(_: @escaping (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T>
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
    
    func withConnection<T>(_ closure: @escaping (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.database.withConnection(closure)
    }
    
    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.database.query(query, binds, logger: logger, onRow)
    }
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

        let promise = eventLoop.makePromise(of: SQLiteConnection.self)
        threadPool.submit { state in
            var handle: OpaquePointer?
            let options = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
            if sqlite3_open_v2(path, &handle, options, nil) == SQLITE_OK, sqlite3_busy_handler(handle, { _, _ in 1 }, nil) == SQLITE_OK {
                let connection = SQLiteConnection(
                    handle: handle,
                    threadPool: threadPool,
                    logger: logger,
                    on: eventLoop
                )
                logger.debug("Connected to sqlite db: \(path)")
                promise.succeed(connection)
            } else {
                logger.error("Failed to connect to sqlite db: \(path)")
                promise.fail(SQLiteError(reason: .cantOpen, message: "Cannot open SQLite database: \(storage)"))
            }
        }
        return promise.futureResult
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

    public func lastAutoincrementID() -> EventLoopFuture<Int> {
        let promise = self.eventLoop.makePromise(of: Int.self)
        self.threadPool.submit { _ in
            let rowid = sqlite3_last_insert_rowid(self.handle)
            promise.succeed(numericCast(rowid))
        }
        return promise.futureResult
    }

    internal var errorMessage: String? {
        if let raw = sqlite3_errmsg(self.handle) {
            return String(cString: raw)
        } else {
            return nil
        }
    }
    
    public func withConnection<T>(_ closure: @escaping (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        closure(self)
    }
    
    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        logger.debug("\(query) \(binds)")
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.threadPool.submit { state in
            do {
                let statement = try SQLiteStatement(query: query, on: self)
                try statement.bind(binds)
                let columns = try statement.columns()
                var callbacks: [EventLoopFuture<Void>] = []
                while let row = try statement.nextRow(for: columns) {
                    let callback = self.eventLoop.submit {
                        onRow(row)
                    }
                    callbacks.append(callback)
                }
                EventLoopFuture<Void>.andAllSucceed(callbacks, on: self.eventLoop)
                    .cascade(to: promise)
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }

    public func close() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.threadPool.submit { state in
            sqlite3_close(self.handle)
            self.eventLoop.submit {
                self.handle = nil
            }.cascade(to: promise)
        }
        return promise.futureResult
    }

	public func install(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		logger.debug("Adding custom function \(customFunction.name)")
		let promise = self.eventLoop.makePromise(of: Void.self)
		self.threadPool.submit { state in
			do {
				try customFunction.install(in: self)
				promise.succeed(())
			} catch {
				promise.fail(error)
			}
		}
		return promise.futureResult
	}

	public func uninstall(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		logger.debug("Removing custom function \(customFunction.name)")
		let promise = self.eventLoop.makePromise(of: Void.self)
		self.threadPool.submit { state in
			do {
				try customFunction.uninstall(in: self)
				promise.succeed(())
			} catch {
				promise.fail(error)
			}
		}
		return promise.futureResult
	}

    deinit {
        assert(self.handle == nil, "SQLiteConnection was not closed before deinitializing")
    }
}
