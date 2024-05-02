/// Supported SQLite column data types when defining schemas.
@available(*, deprecated, message: "This type is unused.")
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

    public func serialize(_ binds: inout [any Encodable]) -> String {
        switch self {
        case .integer: return "INTEGER"
        case .real: return "REAL"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        case .null: return "NULL"
        }
    }
}
