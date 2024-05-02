public struct SQLiteColumn: CustomStringConvertible, Sendable {
    public let name: String
    public let data: SQLiteData

    public var description: String {
        "\(self.name): \(self.data)"
    }
}

public struct SQLiteRow: CustomStringConvertible, Sendable {
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

    public var description: String {
        self.columns.description
    }
}

struct SQLiteColumnOffsets: Sendable {
    let offsets: [(String, Int)]
    let lookupTable: [String: Int]

    init(offsets: [(String, Int)]) {
        self.offsets = offsets
        self.lookupTable = .init(offsets, uniquingKeysWith: { a, _ in a })
    }
}
