import CSQLite
import NIO

/// Supported SQLite data types.
public enum SQLiteData: Equatable, Encodable, CustomStringConvertible {
    /// `Int`.
    case integer(Int)

    /// `Double`.
    case float(Double)

    /// `String`.
    case text(String)

    /// `ByteBuffer`.
    case blob(ByteBuffer)

    /// `NULL`.
    case null

    public var integer: Int? {
        switch self {
        case .integer(let integer):
            return integer
        case .float(let double):
            return Int(double)
        case .text(let string):
            return Int(string)
        case .blob, .null:
            return nil
        }
    }

    public var double: Double? {
        switch self {
        case .integer(let integer):
            return Double(integer)
        case .float(let double):
            return double
        case .text(let string):
            return Double(string)
        case .blob, .null:
            return nil
        }
    }

    public var string: String? {
        switch self {
        case .integer(let integer):
            return String(integer)
        case .float(let double):
            return String(double)
        case .text(let string):
            return string
        case .blob, .null:
            return nil
        }
    }
    
    public var bool: Bool? {
       switch self.integer {
            case 1: return true
            case 0: return false
            default: return nil
        }
    }

	public var blob: ByteBuffer? {
		switch self {
		case .blob(let buffer):
			return buffer
		case .integer, .float, .text, .null:
			return nil
		}
	}

	public var isNull: Bool {
		switch self {
		case .null:
			return true
		case .integer, .float, .text, .blob:
			return false
		}
	}

    /// Description of data
    public var description: String {
        switch self {
        case .blob(let data): return "<\(data.readableBytes) bytes>"
        case .float(let float): return float.description
        case .integer(let int): return int.description
        case .null: return "null"
        case .text(let text): return "\"" + text + "\""
        }
    }

    /// See `Encodable`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .float(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .blob(var value):
            let bytes = value.readBytes(length: value.readableBytes) ?? []
            try container.encode(bytes)
        case .null: try container.encodeNil()
        }
    }
}

extension SQLiteData {
	init(sqliteValue: OpaquePointer) {
		switch sqlite3_value_type(sqliteValue) {
		case SQLITE_NULL:
			self = .null
		case SQLITE_INTEGER:
			self = .integer(Int(sqlite3_value_int64(sqliteValue)))
		case SQLITE_FLOAT:
			self = .float(sqlite3_value_double(sqliteValue))
		case SQLITE_TEXT:
			self = .text(String(cString: sqlite3_value_text(sqliteValue)!))
		case SQLITE_BLOB:
			if let bytes = sqlite3_value_blob(sqliteValue) {
				let count = Int(sqlite3_value_bytes(sqliteValue))
				var buffer = ByteBufferAllocator().buffer(capacity: count)
				buffer.writeBytes(UnsafeBufferPointer(
					start: bytes.assumingMemoryBound(to: UInt8.self),
					count: count
				))

				self = .blob(buffer) // copy bytes
			} else {
				self = .blob(ByteBuffer())
			}
		case let type:
			// Assume a bug: there is no point throwing any error.
			fatalError("Unexpected SQLite value type: \(type)")
		}
	}
}
