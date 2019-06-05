struct SQLiteColumns {
    let storage: [String: Int]
}

public struct SQLiteRow: CustomStringConvertible {
    internal let columns: SQLiteColumns
    internal let data: [SQLiteData]

    public var description: String {
        return self.columns.storage
            .mapValues { self.data[$0] }
            .description
    }

    public func column(_ name: String) -> SQLiteData? {
        guard let offset = self.columns.storage[name] else {
            return nil
        }
        return self.data[offset]
    }
}
