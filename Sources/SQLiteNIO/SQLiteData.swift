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
       switch self.string {
            case "1": return true
            case "0": return false
            default: return nil
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
