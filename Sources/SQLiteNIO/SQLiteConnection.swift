import NIOCore
#if swift(<5.9)
import NIOConcurrencyHelpers
#endif
import NIOPosix
import CSQLite
import Logging

/// A wrapper for the `OpaquePointer` used to represent an open `sqlite3` handle.
///
/// This wrapper serves two purposes:
///
/// - Silencing `Sendable` warnings relating to use of the pointer, and
/// - Preventing confusion with other C types which import as opaque pointers.
///
/// The use of `@unchecked Sendable` is safe for this type because:
///
/// - We ensure that access to the raw handle only ever takes place while running on an `NIOThreadPool`.
///   This does not prevent concurrent access to the handle from multiple threads, but does tend to limit
///   the possibility of misuse (and of course prevents CPU-bound work from ending up on an event loop).
/// - The embedded SQLite is built with `SQLITE_THREADSAFE=1` (serialized mode, permitting safe use of a
///   given connection handle simultaneously from multiple threads).
/// - We include `SQLITE_OPEN_FULLMUTEX` when calling `sqlite_open_v2()`, guaranteeing the use of the
///   serialized threading mode for each connection even if someone uses `sqlite3_config()` to make the
///   less strict multithreaded mode the default.
///
/// And finally, the use of `@unchecked` in particular is justified because:
///
/// 1. We need to be able to mutate the value in order to make it `nil` when the connection it represented
///    is closed. We use the `nil` value as a sentinel by which we determine a connection's validity. Also,
///    _not_ `nil`-ing it out would leave a dangling/freed pointer in place, which is just begging for a
///    segfault.
/// 2. An `OpaquePointer` can not be natively `Sendable`, by definition; it's opaque! The `@unchecked`
///    annotation is how we tell the compiler "we've taken the appropriate precautions to make moving
///    values of this type between isolation regions safe".
///
/// > Note: It appears that in Swift 5.8, TSan likes to throw false positive warnings about this type, hence
/// > the compiler conditionals around using bogus extra locking.
final class SQLiteConnectionHandle: @unchecked Sendable {
    #if swift(<5.9)
    private let _raw: NIOLockedValueBox<OpaquePointer?>
    var raw: OpaquePointer? {
        get { self._raw.withLockedValue { $0 } }
        set { self._raw.withLockedValue { $0 = newValue } }
    }
    
    init(_ raw: OpaquePointer?) {
        self._raw = .init(raw)
    }
    #else
    var raw: OpaquePointer?
    
    init(_ raw: OpaquePointer?) {
        self.raw = raw
    }
    #endif
}

/// Represents a single open connection to an SQLite database, either on disk or in memory.
public final class SQLiteConnection: SQLiteDatabase, Sendable {
    /// The possible storage types for an SQLite database.
    public enum Storage: Equatable, Sendable {
        /// An SQLite database stored entirely in memory.
        ///
        /// In-memory databases persist only so long as the connection to them is open, and are not shared
        /// between processes. In addition, because this package builds the sqlite3 amalgamation with the
        /// recommended `SQLITE_OMIT_SHARED_CACHE` option, it is not possible to open multiple connections
        /// to a single in-memory database; use a temporary file instead.
        ///
        /// In-memory databases are useful for unit testing or caching purposes.
        case memory

        /// An SQLite database stored in a file at the specified path.
        /// 
        /// If a relative path is specified, it is interpreted relative to the current working directory of the
        /// current process (e.g. `NIOFileSystem.shared.currentWorkingDirectory`) at the time of establishing
        /// the connection. It is strongly recommended that users always use absolute paths whenever possible.
        ///
        /// File-based databases persist as long as the files representing them on disk does, and can be opened
        /// multiple times within the same process or even by multiple processes if configured properly.
        case file(path: String)
    }

    /// Return the version of the embedded libsqlite3 as a 32-bit integer value.
    /// 
    /// The value is laid out identicallly to [the `SQLITE_VERSION_NUMBER` constant](c_source_id).
    ///
    /// [c_source_id]: https://sqlite.org/c3ref/c_source_id.html
    public static func libraryVersion() -> Int32 {
        sqlite_nio_sqlite3_libversion_number()
    }
    
