#if SQLCipher
import NIOCore
import NIOPosix
import Logging
import Foundation
import CSQLCipher

extension SQLiteConnection {

    // MARK: - Encryption

    /// Sets the passphrase used to crypt and decrypt an SQLCipher database.
    ///
    /// Call this method after opening the connection but before executing any queries.
    /// This is typically done in a configuration prepare block or immediately after connection.
    ///
    /// - Parameter passphrase: The passphrase string to use for encryption/decryption.
    /// - Returns: A future indicating completion of the passphrase setting operation.
    public func usePassphrase(_ passphrase: String) -> EventLoopFuture<Void> {
        guard !passphrase.isEmpty else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "Passphrase cannot be empty"))
        }
        guard var data = passphrase.data(using: .utf8) else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "Passphrase contains invalid UTF-8 characters"))
        }
        defer {
            data.resetBytes(in: 0..<data.count)
        }
        return self.usePassphrase(data)
    }

    /// Sets the passphrase used to crypt and decrypt an SQLCipher database.
    ///
    /// Call this method after opening the connection but before executing any queries.
    /// This is typically done in a configuration prepare block or immediately after connection.
    ///
    /// - Parameter passphrase: The passphrase data to use for encryption/decryption.
    /// - Returns: A future indicating completion of the passphrase setting operation.
    public func usePassphrase(_ passphrase: Data) -> EventLoopFuture<Void> {
        guard !passphrase.isEmpty else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "Passphrase data cannot be empty"))
        }
        return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            let code = passphrase.withUnsafeBytes {
                sqlite_nio_sqlite3_key(self.handle.raw, $0.baseAddress, CInt($0.count))
            }
            guard code == SQLITE_OK else {
                throw SQLiteError(statusCode: code, connection: self)
            }
        }
    }

    /// Changes the passphrase used by an SQLCipher encrypted database.
    ///
    /// > Warning: `sqlite3_rekey` is discouraged by the SQLCipher team in favor of
    /// > attaching a new database with the desired encryption options and using
    /// > `sqlcipher_export()` to migrate the contents and schema.
    ///
    /// - Parameter passphrase: The new passphrase string to use for encryption.
    /// - Returns: A future indicating completion of the passphrase change operation.
    public func changePassphrase(_ passphrase: String) -> EventLoopFuture<Void> {
        guard !passphrase.isEmpty else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "New passphrase cannot be empty"))
        }
        guard var data = passphrase.data(using: .utf8) else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "New passphrase contains invalid UTF-8 characters"))
        }
        defer {
            data.resetBytes(in: 0..<data.count)
        }
        return self.changePassphrase(data)
    }

    /// Changes the passphrase used by an SQLCipher encrypted database.
    ///
    /// > Warning: `sqlite3_rekey` is discouraged by the SQLCipher team in favor of
    /// > attaching a new database with the desired encryption options and using
    /// > `sqlcipher_export()` to migrate the contents and schema.
    ///
    /// - Parameter passphrase: The new passphrase data to use for encryption.
    /// - Returns: A future indicating completion of the passphrase change operation.
    public func changePassphrase(_ passphrase: Data) -> EventLoopFuture<Void> {
        guard !passphrase.isEmpty else {
            return self.eventLoop.makeFailedFuture(SQLiteError(reason: .misuse, message: "New passphrase data cannot be empty"))
        }
        return self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            let code = passphrase.withUnsafeBytes {
                sqlite_nio_sqlite3_rekey(self.handle.raw, $0.baseAddress, CInt($0.count))
            }
            guard code == SQLITE_OK else {
                throw SQLiteError(statusCode: code, connection: self)
            }
        }
    }
}

// MARK: - Async Encryption Methods

extension SQLiteConnection {

    /// Sets the passphrase used to crypt and decrypt an SQLCipher database (async version).
    ///
    /// Call this method after opening the connection but before executing any queries.
    /// This is typically done in a configuration prepare block or immediately after connection.
    ///
    /// - Parameter passphrase: The passphrase string to use for encryption/decryption.
    public func usePassphrase(_ passphrase: String) async throws {
        try await self.usePassphrase(passphrase).get()
    }

    /// Sets the passphrase used to crypt and decrypt an SQLCipher database (async version).
    ///
    /// Call this method after opening the connection but before executing any queries.
    /// This is typically done in a configuration prepare block or immediately after connection.
    ///
    /// - Parameter passphrase: The passphrase data to use for encryption/decryption.
    public func usePassphrase(_ passphrase: Data) async throws {
        try await self.usePassphrase(passphrase).get()
    }

    /// Changes the passphrase used by an SQLCipher encrypted database (async version).
    ///
    /// > Warning: `sqlite3_rekey` is discouraged by the SQLCipher team in favor of
    /// > attaching a new database with the desired encryption options and using
    /// > `sqlcipher_export()` to migrate the contents and schema.
    ///
    /// - Parameter passphrase: The new passphrase string to use for encryption.
    public func changePassphrase(_ passphrase: String) async throws {
        try await self.changePassphrase(passphrase).get()
    }

    /// Changes the passphrase used by an SQLCipher encrypted database (async version).
    ///
    /// > Warning: `sqlite3_rekey` is discouraged by the SQLCipher team in favor of
    /// > attaching a new database with the desired encryption options and using
    /// > `sqlcipher_export()` to migrate the contents and schema.
    ///
    /// - Parameter passphrase: The new passphrase data to use for encryption.
    public func changePassphrase(_ passphrase: Data) async throws {
        try await self.changePassphrase(passphrase).get()
    }
}
#endif
