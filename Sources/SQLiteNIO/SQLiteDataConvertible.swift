import NIO
import Foundation

public protocol SQLiteDataConvertible {
    init?(sqliteData: SQLiteData)
    var sqliteData: SQLiteData? { get }
}

extension String: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .text(let value) = sqliteData else {
            return nil
        }
        self = value
    }

    public var sqliteData: SQLiteData? {
        return .text(self)
    }
}

extension FixedWidthInteger {
    public init?(sqliteData: SQLiteData) {
        guard case .integer(let value) = sqliteData else {
            return nil
        }
        self = numericCast(value)
    }

    public var sqliteData: SQLiteData? {
        return .integer(numericCast(self))
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
        guard case .float(let value) = sqliteData else {
            return nil
        }
        self = value
    }

    public var sqliteData: SQLiteData? {
        return .float(self)
    }
}

extension Float: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .float(let value) = sqliteData else {
            return nil
        }
        self = Float(value)
    }

    public var sqliteData: SQLiteData? {
        return .float(Double(self))
    }
}

extension ByteBuffer: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .blob(let value) = sqliteData else {
            return nil
        }
        self = value
    }

    public var sqliteData: SQLiteData? {
        return .blob(self)
    }
}

extension Data: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .blob(var value) = sqliteData else {
            return nil
        }
        guard let data = value.readBytes(length: value.readableBytes) else {
            return nil
        }
        self = Data(data)
    }

    public var sqliteData: SQLiteData? {
        var buffer = ByteBufferAllocator().buffer(capacity: self.count)
        buffer.writeBytes(self)
        return .blob(buffer)
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
        return .integer(self ? 1 : 0)
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
            guard let d = dateTimeFormatter.date(from: v) ?? dateFormatter.date(from: v) else {
                return nil
            }
            self = d
            return
        default:
            return nil
        }
        // Round to microseconds to avoid nanosecond precision error causing Dates to fail equality
        let valueSinceReferenceDate = value - Date.timeIntervalBetween1970AndReferenceDate
        let secondsSinceReference = round(valueSinceReferenceDate * 1e6) / 1e6
        self.init(timeIntervalSinceReferenceDate: secondsSinceReference)
    }

    public var sqliteData: SQLiteData? {
        return .float(timeIntervalSince1970)
    }
}

/// Matches dates from the `datetime()` function
let dateTimeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withFullDate,
        .withDashSeparatorInDate,
        .withSpaceBetweenDateAndTime,
        .withTime,
        .withColonSeparatorInTime
    ]
    return formatter
}()

/// Matches dates from the `date()` function
let dateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withFullDate,
        .withDashSeparatorInDate
    ]
    return formatter
}()
