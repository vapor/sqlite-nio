#if SQLCipher
import CSQLCipher
#else
import CSQLite
#endif
import Foundation

public struct SQLiteError: Error, CustomStringConvertible, LocalizedError {
    public let reason: Reason
    public let message: String
    
    public var description: String {
        "\(self.reason): \(self.message)"
    }
    
    public var errorDescription: String? {
        self.description
    }
    
    init(reason: Reason, message: String) {
        self.reason = reason
        self.message = message
    }
    
    init(statusCode: Int32, connection: SQLiteConnection) {
        self.reason = .init(statusCode: statusCode)
        self.message = connection.errorMessage ?? "Unknown"
    }
    
    public enum Reason: Sendable {
        // SQLite "basic" errors
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
        
        // SQLite "extended" result codes
        case errorMissingCollatingSequence, errorRetry, errorMissingSnapshot
        case abortByRollback
        case busyInRecovery, busyInSnapshot, busyTimeout
        case lockedBySharedCache, lockedVirtualTable
        case readonlyInRecovery, readonlyCantLock, readonlyInRollback, readonlyBackingMoved, readonlyDirectory
        case ioErrorFailedRead, ioErrorIncompleteRead, ioErrorFailedWrite, ioErrorFailedSync, ioErrorFailedDirSync,
             ioErrorFailedTruncate, ioErrorFailedStat, ioErrorFailedUnlock, ioErrorFailedReadLock,
             ioErrorFailedDelete, ioErrorNoMemory, ioErrorFailedAccess, ioErrorFailedLockCheck,
             ioErrorFailedAdvisoryLock, ioErrorFailedClose, ioErrorFailedSharedMemOpen, ioErrorFailedSharedMemSize,
             ioErrorFailedSharedMemMap, ioErrorFailedDeleteNonexistent, ioErrorFailedMemoryMap, ioErrorCantFindTempdir,
             ioErrorCygwinPath, ioErrorBadDataChecksum, ioErrorCorruptedFilesystem
        case corruptVirtualTable, corruptSequenceSchema, corruptIndex
        case cantOpenDirectory, cantOpenInvalidPath, cantOpenCygwinPath, cantOpenUnfollowedSymlink
        case constraintCheckFailed, constraintCommitHookFailed, constraintForeignKeyFailed,
             constraintUserFunctionFailed, constraintNotNullFailed, constraintPrimaryKeyFailed,
             constraintTriggerFailed, constraintUniqueFailed, constraintVirtualTableFailed,
             constraintUniqueRowIDFailed, constraintUpdateTriggerDeletedRow, constraintStrictDataTypeFailed
        case authUnauthorizedUser
        case noticeRecoverWAL, noticeRecoverRollback
        case warningAutoindex
        
        
        // The following five "reasons" are holdovers from early development; they have never used by the package
        // are do not correspond to SQLite error codes. They should be considered deprecated, but are not marked
        // as such as there would be no way to avoid the warning for users who switch over this enum.
        case connection
        case close
        case prepare
        case bind
        case execute
        
