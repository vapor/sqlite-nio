import CSQLite
import NIOCore

#if _pointerBitWidth(_64)
/// We use `Int` on 64-bit systems due to public API breakage concerns.
public typealias SQLiteInt64 = Int // 64-bit platform, Int = 64 bits
#elseif _pointerBitWidth(_32)
public typealias SQLiteInt64 = Int64 // On 32-bit platforms, we want to use 64 bit integers.
#else
/// If you hit errors here, you may simply need to add a new architectural bit size above (e.g. _128)
/// when that exists. Or, if [this proposal for pointerBitWidth](https://forums.swift.org/t/pitch-pointer-bit-width-compile-time-conditional/59572)
/// ever lands in a published Swift version, then the above conditionals may need to be adjusted:
#error("Unsupported integer size")
#endif

/// Encapsulates a single data item provided by or to SQLite.
///
/// SQLite supports four data type "affinities" - INTEGER, REAL, TEXT, and BLOB - plus the `NULL` value, which has no
/// innate affinity.
public enum SQLiteData: Equatable, Encodable, CustomStringConvertible, Sendable {
    /// `INTEGER` affinity, represented in Swift by `Int`.
    case integer(SQLiteInt64)

    /// `REAL` affinity, represented in Swift by `Double`.
    case float(Double)

    /// `TEXT` affinity, represented in Swift by `String`.
    case text(String)

    /// `BLOB` affinity, represented in Swift by `ByteBuffer`.
    case blob(ByteBuffer)

    /// A `NULL` value.
    case null

    /// Returns the integer value of the data, performing conversions where possible.
    ///
    /// If the data has `REAL` or `TEXT` affinity, an attempt is made to interpret the value as an integer. `BLOB`
    /// and `NULL` values always return `nil`.
    public var integer: SQLiteInt64? {
        switch self {
        case .integer(let integer): integer
        case .float(let double): .init(double)
        case .text(let string): .init(string)
        case .blob, .null: nil
        }
    }

    /// Returns the real number value of the data, performing conversions where possible.
    ///
    /// If the data has `INTEGER` or `TEXT` affinity, an attempt is made to interpret the value as a `Double`. `BLOB`
    /// and `NULL` values always return `nil`.
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

    /// Returns the textual value of the data, performing conversions where possible.
    ///
    /// If the data has `INTEGER` or `REAL` affinity, the value is converted to text. `BLOB` and `NULL` values always
    /// return `nil`.
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
    
    /// Returns the boolean value of the data, where possible.
    ///
    /// Returns `true` if the value of ``integer`` is exactly `1`, `false` if the value of ``integer`` is exactly
    /// `0`, or `nil` for all other cases.
    public var bool: Bool? {
       switch self.integer {
            case 1: return true
            case 0: return false
            default: return nil
        }
    }

    /// Returns the data as a blob, if it has `BLOB` affinity.
    ///
    /// `INTEGER`, `REAL`, `TEXT`, and `NULL` values always return `nil`.
	public var blob: ByteBuffer? {
		switch self {
		case .blob(let buffer):
			return buffer
		case .integer, .float, .text, .null:
			return nil
		}
	}

    /// `true` if the value is `NULL`, `false` otherwise.
	public var isNull: Bool {
		switch self {
		case .null:
			return true
		case .integer, .float, .text, .blob:
			return false
		}
	}

    // See `CustomStringConvertible.description`.
    public var description: String {
        switch self {
        case .blob(let data): return "<\(data.readableBytes) bytes>"
        case .float(let float): return float.description
        case .integer(let int): return int.description
        case .null: return "null"
        case .text(let text): return #""\#(text)""#
        }
    }

    // See `Encodable.encode(to:)`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .float(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .blob(let value): try container.encode(Array(value.readableBytesView)) // N.B.: Don't use ByteBuffer's Codable conformance; it encodes as Base64, not raw bytes
        case .null: try container.encodeNil()
        }
    }
}

extension SQLiteData {
    /// Attempt to interpret an `sqlite3_value` as an equivalent ``SQLiteData``.
	init(sqliteValue: OpaquePointer) throws {
		switch sqlite_nio_sqlite3_value_type(sqliteValue) {
		case SQLITE_NULL:
			self = .null
		case SQLITE_INTEGER:
			self = .integer(.init(sqlite_nio_sqlite3_value_int64(sqliteValue)))
		case SQLITE_FLOAT:
			self = .float(sqlite_nio_sqlite3_value_double(sqliteValue))
		case SQLITE_TEXT:
            if let raw = sqlite_nio_sqlite3_value_text(sqliteValue) {
                self = .text(String.init(cString: raw))
            } else {
                self = .text("")
            }
		case SQLITE_BLOB:
			if let bytes = sqlite_nio_sqlite3_value_blob(sqliteValue) {
				let count = Int(sqlite_nio_sqlite3_value_bytes(sqliteValue))
                let buffer = ByteBuffer(bytes: UnsafeRawBufferPointer(start: bytes, count: count))
				self = .blob(buffer) // copy bytes
			} else {
				self = .blob(ByteBuffer())
			}
		case let type:
            throw SQLiteCustomFunctionUnexpectedValueTypeError(type: type)
		}
	}
  
    /// The error thrown by ``init(sqliteValue:)`` if an `sqlite3_value` has an unknown type.
    ///
    /// This should never happen, and this error should not have been made `public`.
    public struct SQLiteCustomFunctionUnexpectedValueTypeError: Error {
        public let type: Int32
    }
}
