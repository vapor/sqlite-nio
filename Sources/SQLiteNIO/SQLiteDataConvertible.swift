#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Android)
@preconcurrency import Android
#elseif os(WASI)
import WASILibc
#elseif os(Windows)
import CRT
#endif

import NIOCore
#if canImport(FoundationEssentials)
import NIOFoundationEssentialsCompat
import FoundationEssentials
#else
import NIOFoundationCompat
import Foundation
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
        self = numericCast(value)
    }

    public var sqliteData: SQLiteData? {
        .integer(numericCast(self))
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

extension ByteBuffer: SQLiteDataConvertible {
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

extension Data: SQLiteDataConvertible {
    public init?(sqliteData: SQLiteData) {
        guard case .blob(let value) = sqliteData else {
            return nil
        }
        self = .init(buffer: value, byteTransferStrategy: .copy)
    }

    public var sqliteData: SQLiteData? {
        .blob(.init(data: self))
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
            if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
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
            } else {
                // In practice, this abomination should never actually run, since nobody should actually
                // be running on Catalina or Big Sur. But because Hyrum's Law, just in case they are,
                // this code actually does work. It's ugly, but it works. And deeply sadly, it too is
                // much, much faster than ISO8601DateFormatter... More importantly, it allows us to actually
                // stick to importing FoundationEssentials.
                var stm = tm(
                    tm_sec: 0, tm_min: 0, tm_hour: 0, tm_mday: 0, tm_mon: 0, tm_year: 0,
                    tm_wday: -1, tm_yday: -1, tm_isdst: 0, tm_gmtoff: 0, tm_zone: nil
                )
                guard v.count == 10 || v.count == 19, v.prefix(5).last == "-", v.prefix(8).last == "-",
                      let y = Int32(v.prefix(4)), let n = Int32(v.prefix(7).suffix(2)), let d = Int32(v.prefix(10).suffix(2))
                else { return nil }
                (stm.tm_mday, stm.tm_mon, stm.tm_year) = (d, n - 1, y - 1900)
                if v.count > 10 {
                    guard v.prefix(11).last == " ", v.prefix(14).last == ":", v.prefix(17).last == ":",
                          let h = Int32(v.prefix(13).suffix(2)), let m = Int32(v.prefix(16).suffix(2)), let s = Int32(v.suffix(2))
                    else { return nil }
                    (stm.tm_hour, stm.tm_min, stm.tm_sec) = (h, m, s)
                }
                self = Date(timeIntervalSince1970: TimeInterval(timegm(&stm)))
            }
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
        .float(self.timeIntervalSince1970)
    }
}
