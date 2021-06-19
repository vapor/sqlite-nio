import CSQLite
import Foundation

public struct SQLiteError: Error, CustomStringConvertible, LocalizedError {
    public let reason: Reason
    public let message: String

    public var description: String {
        return "\(self.reason): \(self.message)"
    }

    public var errorDescription: String? {
        return self.description
    }

    internal init(reason: Reason, message: String) {
        self.reason = reason
        self.message = message
    }

    internal init(statusCode: Int32, connection: SQLiteConnection) {
        self.reason = .init(statusCode: statusCode)
        self.message = connection.errorMessage ?? "Unknown"
    }

    public enum Reason {
        case error
        case intern
        case permission
        case abort
        case busy
        case locked
        case noMemory
        case readOnly
        case interrupt
        case ioError
        case corrupt
        case notFound
        case full
        case cantOpen
        case proto
        case empty
        case schema
        case tooBig
        case constraint
        case mismatch
        case misuse
        case noLFS
        case auth
        case format
        case range
        case notADatabase
        case notice
        case warning
        case row
        case done
        case connection
        case close
        case prepare
        case bind
        case execute

			var statusCode: Int32 {
				switch self {
				case .error:
					return SQLITE_ERROR
				case .intern:
					return SQLITE_INTERNAL
				case .abort:
					return SQLITE_ABORT
				case .permission:
					return SQLITE_PERM
				case .busy:
					return SQLITE_BUSY
				case .locked:
					return SQLITE_LOCKED
				case .noMemory:
					return SQLITE_NOMEM
				case .readOnly:
					return SQLITE_READONLY
				case .interrupt:
					return SQLITE_INTERRUPT
				case .ioError:
					return SQLITE_IOERR
				case .corrupt:
					return SQLITE_CORRUPT
				case .notFound:
					return SQLITE_NOTFOUND
				case .full:
					return SQLITE_FULL
				case .cantOpen:
					return SQLITE_CANTOPEN
				case .proto:
					return SQLITE_PROTOCOL
				case .empty:
					return SQLITE_EMPTY
				case .schema:
					return SQLITE_SCHEMA
				case .tooBig:
					return SQLITE_TOOBIG
				case .constraint:
					return SQLITE_CONSTRAINT
				case .mismatch:
					return SQLITE_MISMATCH
				case .misuse:
					return SQLITE_MISUSE
				case .noLFS:
					return SQLITE_NOLFS
				case .auth:
					return SQLITE_AUTH
				case .format:
					return SQLITE_FORMAT
				case .range:
					return SQLITE_RANGE
				case .notADatabase:
					return SQLITE_NOTADB
				case .notice:
					return SQLITE_NOTICE
				case .warning:
					return SQLITE_WARNING
				case .row:
					return SQLITE_ROW
				case .done:
					return SQLITE_DONE
				case .connection, .close, .prepare, .bind, .execute:
					return -1
				}
			}

        internal init(statusCode: Int32) {
            switch statusCode {
            case SQLITE_ERROR:
                self = .error
            case SQLITE_INTERNAL:
                self = .intern
            case SQLITE_PERM:
                self = .permission
            case SQLITE_ABORT:
                self = .abort
            case SQLITE_BUSY:
                self = .busy
            case SQLITE_LOCKED:
                self = .locked
            case SQLITE_NOMEM:
                self = .noMemory
            case SQLITE_READONLY:
                self = .readOnly
            case SQLITE_INTERRUPT:
                self = .interrupt
            case SQLITE_IOERR:
                self = .ioError
            case SQLITE_CORRUPT:
                self = .corrupt
            case SQLITE_NOTFOUND:
                self = .notFound
            case SQLITE_FULL:
                self = .full
            case SQLITE_CANTOPEN:
                self = .cantOpen
            case SQLITE_PROTOCOL:
                self = .proto
            case SQLITE_EMPTY:
                self = .empty
            case SQLITE_SCHEMA:
                self = .schema
            case SQLITE_TOOBIG:
                self = .tooBig
            case SQLITE_CONSTRAINT:
                self = .constraint
            case SQLITE_MISMATCH:
                self = .mismatch
            case SQLITE_MISUSE:
                self = .misuse
            case SQLITE_NOLFS:
                self = .noLFS
            case SQLITE_AUTH:
                self = .auth
            case SQLITE_FORMAT:
                self = .format
            case SQLITE_RANGE:
                self = .range
            case SQLITE_NOTADB:
                self = .notADatabase
            case SQLITE_NOTICE:
                self = .notice
            case SQLITE_WARNING:
                self = .warning
            case SQLITE_ROW:
                self = .row
            case SQLITE_DONE:
                self = .done
            default:
                self = .error
            }
        }
    }
}
