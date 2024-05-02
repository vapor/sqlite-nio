/*

Significant portions of this file have been adapted by @danramteke 
from https://github.com/groue/GRDB.swift/blob/v5.8.0/Tests/GRDBTests/DatabaseFunctionTests.swift
Here is the original copyright notice:

Copyright (C) 2015-2020 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
import XCTest
import SQLiteNIO
import NIOFoundationCompat

private struct CustomValueType: SQLiteDataConvertible, Equatable {
	init() {}
	init?(sqliteData: SQLiteData) {
		guard let string = sqliteData.string, string == "CustomValueType" else {
			return nil
		}
		self = CustomValueType()
	}

	var sqliteData: SQLiteData? {
		.text("CustomValueType")
	}
}

final class DatabaseFunctionTests: XCTestCase {
	// MARK: - Return values

	func testFunctionReturningNull() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in nil }
            try await conn.install(customFunction: fn)

            await XCTAssertAsync(try await conn.query("SELECT f() as result").first?.column("result")?.isNull ?? false)
        }
	}

	func testFunctionReturningInt64() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in 1 }
            try await conn.install(customFunction: fn)
            await XCTAssertEqualAsync(Int(1), try await conn.query("SELECT f() as result").first?.column("result")?.integer)
        }
	}

	func testFunctionReturningDouble() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in 1e100 }
            
            try await conn.install(customFunction: fn)
            await XCTAssertEqualAsync(1e100, try await conn.query("SELECT f() as result").first?.column("result")?.double)
        }
	}

	func testFunctionReturningString() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in "foo" }
            
            try await conn.install(customFunction: fn)
            await XCTAssertEqualAsync("foo", try await conn.query("SELECT f() as result").first?.column("result")?.string)
        }
	}

	func testFunctionReturningData() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in Data("foo".utf8) }
            try await conn.install(customFunction: fn)

            await XCTAssertEqualAsync(ByteBuffer(string: "foo"), try await conn.query("SELECT f() as result").first?.column("result")?.blob)
            await XCTAssertNotEqualAsync(ByteBuffer(string: "bar"), try await conn.query("SELECT f() as result").first?.column("result")?.blob)
        }
	}

	func testFunctionReturningCustomValueType() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in CustomValueType() }
            
            try await conn.install(customFunction: fn)
            await XCTAssertEqualAsync(CustomValueType().sqliteData, try await conn.query("SELECT f() as result").first?.column("result"))
        }
	}

	// MARK: - Argument values

	func testFunctionArgumentNil() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].isNull }
            try await conn.install(customFunction: fn)

            await XCTAssertTrueAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.bool ?? false)
            await XCTAssertFalseAsync(try await conn.query("SELECT f(1) as result").first?.column("result")?.bool ?? true)
            await XCTAssertFalseAsync(try await conn.query("SELECT f(1.1) as result").first?.column("result")?.bool ?? true)
            await XCTAssertFalseAsync(try await conn.query("SELECT f('foo') as result").first?.column("result")?.bool ?? true)
            await XCTAssertFalseAsync(try await conn.query("SELECT f(?) as result", [.text("foo")]).first?.column("result")?.bool ?? true)
        }
	}

	func testFunctionArgumentInt64() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].integer }
            try await conn.install(customFunction: fn)

            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.integer)
            await XCTAssertEqualAsync(1, try await conn.query("SELECT f(1) as result").first?.column("result")?.integer)
            await XCTAssertEqualAsync(1, try await conn.query("SELECT f(1.1) as result").first?.column("result")?.integer)
        }
	}

	func testFunctionArgumentDouble() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].double }
            try await conn.install(customFunction: fn)
            
            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.double)
            await XCTAssertEqualAsync(1.0, try await conn.query("SELECT f(1) as result").first?.column("result")?.double)
            await XCTAssertEqualAsync(1.1, try await conn.query("SELECT f(1.1) as result").first?.column("result")?.double)
        }
	}

	func testFunctionArgumentString() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].string }
            try await conn.install(customFunction: fn)

            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.string)
            await XCTAssertEqualAsync("foo", try await conn.query("SELECT f('foo') as result").first?.column("result")?.string)
        }
	}

	func testFunctionArgumentBlob() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].blob }
            try await conn.install(customFunction: fn)

            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.blob)
            await XCTAssertEqualAsync(ByteBuffer(string: "foo"), try await conn.query("SELECT f(?) as result", [.blob(ByteBuffer(string: "foo"))]).first?.column("result")?.blob)
            await XCTAssertEqualAsync(ByteBuffer(), try await conn.query("SELECT f(?) as result", [.blob(ByteBuffer())]).first?.column("result")?.blob)
        }
	}

	func testFunctionArgumentCustomValueType() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in CustomValueType(sqliteData: values[0]) }
            try await conn.install(customFunction: fn)
            
            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result").flatMap(CustomValueType.init(sqliteData:)))
            await XCTAssertEqualAsync(CustomValueType(), try await conn.query("SELECT f('CustomValueType') as result").first?.column("result").flatMap(CustomValueType.init(sqliteData:)))
        }
	}

	// MARK: - Argument count

	func testFunctionWithoutArgument() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in "foo" }
            try await conn.install(customFunction: fn)
            
            await XCTAssertEqualAsync("foo", try await conn.query("SELECT f() as result").first?.column("result")?.string)
            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT f(1)")) {
                guard let error = $0 as? SQLiteError else { return XCTFail("Expected SQLiteError, got \(String(reflecting: $0))") }
                XCTAssertEqual(error.reason, .error)
                XCTAssertEqual(error.message, "wrong number of arguments to function f()")
            }
        }
	}

	func testFunctionOfOneArgument() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values.first?.string?.uppercased() }
            try await conn.install(customFunction: fn)

            await XCTAssertNilAsync(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.string)
            await XCTAssertEqualAsync("ROUé", try await conn.query("SELECT upper(?) as result", [.text("Roué")]).first?.column("result")?.string)
            await XCTAssertEqualAsync("ROUÉ", try await conn.query("SELECT f(?) as result", [.text("Roué")]).first?.column("result")?.string)
            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT f()")) {
                guard let error = $0 as? SQLiteError else { return XCTFail("Expected SQLiteError, got \(String(reflecting: $0))") }
                XCTAssertEqual(error.reason, .error)
                XCTAssertEqual(error.message, "wrong number of arguments to function f()")
            }
        }
    }

	func testFunctionOfTwoArguments() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 2) { values in values.compactMap { $0.integer }.reduce(0, +) }
            try await conn.install(customFunction: fn)
            
            await XCTAssertEqualAsync(3, try await conn.query("SELECT f(1, 2) as result").first?.column("result")?.integer)
            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT f()")) {
                guard let error = $0 as? SQLiteError else { return XCTFail("Expected SQLiteError, got \(String(reflecting: $0))") }
                XCTAssertEqual(error.reason, .error)
                XCTAssertEqual(error.message, "wrong number of arguments to function f()")
            }
        }
	}

	func testVariadicFunction() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f") { values in values.count }
            try await conn.install(customFunction: fn)

            await XCTAssertEqualAsync(0, try await conn.query("SELECT f() as result").first?.column("result")?.integer)
            await XCTAssertEqualAsync(1, try await conn.query("SELECT f(1) as result").first?.column("result")?.integer)
            await XCTAssertEqualAsync(2, try await conn.query("SELECT f(1, 2) as result").first?.column("result")?.integer)
            await XCTAssertEqualAsync(3, try await conn.query("SELECT f(1, 1, 1) as result").first?.column("result")?.integer)
        }
	}

	// MARK: - Errors

	func testFunctionThrowingDatabaseCustomErrorWithMessage() async throws {
        try await withOpenedConnection { conn in
            struct MyError: Error { let message: String }
            let fn = SQLiteCustomFunction("f") { _ in throw MyError(message: "custom message") }
            try await conn.install(customFunction: fn)

            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT f()")) {
                guard let error = $0 as? SQLiteError else { return XCTFail("Expected SQLiteError, got \(String(reflecting: $0))") }
                XCTAssertEqual(error.reason, .error)
                XCTAssertEqual(error.message, "MyError(message: \"custom message\")")
            }
        }
	}

	func testFunctionThrowingNSError() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f") { _ in
                throw NSError(domain: "CustomErrorDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "custom error message", NSLocalizedFailureReasonErrorKey: "custom error message"])
            }
            try await conn.install(customFunction: fn)

            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT f()")) {
                guard let error = $0 as? SQLiteError else { return XCTFail("Expected SQLiteError, got \(String(reflecting: $0))") }
                XCTAssertEqual(error.reason, .error)
                XCTAssertTrue(error.message.contains("CustomErrorDomain"))
                XCTAssertTrue(error.message.contains("123"))
                XCTAssertTrue(error.message.contains("custom error message"), "expected '\(error.message)' to contain 'custom error message'")
            }
        }
	}

	// MARK: - Misc

	func testFunctionsCanBeExtremelyUnsafeClosures() async throws {
        try await withOpenedConnection { conn in
            final class QuickBox<T: Sendable>: @unchecked Sendable { var value: T; init(_ value: T) { self.value = value } }
            let x = QuickBox(123)
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in x.value }
            try await conn.install(customFunction: fn)
            
            x.value = 321
            await XCTAssertEqualAsync(321, try await conn.query("SELECT f() as result").first?.column("result")?.integer)
        }
	}

	// MARK: - setup

    override class func setUp() {
        XCTAssert(isLoggingConfigured)
    }
}