        var statusCode: Int32 {
            switch self {
            case .error: return SQLITE_ERROR
            case .intern: return SQLITE_INTERNAL
            case .abort: return SQLITE_ABORT
            case .permission: return SQLITE_PERM
            case .busy: return SQLITE_BUSY
            case .locked: return SQLITE_LOCKED
            case .noMemory: return SQLITE_NOMEM
            case .readOnly: return SQLITE_READONLY
            case .interrupt: return SQLITE_INTERRUPT
            case .ioError: return SQLITE_IOERR
            case .corrupt: return SQLITE_CORRUPT
            case .notFound: return SQLITE_NOTFOUND
            case .full: return SQLITE_FULL
            case .cantOpen: return SQLITE_CANTOPEN
            case .proto: return SQLITE_PROTOCOL
            case .empty: return SQLITE_EMPTY
            case .schema: return SQLITE_SCHEMA
            case .tooBig: return SQLITE_TOOBIG
            case .constraint: return SQLITE_CONSTRAINT
            case .mismatch: return SQLITE_MISMATCH
            case .misuse: return SQLITE_MISUSE
            case .noLFS: return SQLITE_NOLFS
            case .auth: return SQLITE_AUTH
            case .format: return SQLITE_FORMAT
            case .range: return SQLITE_RANGE
            case .notADatabase: return SQLITE_NOTADB
            case .notice: return SQLITE_NOTICE
            case .warning: return SQLITE_WARNING
            case .row: return SQLITE_ROW
            case .done: return SQLITE_DONE
            case .errorMissingCollatingSequence: return SQLITE_ERROR_MISSING_COLLSEQ
            case .errorRetry: return SQLITE_ERROR_RETRY
            case .errorMissingSnapshot: return SQLITE_ERROR_SNAPSHOT
            case .abortByRollback: return SQLITE_ABORT_ROLLBACK
            case .busyInRecovery: return SQLITE_BUSY_RECOVERY
            case .busyInSnapshot: return SQLITE_BUSY_SNAPSHOT
            case .busyTimeout: return SQLITE_BUSY_TIMEOUT
            case .lockedBySharedCache: return SQLITE_LOCKED_SHAREDCACHE
            case .lockedVirtualTable: return SQLITE_LOCKED_VTAB
            case .readonlyInRecovery: return SQLITE_READONLY_RECOVERY
            case .readonlyCantLock: return SQLITE_READONLY_CANTLOCK
            case .readonlyInRollback: return SQLITE_READONLY_ROLLBACK
            case .readonlyBackingMoved: return SQLITE_READONLY_DBMOVED
            case .readonlyDirectory: return SQLITE_READONLY_DIRECTORY
            case .ioErrorFailedRead: return SQLITE_IOERR_READ
            case .ioErrorIncompleteRead: return SQLITE_IOERR_SHORT_READ
            case .ioErrorFailedWrite: return SQLITE_IOERR_WRITE
            case .ioErrorFailedSync: return SQLITE_IOERR_FSYNC
            case .ioErrorFailedDirSync: return SQLITE_IOERR_DIR_FSYNC
            case .ioErrorFailedTruncate: return SQLITE_IOERR_TRUNCATE
            case .ioErrorFailedStat: return SQLITE_IOERR_FSTAT
            case .ioErrorFailedUnlock: return SQLITE_IOERR_UNLOCK
            case .ioErrorFailedReadLock: return SQLITE_IOERR_RDLOCK
            case .ioErrorFailedDelete: return SQLITE_IOERR_DELETE
            case .ioErrorNoMemory: return SQLITE_IOERR_NOMEM
            case .ioErrorFailedAccess: return SQLITE_IOERR_ACCESS
            case .ioErrorFailedLockCheck: return SQLITE_IOERR_LOCK
            case .ioErrorFailedAdvisoryLock: return SQLITE_IOERR_CHECKRESERVEDLOCK
            case .ioErrorFailedClose: return SQLITE_IOERR_CLOSE
            case .ioErrorFailedSharedMemOpen: return SQLITE_IOERR_SHMOPEN
            case .ioErrorFailedSharedMemSize: return SQLITE_IOERR_SHMSIZE
            case .ioErrorFailedSharedMemMap: return SQLITE_IOERR_SHMMAP
            case .ioErrorFailedDeleteNonexistent: return SQLITE_IOERR_DELETE_NOENT
            case .ioErrorFailedMemoryMap: return SQLITE_IOERR_MMAP
            case .ioErrorCantFindTempdir: return SQLITE_IOERR_GETTEMPPATH
            case .ioErrorCygwinPath: return SQLITE_IOERR_CONVPATH
            case .ioErrorBadDataChecksum: return SQLITE_IOERR_DATA
            case .ioErrorCorruptedFilesystem: return SQLITE_IOERR_CORRUPTFS
            case .corruptVirtualTable: return SQLITE_CORRUPT_VTAB
            case .corruptSequenceSchema: return SQLITE_CORRUPT_SEQUENCE
            case .corruptIndex: return SQLITE_CORRUPT_INDEX
            case .cantOpenDirectory: return SQLITE_CANTOPEN_ISDIR
            case .cantOpenInvalidPath: return SQLITE_CANTOPEN_FULLPATH
            case .cantOpenCygwinPath: return SQLITE_CANTOPEN_CONVPATH
            case .cantOpenUnfollowedSymlink: return SQLITE_CANTOPEN_SYMLINK
            case .constraintCheckFailed: return SQLITE_CONSTRAINT_CHECK
            case .constraintCommitHookFailed: return SQLITE_CONSTRAINT_COMMITHOOK
            case .constraintForeignKeyFailed: return SQLITE_CONSTRAINT_FOREIGNKEY
            case .constraintUserFunctionFailed: return SQLITE_CONSTRAINT_FUNCTION
            case .constraintNotNullFailed: return SQLITE_CONSTRAINT_NOTNULL
            case .constraintPrimaryKeyFailed: return SQLITE_CONSTRAINT_PRIMARYKEY
            case .constraintTriggerFailed: return SQLITE_CONSTRAINT_TRIGGER
            case .constraintUniqueFailed: return SQLITE_CONSTRAINT_UNIQUE
            case .constraintVirtualTableFailed: return SQLITE_CONSTRAINT_VTAB
            case .constraintUniqueRowIDFailed: return SQLITE_CONSTRAINT_ROWID
            case .constraintUpdateTriggerDeletedRow: return SQLITE_CONSTRAINT_PINNED
            case .constraintStrictDataTypeFailed: return SQLITE_CONSTRAINT_DATATYPE
            case .authUnauthorizedUser: return SQLITE_AUTH_USER
            case .noticeRecoverWAL: return SQLITE_NOTICE_RECOVER_WAL
            case .noticeRecoverRollback: return SQLITE_NOTICE_RECOVER_ROLLBACK
            case .warningAutoindex: return SQLITE_WARNING_AUTOINDEX
            
            case .connection, .close, .prepare, .bind, .execute: return -1
            }
        }
        
