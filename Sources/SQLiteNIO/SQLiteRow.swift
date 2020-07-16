public struct SQLiteColumn: CustomStringConvertible {
    public let name: String
    public let data: SQLiteData

    public var description: String {
        "\(self.name): \(self.data)"
    }
}

public struct SQLiteRow {
    let columnOffsets: SQLiteColumnOffsets
    let data: [SQLiteData]

    public var columns: [SQLiteColumn] {
        self.columnOffsets.offsets.map { (name, offset) in
            SQLiteColumn(name: name, data: self.data[offset])
        }
    }

    public func column(_ name: String) -> SQLiteData? {
        guard let offset = self.columnOffsets.lookupTable[name] else {
            return nil
        }
        return self.data[offset]
    }
}

extension SQLiteRow: CustomStringConvertible {
    public var description: String {
        self.columns.description
    }
}

final class SQLiteColumnOffsets {
    let offsets: [(String, Int)]
    let lookupTable: [String: Int]

    init(offsets: [(String, Int)]) {
        self.offsets = offsets
        self.lookupTable = .init(offsets, uniquingKeysWith: { a, b in a })
    }
}
