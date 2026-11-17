#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

public protocol SQLiteDataConvertible {
    init?(sqliteData: SQLiteData)
    var sqliteData: SQLiteData? { get }
}

extension String: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard let value = sqliteData.string else {
            return nil
        }
        self = value
    }

    public var sqliteData: SQLiteData? {
        .text(self)
    }
}

extension FixedWidthInteger {
    public init?(sqliteData: SQLiteData) {
        // Don't use `SQLiteData.integer`, we don't want to attempt converting strings here.
        guard case .integer(let value) = sqliteData else {
            return nil
        }
        self.init(exactly: value)
    }

    public var sqliteData: SQLiteData? {
        SQLiteInt64(exactly: self).map { .integer($0) }
    }
}

extension Int: SQLiteDataConvertible { }
extension Int8: SQLiteDataConvertible { }
extension Int16: SQLiteDataConvertible { }
extension Int32: SQLiteDataConvertible { }
extension Int64: SQLiteDataConvertible { }
extension UInt: SQLiteDataConvertible { }
extension UInt8: SQLiteDataConvertible { }
extension UInt16: SQLiteDataConvertible { }
extension UInt32: SQLiteDataConvertible { }
extension UInt64: SQLiteDataConvertible { }

extension Double: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        // Don't use `SQLiteData.double`, we don't want to attempt converting strings here.
        switch sqliteData {
        case .integer(let int): self.init(int)
        case .float(let double): self = double
        case .text(_), .blob(_), .null: return nil
        }
    }

    public var sqliteData: SQLiteData? {
        .float(self)
    }
}

extension Float: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        switch sqliteData {
        case .integer(let int): self.init(int)
        case .float(let double): self.init(double)
        case .text(_), .blob(_), .null: return nil
        }
    }

    public var sqliteData: SQLiteData? {
        .float(Double(self))
    }
}

extension Data: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .blob(let value) = sqliteData else {
            return nil
        }
        self = value
    }

    public var sqliteData: SQLiteData? {
        .blob(self)
    }
}

extension Bool: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard let bool = sqliteData.bool else {
            return nil
        }
        self = bool
    }

    public var sqliteData: SQLiteData? {
        .integer(self ? 1 : 0)
    }
}

extension Date: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        let value: Double
        // We have to retrieve floats and integers, because apparently SQLite
        // returns an Integer if the value does not have floating point value.
        switch sqliteData {
        case .float(let v):
            value = v
        case .integer(let v):
            value = Double(v)
        case .text(let v):
            // N.B. ISO8601FormatStyle is MUCH MUCH faster than DateFormatter
            guard let d =
                // Parse as strict ISO8601
                (try? Date(v, strategy: .iso8601)) ??
                // Parse as strict ISO8601 with ' ' instead of 'T'
                (try? Date(v, strategy: .iso8601.dateTimeSeparator(.space))) ??
                // Parse as ISO8601 with ' ' instead of 'T' and no timezone.
                (try? Date(v, strategy: .iso8601.dateTimeSeparator(.space).year().month().day().time(includingFractionalSeconds: false))) ??
                // Parse as ISO8601 with date but no time.
                (try? Date(v, strategy: .iso8601.year().month().day()))
            else {
                return nil
            }
            self = d
            return
        default:
            return nil
        }
        // Round to microseconds to avoid nanosecond precision error causing Dates to fail equality
        let valueSinceReferenceDate = value - Date.timeIntervalBetween1970AndReferenceDate
        let secondsSinceReference = (valueSinceReferenceDate * 1e6).rounded() / 1e6
        self.init(timeIntervalSinceReferenceDate: secondsSinceReference)
    }

    public var sqliteData: SQLiteData? {
        .float(self.timeIntervalSince1970)
    }
}