    /// Return the version of the embedded libsqlite3 as a string.
    ///
    /// The string is formatted identically to [the `SQLITE_VERSION` constant](c_source_id).
    ///
    /// [c_source_id]: https://sqlite.org/c3ref/c_source_id.html
    public static func libraryVersionString() -> String {
        String(cString: sqlite_nio_sqlite3_libversion())
    }
    
    /// Open a new connection to an SQLite database.
    ///
    /// This is equivalent to invoking ``open(storage:threadPool:logger:on:)-64n3x`` using the
    ///  `NIOThreadPool` and `MultiThreadedEventLoopGroup` singletons. This is the recommended configuration
    ///  for all users.
    ///
    /// - Parameters:
    ///   - storage: Specifies the location of the database for the connection. See ``Storage`` for details.
    ///   - logger: The logger used by the connection. Defaults to a new `Logger`.
    /// - Returns: A future whose value on success is a new connection object.
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
    
    /// Open a new connection to an SQLite database.
    ///
    /// - Parameters:
    ///   - storage: Specifies the location of the database for the connection. See ``Storage`` for details.
    ///   - threadPool: An `NIOThreadPool` used to execute all libsqlite3 API calls for this connection.
    ///   - logger: The logger used by the connection. Defaults to a new `Logger`.
    ///   - eventLoop: An `EventLoop` to associate with the connection for creating futures.
    /// - Returns: A future whose value on success is a new connection object.
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
    
    /// The underlying implementation of ``open(storage:threadPool:logger:on:)-64n3x`` and
    /// ``open(storage:threadPool:logger:on:)-3m3lb``.
    private static func openInternal(
        storage: Storage,
        threadPool: NIOThreadPool,
        logger: Logger,
        eventLoop: any EventLoop
    ) throws -> SQLiteConnection {
        let path: String
        switch storage {
        case .memory: path = ":memory:"
        case .file(let file): path = file
        }

        var handle: OpaquePointer?
        let openOptions = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI | SQLITE_OPEN_EXRESCODE
        let openRet = sqlite_nio_sqlite3_open_v2(path, &handle, openOptions, nil)
        guard openRet == SQLITE_OK else {
            throw SQLiteError(reason: .init(statusCode: openRet), message: "Failed to open to SQLite database at \(path)")
        }
        
        let busyRet = sqlite_nio_sqlite3_busy_handler(handle, { _, _ in 1 }, nil)
        guard busyRet == SQLITE_OK else {
            sqlite_nio_sqlite3_close(handle)
            throw SQLiteError(reason: .init(statusCode: busyRet), message: "Failed to set busy handler for SQLite database at \(path)")
        }

        logger.debug("Connected to sqlite database", metadata: ["path": .string(path)])
        return SQLiteConnection(handle: handle, threadPool: threadPool, logger: logger, on: eventLoop)
    }

    // See `SQLiteDatabase.eventLoop`.
    public let eventLoop: any EventLoop
    
    // See `SQLiteDatabase.logger`.
    public let logger: Logger
    
    /// The underlying `sqlite3` connection handle.
    let handle: SQLiteConnectionHandle
    
    /// The thread pool used by this connection when calling libsqlite3 APIs.
    private let threadPool: NIOThreadPool
    
