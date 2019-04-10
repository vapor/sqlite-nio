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

    /// Description of data
    public var description: String {
        switch self {
        case .blob(let data): return data.debugDescription
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
