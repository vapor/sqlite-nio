import CSQLite

public struct SQLiteError: Error, CustomStringConvertible {
    public let reason: Reason
    public let message: String

    public var description: String {
        return "\(self.reason): \(self.message)"
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