    /// Initialize a new ``SQLiteConnection``. Internal use only.
    private init(
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
    
    /// Returns the most recent error message from the connection as a string.
    ///
    /// This is only valid until another operation is performed on the connection; watch out for races.
    var errorMessage: String? {
        sqlite_nio_sqlite3_errmsg(self.handle.raw).map { String(cString: $0) }
    }
    
    /// `false` if the connection is valid, `true` if not.
    public var isClosed: Bool {
        self.handle.raw == nil
    }

    /// Returns the last value generated by auto-increment functionality (either the version implied by
    /// `INTEGER PRIMARY KEY` or that of the explicit `AUTO_INCREMENT` modifier) on this database.
    /// 
    /// Only valid until the next operation is performed on the connection; watch out for races.
    ///
    /// - Returns: A future containing the most recently inserted rowid value.
    public func lastAutoincrementID() -> EventLoopFuture<Int> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            numericCast(sqlite_nio_sqlite3_last_insert_rowid(self.handle.raw))
        }
    }

    // See `SQLiteDatabase.withConnection(_:)`.
    @preconcurrency
    public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }
    
    // See `SQLiteDatabase.query(_:_:logger:_:)`.
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

    /// Close the connection and invalidate its handle.
    /// 
    /// No further operations may be performed on the connection after calling this method.
    ///
    /// - Returns: A future indicating completion of connection closure.
    public func close() -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            sqlite_nio_sqlite3_close(self.handle.raw)
            self.handle.raw = nil
        }
    }
    
    /// Install the provided ``SQLiteCustomFunction`` on the connection.
    ///
    /// - Parameter customFunction: The function to install.
    /// - Returns: A future indicating completion of the install operation.
	public func install(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		self.logger.trace("Adding custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.install(in: self)
		}
	}

    /// Uninstall the provided ``SQLiteCustomFunction`` from the connection.
    ///
    /// - Parameter customFunction: The function to remove.
    /// - Returns: A future indicating completion of the uninstall operation.
	public func uninstall(customFunction: SQLiteCustomFunction) -> EventLoopFuture<Void> {
		self.logger.trace("Removing custom function \(customFunction.name)")
		return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            try customFunction.uninstall(in: self)
		}
	}

    /// Deinitializer for ``SQLiteConnection``.
    deinit {
        assert(self.handle.raw == nil, "SQLiteConnection was not closed before deinitializing")
    }
}

extension SQLiteConnection {
    /// Open a new connection to an SQLite database.
    ///
    /// This is equivalent to invoking ``open(storage:threadPool:logger:on:)-3m3lb`` using the
    ///  `NIOThreadPool` and `MultiThreadedEventLoopGroup` singletons. This is the recommended configuration
    ///  for all users.
    ///
    /// - Parameters:
    ///   - storage: Specifies the location of the database for the connection. See ``Storage`` for details.
    ///   - logger: The logger used by the connection. Defaults to a new `Logger`.
    /// - Returns: A future whose value on success is a new connection object.
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
    
    /// Open a new connection to an SQLite database.
    ///
    /// - Parameters:
    ///   - storage: Specifies the location of the database for the connection. See ``Storage`` for details.
    ///   - threadPool: An `NIOThreadPool` used to execute all libsqlite3 API calls for this connection.
    ///   - logger: The logger used by the connection. Defaults to a new `Logger`.
    ///   - eventLoop: An `EventLoop` to associate with the connection for creating futures.
    /// - Returns: A new connection object.
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
    
    /// Returns the last value generated by auto-increment functionality (either the version implied by
    /// `INTEGER PRIMARY KEY` or that of the explicit `AUTO_INCREMENT` modifier) on this database.
    /// 
    /// Only valid until the next operation is performed on the connection; watch out for races.
    ///
    /// - Returns: The most recently inserted rowid value.
    public func lastAutoincrementID() async throws -> Int {
        try await self.threadPool.runIfActive {
            numericCast(sqlite_nio_sqlite3_last_insert_rowid(self.handle.raw))
        }
    }

    /// Concurrency-aware variant of ``withConnection(_:)-8cmxp``.
    public func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
    ) async throws -> T {
        try await closure(self)
    }
    
    /// Concurrency-aware variant of ``query(_:_:_:)-etrj``.
    public func query(
        _ query: String,
        _ binds: [SQLiteData],
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) async throws {
        try await self.query(query, binds, onRow).get()
    }

    /// Close the connection and invalidate its handle.
    /// 
    /// No further operations may be performed on the connection after calling this method.
    public func close() async throws {
        try await self.threadPool.runIfActive {
            sqlite_nio_sqlite3_close(self.handle.raw)
            self.handle.raw = nil
        }
    }

    /// Install the provided ``SQLiteCustomFunction`` on the connection.
    ///
    /// - Parameter customFunction: The function to install.
	public func install(customFunction: SQLiteCustomFunction) async throws {
		self.logger.trace("Adding custom function \(customFunction.name)")
		return try await self.threadPool.runIfActive {
            try customFunction.install(in: self)
		}
	}

    /// Uninstall the provided ``SQLiteCustomFunction`` from the connection.
    ///
    /// - Parameter customFunction: The function to remove.
	public func uninstall(customFunction: SQLiteCustomFunction) async throws {
		self.logger.trace("Removing custom function \(customFunction.name)")
		return try await self.threadPool.runIfActive {
            try customFunction.uninstall(in: self)
		}
	}
}
