import NIO
import CSQLite

internal struct SQLiteStatement {
    private var handle: OpaquePointer?
    private let connection: SQLiteConnection

    internal init(query: String, on connection: SQLiteConnection) throws {
        self.connection = connection
        let ret = sqlite3_prepare_v2(connection.handle, query, -1, &self.handle, nil)
        guard ret == SQLITE_OK else {
            throw SQLiteError(statusCode: ret, connection: connection)
        }
    }

    internal func bind(_ binds: [SQLiteData]) throws {
        for (i, bind) in binds.enumerated() {
            let i = Int32(i + 1)
            switch bind {
            case .blob(let value):
                let count = Int32(value.readableBytes)
                let ret = value.withUnsafeReadableBytes { pointer in
                    return sqlite3_bind_blob(self.handle, i, pointer.baseAddress, count, SQLITE_TRANSIENT)
                }
                guard ret == SQLITE_OK else {
                    throw SQLiteError(statusCode: ret, connection: connection)
                }
            case .float(let value):
                let ret = sqlite3_bind_double(self.handle, i, value)
                guard ret == SQLITE_OK else {
                    throw SQLiteError(statusCode: ret, connection: connection)
                }
            case .integer(let value):
                let ret = sqlite3_bind_int64(self.handle, i, Int64(value))
                guard ret == SQLITE_OK else {
                    throw SQLiteError(statusCode: ret, connection: connection)
                }
            case .null:
                let ret = sqlite3_bind_null(self.handle, i)
                if ret != SQLITE_OK {
                    throw SQLiteError(statusCode: ret, connection: connection)
                }
            case .text(let value):
                let strlen = Int32(value.utf8.count)
                let ret = sqlite3_bind_text(self.handle, i, value, strlen, SQLITE_TRANSIENT)
                guard ret == SQLITE_OK else {
                    throw SQLiteError(statusCode: ret, connection: connection)
                }
            }
        }
    }

    internal func columns() throws -> SQLiteColumnOffsets {
        var columns: [(String, Int)] = []

        let count = sqlite3_column_count(self.handle)
        columns.reserveCapacity(Int(count))

        // iterate over column count and intialize columns once
        // we will then re-use the columns for each row
        for i in 0..<count {
            try columns.append((self.column(at: i), numericCast(i)))
        }

        return .init(offsets: columns)
    }

    internal func nextRow(for columns: SQLiteColumnOffsets) throws -> SQLiteRow? {
        // step over the query, this will continue to return SQLITE_ROW
        // for as long as there are new rows to be fetched
        let step = sqlite3_step(self.handle)
        switch step {
        case SQLITE_DONE:
            // no results left
            let ret = sqlite3_finalize(self.handle)
            guard ret == SQLITE_OK else {
                throw SQLiteError(statusCode: ret, connection: connection)
            }
            return nil
        case SQLITE_ROW:
            break
        default:
            throw SQLiteError(statusCode: step, connection: connection)
        }


        let count = sqlite3_column_count(self.handle)
        var row: [SQLiteData] = []
        for i in 0..<count {
            try row.append(self.data(at: Int32(i)))
        }
        return SQLiteRow(columnOffsets: columns, data: row)
    }

    // MARK: Private

    private func data(at offset: Int32) throws -> SQLiteData {
        let type = try dataType(at: offset)
        switch type {
        case .integer:
            let val = sqlite3_column_int64(self.handle, offset)
            let integer = Int(val)
            return .integer(integer)
        case .real:
            let val = sqlite3_column_double(self.handle, offset)
            let double = Double(val)
            return .float(double)
        case .text:
            guard let val = sqlite3_column_text(self.handle, offset) else {
                throw SQLiteError(reason: .error, message: "Unexpected nil column text")
            }
            let string = String(cString: val)
            return .text(string)
        case .blob:
            let length = Int(sqlite3_column_bytes(self.handle, offset))
            var buffer = ByteBufferAllocator().buffer(capacity: length)
            if let blobPointer = sqlite3_column_blob(self.handle, offset) {
                buffer.writeBytes(UnsafeBufferPointer(
                    start: blobPointer.assumingMemoryBound(to: UInt8.self),
                    count: length
                ))
            }
            return .blob(buffer)
        case .null: return .null
        }
    }

    private func dataType(at offset: Int32) throws -> SQLiteDataType {
        switch sqlite3_column_type(self.handle, offset) {
        case SQLITE_INTEGER: return .integer
        case SQLITE_FLOAT: return .real
        case SQLITE_TEXT: return .text
        case SQLITE_BLOB: return .blob
        case SQLITE_NULL: return .null
        default: throw SQLiteError(reason: .error, message: "Unexpected column type.")
        }
    }

    private func column(at offset: Int32) throws -> String {
        guard let cName = sqlite3_column_name(self.handle, offset) else {
            throw SQLiteError(reason: .error, message: "Unexpected nil column name")
        }
        return String(cString: cName)
    }
}

internal let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
