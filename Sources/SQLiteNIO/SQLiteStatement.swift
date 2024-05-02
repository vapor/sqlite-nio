import NIOCore
import CSQLite

struct SQLiteStatement {
    private var handle: OpaquePointer?
    private let connection: SQLiteConnection

    init(query: String, on connection: SQLiteConnection) throws {
        self.connection = connection
        
        let ret = sqlite_nio_sqlite3_prepare_v3(
            connection.handle.raw,
            query,
            -1,
            0, // TODO: Look into figuring out when passing SQLITE_PREPARE_PERSISTENT would be apropos.
            &self.handle,
            nil
        )
        // Can't use self.check() here, there's nohting to finalize yet on failure.
        guard ret == SQLITE_OK else {
            throw SQLiteError(statusCode: ret, connection: connection)
        }
    }
    
    private mutating func check(_ ret: Int32) throws {
        // We check it this way so that `SQLITE_DONE` causes a finalize without throwing an error.
        if ret != SQLITE_OK, let handle = self.handle {
            sqlite_nio_sqlite3_finalize(handle)
            self.handle = nil
        }
        
        guard ret == SQLITE_OK || ret == SQLITE_DONE || ret == SQLITE_ROW else {
            throw SQLiteError(statusCode: ret, connection: self.connection)
        }
    }
    
    mutating func bind(_ binds: [SQLiteData]) throws {
        for (i, bind) in binds.enumerated() {
            let i = Int32(i + 1), ret: Int32
            
            switch bind {
            case .blob(let value):
                ret = value.withUnsafeReadableBytes {
                    sqlite_nio_sqlite3_bind_blob64(self.handle, i, $0.baseAddress, UInt64($0.count), SQLITE_TRANSIENT)
                }
            case .float(let value):
                ret = sqlite_nio_sqlite3_bind_double(self.handle, i, value)
            case .integer(let value):
                ret = sqlite_nio_sqlite3_bind_int64(self.handle, i, Int64(value))
            case .null:
                ret = sqlite_nio_sqlite3_bind_null(self.handle, i)
            case .text(let value):
                ret = sqlite_nio_sqlite3_bind_text64(self.handle, i, value, UInt64(value.utf8.count), SQLITE_TRANSIENT, UInt8(SQLITE_UTF8))
            }
            try self.check(ret)
        }
    }

    mutating func columns() throws -> SQLiteColumnOffsets {
        var columns: [(String, Int)] = []

        let count = sqlite_nio_sqlite3_column_count(self.handle)
        columns.reserveCapacity(Int(count))

        // iterate over column count and intialize columns once
        // we will then re-use the columns for each row
        for i in 0 ..< count {
            try columns.append((self.column(at: i), numericCast(i)))
        }

        return .init(offsets: columns)
    }

    mutating func nextRow(for columns: SQLiteColumnOffsets) throws -> SQLiteRow? {
    /// Step over the query. This will continue to return `SQLITE_ROW` for as long as there are new rows to be fetched.
        switch sqlite_nio_sqlite3_step(self.handle) {
        case SQLITE_ROW:
            // Row returned.
            break
        case let ret:
            // No results left, or error.
            // This check is explicitly guaranteed to finalize the statement if the code is SQLITE_DONE.
            try self.check(ret)
            return nil
        }

        return SQLiteRow(columnOffsets: columns, data: try (0 ..< columns.offsets.count).map { try self.data(at: Int32($0)) })
    }

    // MARK: Private

    private func data(at offset: Int32) throws -> SQLiteData {
        switch sqlite_nio_sqlite3_column_type(self.handle, offset) {
        case SQLITE_INTEGER:
            return .integer(Int(sqlite_nio_sqlite3_column_int64(self.handle, offset)))
        case SQLITE_FLOAT:
            return .float(Double(sqlite_nio_sqlite3_column_double(self.handle, offset)))
        case SQLITE_TEXT:
            guard let val = sqlite_nio_sqlite3_column_text(self.handle, offset) else {
                throw SQLiteError(reason: .error, message: "Unexpected nil column text")
            }
            return .text(.init(cString: val))
        case SQLITE_BLOB:
            let length = Int(sqlite_nio_sqlite3_column_bytes(self.handle, offset))
            var buffer = ByteBufferAllocator().buffer(capacity: length)
            
            if let blobPointer = sqlite_nio_sqlite3_column_blob(self.handle, offset) {
                buffer.writeBytes(UnsafeRawBufferPointer(start: blobPointer, count: length))
            }
            return .blob(buffer)
        case SQLITE_NULL:
            return .null
        default:
            throw SQLiteError(reason: .error, message: "Unexpected column type.")
        }
    }

    private func column(at offset: Int32) throws -> String {
        guard let cName = sqlite_nio_sqlite3_column_name(self.handle, offset) else {
            throw SQLiteError(reason: .error, message: "Unexpectedly nil column name at offset \(offset)")
        }
        return String(cString: cName)
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