        init(statusCode: Int32) {
            switch statusCode {
            case SQLITE_ERROR: self = .error
            case SQLITE_INTERNAL: self = .intern
            case SQLITE_PERM: self = .permission
            case SQLITE_ABORT: self = .abort
            case SQLITE_BUSY: self = .busy
            case SQLITE_LOCKED: self = .locked
            case SQLITE_NOMEM: self = .noMemory
            case SQLITE_READONLY: self = .readOnly
            case SQLITE_INTERRUPT: self = .interrupt
            case SQLITE_IOERR: self = .ioError
            case SQLITE_CORRUPT: self = .corrupt
            case SQLITE_NOTFOUND: self = .notFound
            case SQLITE_FULL: self = .full
            case SQLITE_CANTOPEN: self = .cantOpen
            case SQLITE_PROTOCOL: self = .proto
            case SQLITE_EMPTY: self = .empty
            case SQLITE_SCHEMA: self = .schema
            case SQLITE_TOOBIG: self = .tooBig
            case SQLITE_CONSTRAINT: self = .constraint
            case SQLITE_MISMATCH: self = .mismatch
            case SQLITE_MISUSE: self = .misuse
            case SQLITE_NOLFS: self = .noLFS
            case SQLITE_AUTH: self = .auth
            case SQLITE_FORMAT: self = .format
            case SQLITE_RANGE: self = .range
            case SQLITE_NOTADB: self = .notADatabase
            case SQLITE_NOTICE: self = .notice
            case SQLITE_WARNING: self = .warning
            case SQLITE_ROW: self = .row
            case SQLITE_DONE: self = .done

            case SQLITE_ERROR_MISSING_COLLSEQ: self = .errorMissingCollatingSequence
            case SQLITE_ERROR_RETRY: self = .errorRetry
            case SQLITE_ERROR_SNAPSHOT: self = .errorMissingSnapshot
            case SQLITE_ABORT_ROLLBACK: self = .abortByRollback
            case SQLITE_BUSY_RECOVERY: self = .busyInRecovery
            case SQLITE_BUSY_SNAPSHOT: self = .busyInSnapshot
            case SQLITE_BUSY_TIMEOUT: self = .busyTimeout
            case SQLITE_LOCKED_SHAREDCACHE: self = .lockedBySharedCache
            case SQLITE_LOCKED_VTAB: self = .lockedVirtualTable
            case SQLITE_READONLY_RECOVERY: self = .readonlyInRecovery
            case SQLITE_READONLY_CANTLOCK: self = .readonlyCantLock
            case SQLITE_READONLY_ROLLBACK: self = .readonlyInRollback
            case SQLITE_READONLY_DBMOVED: self = .readonlyBackingMoved
            case SQLITE_READONLY_DIRECTORY: self = .readonlyDirectory
            case SQLITE_IOERR_READ: self = .ioErrorFailedRead
            case SQLITE_IOERR_SHORT_READ: self = .ioErrorIncompleteRead
            case SQLITE_IOERR_WRITE: self = .ioErrorFailedWrite
            case SQLITE_IOERR_FSYNC: self = .ioErrorFailedSync
            case SQLITE_IOERR_DIR_FSYNC: self = .ioErrorFailedDirSync
            case SQLITE_IOERR_TRUNCATE: self = .ioErrorFailedTruncate
            case SQLITE_IOERR_FSTAT: self = .ioErrorFailedStat
            case SQLITE_IOERR_UNLOCK: self = .ioErrorFailedUnlock
            case SQLITE_IOERR_RDLOCK: self = .ioErrorFailedReadLock
            case SQLITE_IOERR_DELETE: self = .ioErrorFailedDelete
            case SQLITE_IOERR_NOMEM: self = .ioErrorNoMemory
            case SQLITE_IOERR_ACCESS: self = .ioErrorFailedAccess
            case SQLITE_IOERR_LOCK: self = .ioErrorFailedLockCheck
            case SQLITE_IOERR_CHECKRESERVEDLOCK: self = .ioErrorFailedAdvisoryLock
            case SQLITE_IOERR_CLOSE: self = .ioErrorFailedClose
            case SQLITE_IOERR_SHMOPEN: self = .ioErrorFailedSharedMemOpen
            case SQLITE_IOERR_SHMSIZE: self = .ioErrorFailedSharedMemSize
            case SQLITE_IOERR_SHMMAP: self = .ioErrorFailedSharedMemMap
            case SQLITE_IOERR_DELETE_NOENT: self = .ioErrorFailedDeleteNonexistent
            case SQLITE_IOERR_MMAP: self = .ioErrorFailedMemoryMap
            case SQLITE_IOERR_GETTEMPPATH: self = .ioErrorCantFindTempdir
            case SQLITE_IOERR_CONVPATH: self = .ioErrorCygwinPath
            case SQLITE_IOERR_DATA: self = .ioErrorBadDataChecksum
            case SQLITE_IOERR_CORRUPTFS: self = .ioErrorCorruptedFilesystem
            case SQLITE_CORRUPT_VTAB: self = .corruptVirtualTable
            case SQLITE_CORRUPT_SEQUENCE: self = .corruptSequenceSchema
            case SQLITE_CORRUPT_INDEX: self = .corruptIndex
            case SQLITE_CANTOPEN_ISDIR: self = .cantOpenDirectory
            case SQLITE_CANTOPEN_FULLPATH: self = .cantOpenInvalidPath
            case SQLITE_CANTOPEN_CONVPATH: self = .cantOpenCygwinPath
            case SQLITE_CANTOPEN_SYMLINK: self = .cantOpenUnfollowedSymlink
            case SQLITE_CONSTRAINT_CHECK: self = .constraintCheckFailed
            case SQLITE_CONSTRAINT_COMMITHOOK: self = .constraintCommitHookFailed
            case SQLITE_CONSTRAINT_FOREIGNKEY: self = .constraintForeignKeyFailed
            case SQLITE_CONSTRAINT_FUNCTION: self = .constraintUserFunctionFailed
            case SQLITE_CONSTRAINT_NOTNULL: self = .constraintNotNullFailed
            case SQLITE_CONSTRAINT_PRIMARYKEY: self = .constraintPrimaryKeyFailed
            case SQLITE_CONSTRAINT_TRIGGER: self = .constraintTriggerFailed
            case SQLITE_CONSTRAINT_UNIQUE: self = .constraintUniqueFailed
            case SQLITE_CONSTRAINT_VTAB: self = .constraintVirtualTableFailed
            case SQLITE_CONSTRAINT_ROWID: self = .constraintUniqueRowIDFailed
            case SQLITE_CONSTRAINT_PINNED: self = .constraintUpdateTriggerDeletedRow
            case SQLITE_CONSTRAINT_DATATYPE: self = .constraintStrictDataTypeFailed
            case SQLITE_AUTH_USER: self = .authUnauthorizedUser
            case SQLITE_NOTICE_RECOVER_WAL: self = .noticeRecoverWAL
            case SQLITE_NOTICE_RECOVER_ROLLBACK: self = .noticeRecoverRollback
            case SQLITE_WARNING_AUTOINDEX: self = .warningAutoindex

            default: self = .error
            }
        }
    }
}

