/// Supported SQLite column data types when defining schemas.
public enum SQLiteDataType {
    /// `INTEGER`.
    case integer

    /// `REAL`.
    case real

    /// `TEXT`.
    case text

    /// `BLOB`.
    case blob

    /// `NULL`.
    case null

    /// See `SQLSerializable`.
    public func serialize(_ binds: inout [Encodable]) -> String {
        switch self {
        case .integer: return "INTEGER"
        case .real: return "REAL"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        case .null: return "NULL"
        }
    }
}
