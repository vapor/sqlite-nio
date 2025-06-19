#if SQLCipher
import XCTest
@testable import SQLiteNIO

final class OpenSSLInfoTests: XCTestCase {
    func testSQLCipherVersionAvailable() async throws {
        try await withOpenedConnection { connection in
            let rows = try await connection.query("PRAGMA cipher_version;")
            XCTAssertEqual(rows.count, 1)
            
            if let version = rows[0].column("cipher_version")?.string {
                XCTAssertFalse(version.isEmpty, "SQLCipher version should not be empty")
            }
        }
    }
    
    func testSQLCipherCompileOptions() async throws {
        try await withOpenedConnection { connection in
            let rows = try await connection.query("PRAGMA compile_options;")
            XCTAssertGreaterThan(rows.count, 0, "Should have compile options")
            
            let options = rows.compactMap { $0.column("compile_options")?.string }
            let hasCodec = options.contains { $0.contains("HAS_CODEC") }
            XCTAssertTrue(hasCodec, "Should have SQLITE_HAS_CODEC compile option")
        }
    }
    
    func testSQLCipherCryptoFunctionality() async throws {
        try await withOpenedConnection { connection in
            _ = try await connection.query("PRAGMA key = 'test_key';")
            
            let rows = try await connection.query("PRAGMA cipher_page_size;")
            XCTAssertEqual(rows.count, 1)
            
            if let pageSize = rows[0].column("cipher_page_size")?.integer {
                XCTAssertGreaterThan(pageSize, 0, "Cipher page size should be positive")
            }
        }
    }
    
    func testSQLCipherMemorySecurityOptions() async throws {
        try await withOpenedConnection { connection in
            _ = try await connection.query("PRAGMA key = 'security_test';")
            
            let rows = try await connection.query("PRAGMA cipher_memory_security;")
            XCTAssertEqual(rows.count, 1)
        }
    }
}
#endif
