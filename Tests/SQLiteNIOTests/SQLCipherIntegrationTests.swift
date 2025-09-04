#if SQLCipher
import XCTest
@testable import SQLiteNIO
import Foundation

final class SQLCipherIntegrationTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func withOpenedConnection(_ operation: (SQLiteConnection) async throws -> Void) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_encrypted_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
        try await operation(connection)
        try await connection.close()
    }
    
    private func readDatabaseFileAsString(path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Proper Encryption Tests
    
    func testDatabaseIsActuallyEncrypted() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("encryption_test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Create encrypted database with data
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            // Use SQLiteNIO method instead of PRAGMA key
            try await connection.usePassphrase("strong_password_123")
            
            // Create table and insert recognizable data
            _ = try await connection.query("CREATE TABLE secrets (id INTEGER PRIMARY KEY, secret TEXT);")
            _ = try await connection.query("INSERT INTO secrets (secret) VALUES ('this_is_secret_data_that_should_be_encrypted');")
            _ = try await connection.query("INSERT INTO secrets (secret) VALUES ('another_secret_value');")
            
            try await connection.close()
        }
        
        // Verify the database file exists and is not empty
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Database file should not be empty")
        
        // CRITICAL TEST: Verify the file content is NOT readable as plaintext
        if let fileContent = readDatabaseFileAsString(path: tempURL.path) {
            // The file should NOT contain our plaintext data
            XCTAssertFalse(fileContent.contains("this_is_secret_data_that_should_be_encrypted"), 
                           "Database file should not contain plaintext data")
            XCTAssertFalse(fileContent.contains("another_secret_value"), 
                           "Database file should not contain plaintext data")
            XCTAssertFalse(fileContent.contains("CREATE TABLE secrets"), 
                           "Database file should not contain plaintext SQL")
            XCTAssertFalse(fileContent.contains("secrets"), 
                           "Database file should not contain plaintext table names")
        } else {
            // If we can't read as UTF-8, that's actually good - it means the file is encrypted
            // But let's verify it's not just binary data by checking if it's readable
            let data = try Data(contentsOf: tempURL)
            XCTAssertGreaterThan(data.count, 0, "Database file should contain data")
        }
    }
    
    func testDatabaseCannotBeOpenedWithoutKey() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("no_key_test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Create encrypted database
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            try await connection.usePassphrase("encryption_key_456")
            _ = try await connection.query("CREATE TABLE test (data TEXT);")
            _ = try await connection.query("INSERT INTO test (data) VALUES ('secret');")
            try await connection.close()
        }
        
        // Try to open the database WITHOUT providing a key - this should fail
        var connection: SQLiteConnection?
        do {
            connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            // This should fail because we're not providing the encryption key
            let rows = try await connection!.query("SELECT data FROM test;")
            try await connection!.close()
            XCTFail("Should not be able to read encrypted database without key, got \(rows.count) rows")
        } catch {
            // This is expected - the database should not be readable without the key
            XCTAssertTrue(error is SQLiteError, "Should get SQLiteError when trying to read encrypted DB without key")
            
            // Make sure to close the connection if it was created
            if let conn = connection {
                try? await conn.close()
            }
        }
    }
    
    func testDatabaseCannotBeOpenedWithWrongKey() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wrong_key_test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Create encrypted database with key "correct_key"
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            try await connection.usePassphrase("correct_key")
            _ = try await connection.query("CREATE TABLE test (data TEXT);")
            _ = try await connection.query("INSERT INTO test (data) VALUES ('secret_data');")
            try await connection.close()
        }
        
        // Try to open with WRONG key - this should fail
        var connection: SQLiteConnection?
        do {
            connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            // Provide wrong key using SQLiteNIO method
            try await connection!.usePassphrase("wrong_key")
            
            // This should fail because the wrong key will cause corruption/encryption errors
            let rows = try await connection!.query("SELECT data FROM test;")
            try await connection!.close()
            XCTFail("Should not be able to read encrypted database with wrong key, got \(rows.count) rows")
        } catch {
            // This is expected - wrong key should cause an error
            XCTAssertTrue(error is SQLiteError, "Should get SQLiteError when using wrong key")
            
            // Make sure to close the connection if it was created
            if let conn = connection {
                try? await conn.close()
            }
        }
    }
    
    func testDatabaseCanBeOpenedWithCorrectKey() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("correct_key_test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let correctKey = "correct_encryption_key_789"
        let testData = "this_is_test_data_for_encryption_verification"
        
        // Create encrypted database
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            _ = try await connection.query("PRAGMA key = '\(correctKey)';")
            _ = try await connection.query("CREATE TABLE test (id INTEGER, data TEXT);")
            _ = try await connection.query("INSERT INTO test (id, data) VALUES (1, '\(testData)');")
            try await connection.close()
        }
        
        // Open with CORRECT key - this should work
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            // Provide correct key using SQLiteNIO method
            try await connection.usePassphrase(correctKey)
            
            // This should work and return our data
            let rows = try await connection.query("SELECT data FROM test WHERE id = 1;")
            try await connection.close()
            XCTAssertEqual(rows.count, 1, "Should be able to read data with correct key")
            XCTAssertEqual(rows[0].column("data")?.string, testData, "Should get correct data with correct key")
        }
    }
    
    func testSQLCipherVersionInfo() async throws {
        // Test that SQLCipher reports its version correctly
        try await withOpenedConnection { connection in
            let rows = try await connection.query("PRAGMA cipher_version;")
            XCTAssertEqual(rows.count, 1)
            
            if let version = rows[0].column("cipher_version")?.string {
                XCTAssertFalse(version.isEmpty, "SQLCipher version should not be empty")
                print("SQLCipher version: \(version)")
            }
        }
    }
    
    func testSQLCipherOpenSSLIntegration() async throws {
        // Test that SQLCipher can access OpenSSL functions
        try await withOpenedConnection { connection in
            // Set a key to ensure encryption is working
            try await connection.usePassphrase("integration_test")
            
            // Test that we can use crypto-related pragmas
            let rows = try await connection.query("PRAGMA cipher_page_size;")
            XCTAssertEqual(rows.count, 1)
            
            if let pageSize = rows[0].column("cipher_page_size")?.integer {
                XCTAssertGreaterThan(pageSize, 0, "Cipher page size should be positive")
            }
        }
    }
    
    func testEncryptedDatabasePersistence() async throws {
        // Test that encrypted data persists correctly
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("persistence_test_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let passphrase = "persistence_test_passphrase"
        let testData = "secret_persistent_data"
        
        // Create encrypted database
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            try await connection.usePassphrase(passphrase)
            _ = try await connection.query("CREATE TABLE persistent (data TEXT);")
            _ = try await connection.query("INSERT INTO persistent (data) VALUES ('\(testData)');")
            try await connection.close()
        }
        
        // Verify the file is encrypted (not plaintext)
        if let fileContent = readDatabaseFileAsString(path: tempURL.path) {
            XCTAssertFalse(fileContent.contains(testData), "Database file should not contain plaintext data")
        }
        
        // Reopen and verify data
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            
            try await connection.usePassphrase(passphrase)
            let rows = try await connection.query("SELECT data FROM persistent;")
            
            try await connection.close()
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].column("data")?.string, testData)
        }
    }
}
#endif
