#if SQLCipher
import XCTest
@testable import SQLiteNIO

final class SQLCipherIntegrationTests: XCTestCase {
    func testSQLCipherBasicEncryption() async throws {
        // Test that we can create an encrypted database with SQLCipher
        try await withOpenedConnection { connection in
            // Set encryption key (this should work if SQLCipher is properly linked with OpenSSL)
            _ = try await connection.query("PRAGMA key = 'test_password';")
            
            // Create a test table
            _ = try await connection.query("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);")
            
            // Insert test data
            _ = try await connection.query("INSERT INTO test (name) VALUES ('encrypted_data');")
            
            // Query the data back
            let rows = try await connection.query("SELECT name FROM test;")
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].column("name")?.string, "encrypted_data")
        }
    }
    
    func testSQLCipherVersionInfo() async throws {
        // Test that SQLCipher reports its version correctly
        try await withOpenedConnection { connection in
            let rows = try await connection.query("PRAGMA cipher_version;")
            XCTAssertEqual(rows.count, 1)
            
            if let version = rows[0].column("cipher_version")?.string {
                XCTAssertFalse(version.isEmpty, "SQLCipher version should not be empty")
            }
        }
    }
    
    func testSQLCipherOpenSSLIntegration() async throws {
        // Test that SQLCipher can access OpenSSL functions
        try await withOpenedConnection { connection in
            // Set a key to ensure encryption is working
            _ = try await connection.query("PRAGMA key = 'integration_test';")
            
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
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_encrypted.db")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Create encrypted database
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            do {
                _ = try await connection.query("PRAGMA key = 'persistence_test';")
                _ = try await connection.query("CREATE TABLE persistent (data TEXT);")
                _ = try await connection.query("INSERT INTO persistent (data) VALUES ('secret_data');")
                try await connection.close()
            } catch {
                try? await connection.close()
                throw error
            }
        }
        
        // Reopen and verify data
        do {
            let connection = try await SQLiteConnection.open(storage: .file(path: tempURL.path))
            do {
                _ = try await connection.query("PRAGMA key = 'persistence_test';")
                let rows = try await connection.query("SELECT data FROM persistent;")
                
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows[0].column("data")?.string, "secret_data")
                try await connection.close()
            } catch {
                try? await connection.close()
                throw error
            }
        }
    }
}
#endif