/// Redefinitions of SQLite's extended result codes, from `sqlite3.h`. ClangImporter still doesn't import these.
let SQLITE_ERROR_MISSING_COLLSEQ: Int32 = (SQLITE_ERROR | (1<<8))
let SQLITE_ERROR_RETRY: Int32 = (SQLITE_ERROR | (2<<8))
let SQLITE_ERROR_SNAPSHOT: Int32 = (SQLITE_ERROR | (3<<8))
let SQLITE_IOERR_READ: Int32 = (SQLITE_IOERR | (1<<8))
let SQLITE_IOERR_SHORT_READ: Int32 = (SQLITE_IOERR | (2<<8))
let SQLITE_IOERR_WRITE: Int32 = (SQLITE_IOERR | (3<<8))
let SQLITE_IOERR_FSYNC: Int32 = (SQLITE_IOERR | (4<<8))
let SQLITE_IOERR_DIR_FSYNC: Int32 = (SQLITE_IOERR | (5<<8))
let SQLITE_IOERR_TRUNCATE: Int32 = (SQLITE_IOERR | (6<<8))
let SQLITE_IOERR_FSTAT: Int32 = (SQLITE_IOERR | (7<<8))
let SQLITE_IOERR_UNLOCK: Int32 = (SQLITE_IOERR | (8<<8))
let SQLITE_IOERR_RDLOCK: Int32 = (SQLITE_IOERR | (9<<8))
let SQLITE_IOERR_DELETE: Int32 = (SQLITE_IOERR | (10<<8))
let SQLITE_IOERR_BLOCKED: Int32 = (SQLITE_IOERR | (11<<8))
let SQLITE_IOERR_NOMEM: Int32 = (SQLITE_IOERR | (12<<8))
let SQLITE_IOERR_ACCESS: Int32 = (SQLITE_IOERR | (13<<8))
let SQLITE_IOERR_CHECKRESERVEDLOCK: Int32 = (SQLITE_IOERR | (14<<8))
let SQLITE_IOERR_LOCK: Int32 = (SQLITE_IOERR | (15<<8))
let SQLITE_IOERR_CLOSE: Int32 = (SQLITE_IOERR | (16<<8))
let SQLITE_IOERR_DIR_CLOSE: Int32 = (SQLITE_IOERR | (17<<8))
let SQLITE_IOERR_SHMOPEN: Int32 = (SQLITE_IOERR | (18<<8))
let SQLITE_IOERR_SHMSIZE: Int32 = (SQLITE_IOERR | (19<<8))
let SQLITE_IOERR_SHMLOCK: Int32 = (SQLITE_IOERR | (20<<8))
let SQLITE_IOERR_SHMMAP: Int32 = (SQLITE_IOERR | (21<<8))
let SQLITE_IOERR_SEEK: Int32 = (SQLITE_IOERR | (22<<8))
let SQLITE_IOERR_DELETE_NOENT: Int32 = (SQLITE_IOERR | (23<<8))
let SQLITE_IOERR_MMAP: Int32 = (SQLITE_IOERR | (24<<8))
let SQLITE_IOERR_GETTEMPPATH: Int32 = (SQLITE_IOERR | (25<<8))
let SQLITE_IOERR_CONVPATH: Int32 = (SQLITE_IOERR | (26<<8))
let SQLITE_IOERR_VNODE: Int32 = (SQLITE_IOERR | (27<<8))
let SQLITE_IOERR_AUTH: Int32 = (SQLITE_IOERR | (28<<8))
let SQLITE_IOERR_BEGIN_ATOMIC: Int32 = (SQLITE_IOERR | (29<<8))
let SQLITE_IOERR_COMMIT_ATOMIC: Int32 = (SQLITE_IOERR | (30<<8))
let SQLITE_IOERR_ROLLBACK_ATOMIC: Int32 = (SQLITE_IOERR | (31<<8))
let SQLITE_IOERR_DATA: Int32 = (SQLITE_IOERR | (32<<8))
let SQLITE_IOERR_CORRUPTFS: Int32 = (SQLITE_IOERR | (33<<8))
let SQLITE_IOERR_IN_PAGE: Int32 = (SQLITE_IOERR | (34<<8))
let SQLITE_LOCKED_SHAREDCACHE: Int32 = (SQLITE_LOCKED | (1<<8))
let SQLITE_LOCKED_VTAB: Int32 = (SQLITE_LOCKED | (2<<8))
let SQLITE_BUSY_RECOVERY: Int32 = (SQLITE_BUSY | (1<<8))
let SQLITE_BUSY_SNAPSHOT: Int32 = (SQLITE_BUSY | (2<<8))
let SQLITE_BUSY_TIMEOUT: Int32 = (SQLITE_BUSY | (3<<8))
let SQLITE_CANTOPEN_NOTEMPDIR: Int32 = (SQLITE_CANTOPEN | (1<<8))
let SQLITE_CANTOPEN_ISDIR: Int32 = (SQLITE_CANTOPEN | (2<<8))
let SQLITE_CANTOPEN_FULLPATH: Int32 = (SQLITE_CANTOPEN | (3<<8))
let SQLITE_CANTOPEN_CONVPATH: Int32 = (SQLITE_CANTOPEN | (4<<8))
let SQLITE_CANTOPEN_SYMLINK: Int32 = (SQLITE_CANTOPEN | (6<<8))
let SQLITE_CORRUPT_VTAB: Int32 = (SQLITE_CORRUPT | (1<<8))
let SQLITE_CORRUPT_SEQUENCE: Int32 = (SQLITE_CORRUPT | (2<<8))
let SQLITE_CORRUPT_INDEX: Int32 = (SQLITE_CORRUPT | (3<<8))
let SQLITE_READONLY_RECOVERY: Int32 = (SQLITE_READONLY | (1<<8))
let SQLITE_READONLY_CANTLOCK: Int32 = (SQLITE_READONLY | (2<<8))
let SQLITE_READONLY_ROLLBACK: Int32 = (SQLITE_READONLY | (3<<8))
let SQLITE_READONLY_DBMOVED: Int32 = (SQLITE_READONLY | (4<<8))
let SQLITE_READONLY_CANTINIT: Int32 = (SQLITE_READONLY | (5<<8))
let SQLITE_READONLY_DIRECTORY: Int32 = (SQLITE_READONLY | (6<<8))
let SQLITE_ABORT_ROLLBACK: Int32 = (SQLITE_ABORT | (2<<8))
let SQLITE_CONSTRAINT_CHECK: Int32 = (SQLITE_CONSTRAINT | (1<<8))
let SQLITE_CONSTRAINT_COMMITHOOK: Int32 = (SQLITE_CONSTRAINT | (2<<8))
let SQLITE_CONSTRAINT_FOREIGNKEY: Int32 = (SQLITE_CONSTRAINT | (3<<8))
let SQLITE_CONSTRAINT_FUNCTION: Int32 = (SQLITE_CONSTRAINT | (4<<8))
let SQLITE_CONSTRAINT_NOTNULL: Int32 = (SQLITE_CONSTRAINT | (5<<8))
let SQLITE_CONSTRAINT_PRIMARYKEY: Int32 = (SQLITE_CONSTRAINT | (6<<8))
let SQLITE_CONSTRAINT_TRIGGER: Int32 = (SQLITE_CONSTRAINT | (7<<8))
let SQLITE_CONSTRAINT_UNIQUE: Int32 = (SQLITE_CONSTRAINT | (8<<8))
let SQLITE_CONSTRAINT_VTAB: Int32 = (SQLITE_CONSTRAINT | (9<<8))
let SQLITE_CONSTRAINT_ROWID: Int32 = (SQLITE_CONSTRAINT | (10<<8))
let SQLITE_CONSTRAINT_PINNED: Int32 = (SQLITE_CONSTRAINT | (11<<8))
let SQLITE_CONSTRAINT_DATATYPE: Int32 = (SQLITE_CONSTRAINT | (12<<8))
let SQLITE_NOTICE_RECOVER_WAL: Int32 = (SQLITE_NOTICE | (1<<8))
let SQLITE_NOTICE_RECOVER_ROLLBACK: Int32 = (SQLITE_NOTICE | (2<<8))
let SQLITE_NOTICE_RBU: Int32 = (SQLITE_NOTICE | (3<<8))
let SQLITE_WARNING_AUTOINDEX: Int32 = (SQLITE_WARNING | (1<<8))
let SQLITE_AUTH_USER: Int32 = (SQLITE_AUTH | (1<<8))
