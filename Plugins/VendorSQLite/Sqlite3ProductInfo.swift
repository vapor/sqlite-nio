#if canImport(Darwin)

import struct Foundation.URL

struct Sqlite3ProductInfo {
    let version: SemanticVersion
    let downloadURL: URL
    let filename: String
    let sizeInBytes: Int
    let sha3Hash: String

    init(from csvRow: String) throws {
        let columns = csvRow.split(separator: ",", omittingEmptySubsequences: false)
        
        guard columns.count == 5, columns[0] == "PRODUCT" else {
            throw VendoringError("Invalid product info, expecting 5 columns starting with PRODUCT in: \(csvRow)")
        }
        guard let version = SemanticVersion(from: columns[1]) else {
            throw VendoringError("Invalid product version \(columns[1])")
        }
        guard let downloadURL = URL(string: "\(columns[2])", relativeTo: VendorSQLite.sqliteURL) else {
            throw VendoringError("Invalid product relative URL \(columns[2])")
        }
        guard let sizeInBytes = Int(columns[3]) else {
            throw VendoringError("Invalid product archive size \(columns[3])")
        }
        guard columns[4].count == 64, columns[4].allSatisfy(\.isHexDigit) else {
            throw VendoringError("Invalid product SHA-3 hash")
        }

        self.version = version
        self.downloadURL = downloadURL
        self.filename = downloadURL.lastPathComponent
        self.sizeInBytes = sizeInBytes
        self.sha3Hash = String(columns[4])
    }
}

#endif
