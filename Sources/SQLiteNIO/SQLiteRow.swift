public struct SQLiteColumns {
    public let offsets: [String: Int]
}

public struct SQLiteRow: CustomStringConvertible {
    public let columns: SQLiteColumns
    public let data: [SQLiteData]

    public var description: String {
        return self.columns.offsets
            .mapValues { self.data[$0] }
            .description
    }

    public func column(_ name: String) -> SQLiteData? {
        guard let offset = self.columns.offsets[name] else {
            return nil
        }
        return self.data[offset]
    }
}
